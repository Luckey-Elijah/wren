import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

/// The result of checking or performing a Wren self-upgrade.
class WrenUpgradeResult {
  /// Creates an upgrade result.
  const new({required this.version, required this.upgraded});

  /// Version currently installed after this operation.
  final String version;

  /// Whether a newer Wren executable was installed.
  final bool upgraded;
}

/// A self-upgrade failure with user-facing recovery guidance.
class WrenUpgradeException implements Exception {
  /// Creates a self-upgrade failure.
  const new(this.message);

  /// Explanation and any manual recovery guidance.
  final String message;

  @override
  String toString() => message;
}

/// Downloads and atomically replaces the running Wren executable.
class WrenSelfUpgrade {
  /// Creates an upgrade operation for one invocation.
  new({
    required this.currentVersion,
    required this.hostAssetName,
    required this.executablePath,
    required this.dataDirectory,
    required this.stdout,
    required this.stderr,
    Uri? releaseApiUri,
  }) : releaseApiUri = releaseApiUri ?? _defaultReleaseApiUri;

  static final Uri _defaultReleaseApiUri = Uri.parse(
    'https://api.github.com/repos/Luckey-Elijah/wren/releases?per_page=100',
  );

  /// The version compiled into the currently running Wren executable.
  final String currentVersion;

  /// Native release asset suffix, such as linux-x64.
  final String hostAssetName;

  /// Path to the running Wren executable.
  final String executablePath;

  /// Wren data directory, where the previous working executable is retained.
  final String dataDirectory;

  /// Release-list endpoint; overridable for local fixture servers.
  final Uri releaseApiUri;

  /// Human-readable command output.
  final StringSink stdout;

  /// Diagnostics and progress output.
  final StringSink stderr;

  /// Finds the highest newer stable release and upgrades when one exists.
  Future<WrenUpgradeResult> run() async {
    final current = _parseVersion(currentVersion);
    final executable = _validateExecutable(executablePath);
    final originalDigest = await _digestFile(executable);

    final client = io.HttpClient();
    Directory? staging;
    try {
      final releases = await _fetchReleases(client);
      final candidates =
          releases
              .where((release) => release.version.compareTo(current) > 0)
              .toList()
            ..sort((left, right) => right.version.compareTo(left.version));

      if (candidates.isEmpty) {
        stdout.writeln(
          'Wren $currentVersion is already at the latest stable release.',
        );
        return WrenUpgradeResult(version: currentVersion, upgraded: false);
      }

      final selected = candidates.first;
      final archiveName = 'wren-${selected.version}-$hostAssetName.tar.gz';
      final archiveUrl = selected.assetUrls[archiveName];
      final checksumUrl = selected.assetUrls['$archiveName.sha256'];
      if (archiveUrl == null || checksumUrl == null) {
        throw WrenUpgradeException(
          'Wren ${selected.version} does not publish the required '
          '$hostAssetName archive and SHA-256 file. '
          'Install it manually from the Wren releases.',
        );
      }
      _validateAssetUri(archiveUrl);
      _validateAssetUri(checksumUrl);

      final parent = executable.parent;
      try {
        staging = await parent.createTemp('.wren-upgrade-');
      } on Object catch (error) {
        throw WrenUpgradeException(
          'cannot stage an upgrade beside $executablePath: $error. '
          'Install the new Wren executable manually.',
        );
      }
      final archive = File(p.join(staging.path, archiveName));
      final checksum = await _getBytes(client, checksumUrl);
      final expectedDigest = _parseChecksum(utf8.decode(checksum), archiveName);
      final archiveBytes = await _getBytes(client, archiveUrl);
      final actualDigest = sha256.convert(archiveBytes).toString();
      if (actualDigest != expectedDigest) {
        throw const WrenUpgradeException(
          'the downloaded Wren archive does not match its SHA-256 checksum. '
          'The installed executable was not changed.',
        );
      }
      await archive.writeAsBytes(archiveBytes, flush: true);

      final packageDirectoryName = 'wren-${selected.version}-$hostAssetName';
      final extractedRoot = Directory(p.join(staging.path, 'extracted'))
        ..createSync();
      await _extractArchive(archive, extractedRoot, packageDirectoryName);
      final candidate = File(
        p.join(extractedRoot.path, packageDirectoryName, 'wren'),
      );
      _validateCandidate(candidate);
      await _verifyVersion(candidate.path, selected.version.toString());

      if (await _digestFile(executable) != originalDigest) {
        throw const WrenUpgradeException(
          'the running Wren executable changed during the upgrade. '
          'No replacement was made; retry after other Wren operations finish.',
        );
      }

      final backup = await _savePreviousExecutable(
        executable,
        selectedCurrentVersion: currentVersion,
      );
      try {
        await candidate.rename(executable.path);
      } on Object catch (error) {
        throw WrenUpgradeException(
          'could not replace $executablePath atomically: $error. '
          'The previous executable is saved at ${backup.path}. '
          'Install the new Wren executable manually.',
        );
      }

      try {
        await _verifyVersion(executable.path, selected.version.toString());
      } on Object catch (error) {
        try {
          final restore = File(
            p.join(
              parent.path,
              '.wren-restore-${io.pid}-'
              '${DateTime.now().microsecondsSinceEpoch}',
            ),
          );
          await backup.copy(restore.path);
          await restore.rename(executable.path);
          await _verifyVersion(executable.path, currentVersion);
        } on Object catch (restoreError) {
          throw WrenUpgradeException(
            'the upgraded executable failed validation ($error), and '
            'automatic rollback also failed ($restoreError). Restore the '
            'working executable from ${backup.path}.',
          );
        }
        throw WrenUpgradeException(
          'the upgraded executable failed validation and was rolled back. '
          'The working Wren $currentVersion executable is restored; '
          'the failed upgrade was not installed.',
        );
      }

      stdout.writeln(
        'Upgraded Wren from $currentVersion to ${selected.version}.',
      );
      return WrenUpgradeResult(
        version: selected.version.toString(),
        upgraded: true,
      );
    } on WrenUpgradeException {
      rethrow;
    } on Object catch (error) {
      throw WrenUpgradeException(
        'could not upgrade Wren: $error. The installed executable was not '
        'changed unless rollback guidance above was printed.',
      );
    } finally {
      client.close(force: true);
      if (staging != null && staging.existsSync()) {
        try {
          await staging.delete(recursive: true);
        } on Object catch (error) {
          stderr.writeln('could not remove upgrade staging files: $error');
        }
      }
    }
  }

  Future<List<_PublishedWrenRelease>> _fetchReleases(
    io.HttpClient client,
  ) async {
    final releases = <_PublishedWrenRelease>[];
    final initial = releaseApiUri;
    var uri = initial.replace(
      queryParameters: <String, String>{
        ...initial.queryParameters,
        'per_page': '100',
        'page': '1',
      },
    );
    var page = 1;
    while (true) {
      final response = await _getResponse(client, uri);
      final decoded = jsonDecode(utf8.decode(response.bytes));
      if (decoded is! List<Object?>) {
        throw const WrenUpgradeException(
          'the Wren release service returned an invalid response.',
        );
      }
      for (final entry in decoded) {
        if (entry is! Map<String, Object?> ||
            entry['draft'] == true ||
            entry['prerelease'] == true) {
          continue;
        }
        final tag = entry['tag_name'];
        if (tag is! String || !tag.startsWith('wren-v')) continue;
        final version = _tryParseStableVersion(tag.substring('wren-v'.length));
        if (version == null) continue;
        final rawAssets = entry['assets'];
        if (rawAssets is! List<Object?>) continue;
        final assets = <String, Uri>{};
        for (final rawAsset in rawAssets) {
          if (rawAsset is! Map<String, Object?>) continue;
          final name = rawAsset['name'];
          final url = rawAsset['browser_download_url'];
          if (name is! String || url is! String) continue;
          final parsedUrl = Uri.tryParse(url);
          if (parsedUrl != null) assets[name] = parsedUrl;
        }
        releases.add(_PublishedWrenRelease(version, assets));
      }
      final next = _nextPage(response.linkHeader);
      if (next == null) break;
      uri = next;
      page++;
      if (page > 100) {
        throw const WrenUpgradeException(
          'the Wren release service returned too many pages.',
        );
      }
    }
    return releases;
  }

  Uri? _nextPage(String? linkHeader) {
    if (linkHeader == null) return null;
    for (final part in linkHeader.split(',')) {
      final match = RegExp(r'<([^>]+)>;\s*rel="next"').firstMatch(part.trim());
      if (match != null) return Uri.tryParse(match.group(1)!);
    }
    return null;
  }

  Future<_VersionedResponse> _getResponse(io.HttpClient client, Uri uri) async {
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 30));
      request.headers
        ..set(io.HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(io.HttpHeaders.userAgentHeader, 'Wren/$currentVersion');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != io.HttpStatus.ok) {
        throw WrenUpgradeException(
          'the Wren release service returned HTTP ${response.statusCode}.',
        );
      }
      final bytes = await response
          .fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (builder, chunk) => builder..add(chunk),
          )
          .timeout(const Duration(seconds: 120));
      return _VersionedResponse(
        bytes.takeBytes(),
        response.headers.value('link'),
      );
    } on WrenUpgradeException {
      rethrow;
    } on Object catch (error) {
      throw WrenUpgradeException(
        'could not read Wren release data from $uri: $error.',
      );
    }
  }

  Future<Uint8List> _getBytes(io.HttpClient client, Uri uri) async =>
      (await _getResponse(client, uri)).bytes;

  void _validateAssetUri(Uri uri) {
    final isLocalFixture =
        releaseApiUri.scheme == 'http' &&
        const {'localhost', '127.0.0.1', '::1'}.contains(releaseApiUri.host);
    final allowed = isLocalFixture
        ? uri.scheme == 'http' &&
              uri.host == releaseApiUri.host &&
              uri.port == releaseApiUri.port
        : uri.scheme == 'https' && uri.host == 'github.com';
    if (!allowed) {
      throw const WrenUpgradeException(
        'the Wren release metadata contains an unexpected asset URL. '
        'The installed executable was not changed.',
      );
    }
  }

  String _parseChecksum(String contents, String archiveName) {
    final line = contents.trim().split(RegExp(r'\r?\n')).first.trim();
    final match = RegExp(r'^([a-fA-F0-9]{64})(?:\s+\*?(.+))?$')
        .firstMatch(line);
    if (match == null) {
      throw const WrenUpgradeException(
        'the Wren SHA-256 file is malformed. '
        'The installed executable was not changed.',
      );
    }
    final filename = match.group(2)?.trim();
    if (filename != null && p.basename(filename) != archiveName) {
      throw const WrenUpgradeException(
        'the Wren SHA-256 file names a different archive. '
        'The installed executable was not changed.',
      );
    }
    return match.group(1)!.toLowerCase();
  }

  Future<void> _extractArchive(
    File archive,
    Directory destination,
    String expectedTopLevel,
  ) async {
    final listing = await _runProcess('tar', ['-tzf', archive.path]);
    if (listing.exitCode != 0) {
      throw WrenUpgradeException(
        'the Wren archive could not be listed: ${listing.stderr.trim()}. '
        'The installed executable was not changed.',
      );
    }
    final members = listing.stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    for (final member in members) {
      final normalized = member.replaceAll(r'\', '/');
      final parts = normalized.split('/');
      if (p.isAbsolute(normalized) ||
          parts.contains('..') ||
          (parts.first != expectedTopLevel)) {
        throw const WrenUpgradeException(
          'the Wren archive contains an unexpected file path. '
          'The installed executable was not changed.',
        );
      }
    }
    final extracted = await _runProcess('tar', [
      '-xzf',
      archive.path,
      '-C',
      destination.path,
    ]);
    if (extracted.exitCode != 0) {
      throw WrenUpgradeException(
        'the Wren archive could not be extracted: ${extracted.stderr.trim()}. '
        'The installed executable was not changed.',
      );
    }
  }

  Future<File> _savePreviousExecutable(
    File executable, {
    required String selectedCurrentVersion,
  }) async {
    final directory = Directory(p.absolute(dataDirectory));
    final backup = File(p.join(directory.path, 'wren.previous'));
    try {
      directory.createSync(recursive: true);
      final backupType = FileSystemEntity.typeSync(
        backup.path,
        followLinks: false,
      );
      if (backupType != FileSystemEntityType.notFound &&
          backupType != FileSystemEntityType.file) {
        throw const WrenUpgradeException(
          'the rollback path is not a regular file. Move it aside and retry.',
        );
      }
      if (p.equals(p.normalize(backup.path), p.normalize(executable.path))) {
        throw const WrenUpgradeException(
          'the executable path conflicts with Wren’s rollback path. '
          'Install Wren at a different path.',
        );
      }
      final temporary = File(
        p.join(
          directory.path,
          '.wren-previous-${io.pid}-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await executable.copy(temporary.path);
      _validateCandidate(temporary);
      await _verifyVersion(temporary.path, selectedCurrentVersion);
      await temporary.rename(backup.path);
      return backup;
    } on WrenUpgradeException {
      rethrow;
    } on Object catch (error) {
      throw WrenUpgradeException(
        'could not retain a rollback executable at ${backup.path}: $error. '
        'The installed executable was not changed; install Wren manually if '
        'the data directory cannot be made writable.',
      );
    }
  }

  File _validateExecutable(String path) {
    final absolute = p.absolute(path);
    if (p.basename(absolute) != 'wren') {
      throw WrenUpgradeException(
        'cannot upgrade Wren from $absolute because a direct installation must '
        'use the executable name wren. Install the new executable manually.',
      );
    }
    final type = FileSystemEntity.typeSync(absolute, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw WrenUpgradeException(
        'cannot upgrade a symlinked Wren executable at $absolute. '
        'Install the new executable manually at the real file path.',
      );
    }
    if (type != FileSystemEntityType.file) {
      throw WrenUpgradeException(
        'cannot upgrade Wren because $absolute is not a regular '
        'executable file. '
        'Install the new executable manually.',
      );
    }
    final stat = FileStat.statSync(absolute);
    if (stat.type != FileSystemEntityType.file ||
        stat.mode & 0x49 == 0 ||
        stat.mode & 0x92 == 0) {
      throw WrenUpgradeException(
        'cannot upgrade $absolute because it is not both executable '
        'and writable. '
        'Install the new executable manually; Wren will not request '
        'elevated access.',
      );
    }
    final parent = Directory(p.dirname(absolute));
    if (!parent.existsSync()) {
      throw WrenUpgradeException(
        'the Wren installation directory for $absolute is unavailable. '
        'Install the new executable manually.',
      );
    }
    return File(absolute);
  }

  void _validateCandidate(File file) {
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        FileStat.statSync(file.path).mode & 0x49 == 0) {
      throw const WrenUpgradeException(
        'the staged Wren executable is missing or is not executable. '
        'The installed executable was not changed.',
      );
    }
  }

  Future<void> _verifyVersion(String path, String expected) async {
    final result = await _runProcess(path, ['--version']);
    final reported = result.stdout.trim();
    if (result.exitCode != 0 || reported != 'wren $expected') {
      throw WrenUpgradeException(
        'the Wren executable at $path reported '
        '${reported.isEmpty ? 'no version' : reported} '
        'instead of wren $expected.',
      );
    }
  }

  Version _parseVersion(String value) {
    try {
      final version = Version.parse(value);
      if (version.isPreRelease) throw const FormatException('prerelease');
      return version;
    } on FormatException {
      throw WrenUpgradeException(
        'the running Wren version $value is not a stable SemVer version.',
      );
    }
  }

  Version? _tryParseStableVersion(String value) {
    try {
      final version = Version.parse(value);
      return version.isPreRelease ? null : version;
    } on FormatException {
      return null;
    }
  }

  Future<String> _digestFile(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<_CommandOutput> _runProcess(
    String executable,
    List<String> arguments,
  ) async {
    io.Process process;
    try {
      process = await io.Process.start(executable, arguments);
    } on Object catch (error) {
      throw WrenUpgradeException(
        'could not start $executable: $error. Install Wren manually if the '
        'required system tools are unavailable.',
      );
    }
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    try {
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          process.kill();
          throw const WrenUpgradeException(
            'a Wren upgrade process timed out. '
            'The installed executable was not changed.',
          );
        },
      );
      return _CommandOutput(exitCode, await stdoutFuture, await stderrFuture);
    } on WrenUpgradeException {
      rethrow;
    } on Object catch (error) {
      process.kill();
      throw WrenUpgradeException(
        'an upgrade process failed: $error. '
        'The installed executable was not changed.',
      );
    }
  }
}

class _PublishedWrenRelease {
  const new(this.version, this.assetUrls);

  final Version version;
  final Map<String, Uri> assetUrls;
}

class _VersionedResponse {
  const new(this.bytes, this.linkHeader);

  final Uint8List bytes;
  final String? linkHeader;
}

class _CommandOutput {
  const new(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}
