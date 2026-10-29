import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wren/wren.dart';

void main() {
  group('upgrade-wren', () {
    late Directory temporaryDirectory;
    late Directory executableDirectory;
    late Directory dataDirectory;
    late _FakeWrenReleaseServer releaseServer;
    late File executable;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'wren-upgrade-',
      );
      executableDirectory = Directory(p.join(temporaryDirectory.path, 'bin'))
        ..createSync();
      dataDirectory = Directory(p.join(temporaryDirectory.path, 'data'))
        ..createSync();
      executable = File(p.join(executableDirectory.path, 'wren'));
      releaseServer = _FakeWrenReleaseServer();
      await releaseServer.start();
    });

    tearDown(() async {
      await releaseServer.close();
      await temporaryDirectory.delete(recursive: true);
    });

    Future<(int, String, String)> runUpgrade({
      String currentVersion = '1.0.0',
    }) async {
      final output = StringBuffer();
      final errors = StringBuffer();
      final status = await runWren(
        ['upgrade-wren'],
        host: HostPlatform.linuxX64,
        installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
        runningExecutablePath: executable.path,
        upgradeReleaseApiUri: releaseServer.apiUri,
        wrenVersion: currentVersion,
        stdoutSink: output,
        stderrSink: errors,
      );
      return (status, output.toString(), errors.toString());
    }

    test(
      'selects the highest stable version and retains a working backup',
      () async {
        await _writeExecutable(executable, version: '1.0.0');
        await releaseServer.addRelease('1.8.0');
        await releaseServer.addRelease(
          '2.0.0',
          archive: await _makeArchive('2.0.0'),
        );
        await releaseServer.addRelease('9.0.0-beta.1', prerelease: true);

        final (status, output, errors) = await runUpgrade();

        expect(status, 0);
        expect(errors, isEmpty);
        expect(output, contains('Upgraded Wren from 1.0.0 to 2.0.0.'));
        expect(await _versionOf(executable), 'wren 2.0.0');
        expect(
          await _versionOf(File(p.join(dataDirectory.path, 'wren.previous'))),
          'wren 1.0.0',
        );
        expect(releaseServer.archiveRequests, 1);
      },
    );

    test(
      'equal, older, and prerelease tags do not trigger a downgrade',
      () async {
        await _writeExecutable(executable, version: '1.0.0');
        await releaseServer.addRelease('0.9.0');
        await releaseServer.addRelease('1.0.0');
        await releaseServer.addRelease('8.0.0-rc.1', prerelease: true);

        final (status, output, errors) = await runUpgrade();

        expect(status, 0);
        expect(errors, isEmpty);
        expect(output, contains('already at the latest stable release'));
        expect(await _versionOf(executable), 'wren 1.0.0');
        expect(releaseServer.archiveRequests, 0);
        expect(
          File(p.join(dataDirectory.path, 'wren.previous')).existsSync(),
          isFalse,
        );
      },
    );

    test('a bad checksum leaves the installed executable untouched', () async {
      await _writeExecutable(executable, version: '1.0.0');
      await releaseServer.addRelease(
        '2.0.0',
        archive: await _makeArchive('2.0.0'),
        badChecksum: true,
      );

      final (status, _, errors) = await runUpgrade();

      expect(status, 4);
      expect(errors, contains('does not match its SHA-256 checksum'));
      expect(await _versionOf(executable), 'wren 1.0.0');
      expect(
        File(p.join(dataDirectory.path, 'wren.previous')).existsSync(),
        isFalse,
      );
    });

    test('a truncated archive is treated as an interrupted download', () async {
      await _writeExecutable(executable, version: '1.0.0');
      await releaseServer.addRelease(
        '2.0.0',
        archive: await _makeArchive('2.0.0'),
        truncateArchive: true,
      );

      final (status, _, errors) = await runUpgrade();

      expect(status, 4);
      expect(errors, contains('does not match its SHA-256 checksum'));
      expect(await _versionOf(executable), 'wren 1.0.0');
      expect(
        File(p.join(dataDirectory.path, 'wren.previous')).existsSync(),
        isFalse,
      );
    });

    test('symlinked and non-writable executables are refused', () async {
      final realExecutable = File(
        p.join(executableDirectory.path, 'real-wren'),
      );
      await _writeExecutable(realExecutable, version: '1.0.0');
      await Link(executable.path).create(realExecutable.path);
      await releaseServer.addRelease(
        '2.0.0',
        archive: await _makeArchive('2.0.0'),
      );

      final (_, _, symlinkErrors) = await runUpgrade();

      expect(symlinkErrors, contains('symlinked Wren executable'));
      expect(symlinkErrors, contains('Install the new executable manually'));
      expect(releaseServer.releaseRequests, 0);

      await Link(executable.path).delete();
      await _writeExecutable(executable, version: '1.0.0');
      await Process.run('chmod', ['555', executable.path]);

      final (status, _, readOnlyErrors) = await runUpgrade();

      expect(status, 4);
      expect(readOnlyErrors, contains('not both executable and writable'));
      expect(readOnlyErrors, contains('will not request elevated access'));
      expect(await _versionOf(executable), 'wren 1.0.0');
      expect(releaseServer.archiveRequests, 0);
    });

    test(
      'an incomplete archive fails before replacing the executable',
      () async {
        await _writeExecutable(executable, version: '1.0.0');
        await releaseServer.addRelease(
          '2.0.0',
          archive: await _makeArchive('2.0.0', includeExecutable: false),
        );

        final (status, _, errors) = await runUpgrade();

        expect(status, 4);
        expect(errors, contains('staged Wren executable is missing'));
        expect(await _versionOf(executable), 'wren 1.0.0');
        expect(
          File(p.join(dataDirectory.path, 'wren.previous')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'post-swap validation failure rolls back to the previous binary',
      () async {
        await _writeExecutable(executable, version: '1.0.0');
        await releaseServer.addRelease(
          '2.0.0',
          archive: await _makeArchive(
            '2.0.0',
            finalVersion: 'broken',
            finalExitCode: 9,
          ),
        );

        final (status, _, errors) = await runUpgrade();

        expect(status, 4);
        expect(errors, contains('was rolled back'));
        expect(await _versionOf(executable), 'wren 1.0.0');
        expect(
          await _versionOf(File(p.join(dataDirectory.path, 'wren.previous'))),
          'wren 1.0.0',
        );
      },
    );

    test('version flag reports the compiled package version', () async {
      final output = StringBuffer();

      final status = await runWren(
        ['--version'],
        wrenVersion: '2.3.4',
        stdoutSink: output,
        stderrSink: StringBuffer(),
      );

      expect(status, 0);
      expect(output.toString(), 'wren 2.3.4\n');
    });
  });
}

Future<void> _writeExecutable(File file, {required String version}) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '#!/bin/sh\n'
    'if [ "\$1" = "--version" ]; then\n'
    '  echo "wren $version"\n'
    '  exit 0\n'
    'fi\n'
    'exit 0\n',
  );
  final chmod = await Process.run('chmod', ['755', file.path]);
  if (chmod.exitCode != 0) {
    throw StateError('chmod failed: ${chmod.stderr}');
  }
}

Future<Uint8List> _makeArchive(
  String version, {
  bool includeExecutable = true,
  String? finalVersion,
  int finalExitCode = 0,
}) async {
  final root = await Directory.systemTemp.createTemp('wren-archive-');
  try {
    final packageName = 'wren-$version-linux-x64';
    final package = Directory(p.join(root.path, packageName))..createSync();
    if (includeExecutable) {
      final stagedOutput = 'wren $version';
      final installedOutput = 'wren ${finalVersion ?? version}';
      final script = finalVersion == null
          ? '#!/bin/sh\n'
                'if [ "\$1" = "--version" ]; then\n'
                '  echo "$stagedOutput"\n'
                '  exit 0\n'
                'fi\n'
                'exit 0\n'
          : '#!/bin/sh\n'
                'if [ "\$1" = "--version" ]; then\n'
                '  case "\$0" in\n'
                '    */.wren-upgrade-*/extracted/*/wren)\n'
                '      echo "$stagedOutput"\n'
                '      exit 0\n'
                '      ;;\n'
                '    *)\n'
                '      echo "$installedOutput"\n'
                '      exit $finalExitCode\n'
                '      ;;\n'
                '  esac\n'
                'fi\n'
                'exit 0\n';
      final executable = File(p.join(package.path, 'wren'));
      await executable.writeAsString(script);
      final chmod = await Process.run('chmod', ['755', executable.path]);
      if (chmod.exitCode != 0) {
        throw StateError('chmod failed: ${chmod.stderr}');
      }
    }
    final archive = File(p.join(root.path, 'archive.tar.gz'));
    final tar = await Process.run('tar', [
      '-czf',
      archive.path,
      '-C',
      root.path,
      packageName,
    ]);
    if (tar.exitCode != 0) throw StateError('tar failed: ${tar.stderr}');
    return await archive.readAsBytes();
  } finally {
    await root.delete(recursive: true);
  }
}

Future<String> _versionOf(File file) async {
  final result = await Process.run(file.path, ['--version']);
  if (result.exitCode != 0) {
    throw StateError('version check failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

class _FakeWrenReleaseServer {
  final _releases = <Map<String, Object?>>[];
  final _archives = <String, Uint8List>{};
  final _badChecksums = <String>{};
  final _truncatedArchives = <String>{};
  HttpServer? _server;
  int releaseRequests = 0;
  int archiveRequests = 0;

  Uri get apiUri => Uri.parse(
    'http://127.0.0.1:${_server!.port}/repos/Luckey-Elijah/wren/releases',
  );

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> addRelease(
    String version, {
    Uint8List? archive,
    bool prerelease = false,
    bool badChecksum = false,
    bool truncateArchive = false,
  }) async {
    final archiveName = 'wren-$version-linux-x64.tar.gz';
    final assets = <Map<String, Object?>>[];
    if (archive != null) {
      _archives[version] = archive;
      if (badChecksum) _badChecksums.add(version);
      if (truncateArchive) _truncatedArchives.add(version);
      assets.addAll([
        {
          'name': archiveName,
          'browser_download_url': _assetUri(version, 'archive').toString(),
        },
        {
          'name': '$archiveName.sha256',
          'browser_download_url': _assetUri(version, 'checksum').toString(),
        },
      ]);
    }
    _releases.add({
      'tag_name': 'wren-v$version',
      'draft': false,
      'prerelease': prerelease,
      'assets': assets,
    });
  }

  Uri _assetUri(String version, String kind) =>
      Uri.parse('http://127.0.0.1:${_server!.port}/assets/$version/$kind');

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path.endsWith('/releases')) {
      releaseRequests++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(_releases));
      await request.response.close();
      return;
    }
    final parts = request.uri.pathSegments;
    if (parts.length == 3 && parts[0] == 'assets') {
      final version = parts[1];
      if (parts[2] == 'archive') {
        archiveRequests++;
        final bytes = _archives[version];
        if (bytes == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else if (_truncatedArchives.contains(version)) {
          request.response.add(bytes.sublist(0, bytes.length ~/ 2));
        } else {
          request.response.add(bytes);
        }
        await request.response.close();
        return;
      }
      if (parts[2] == 'checksum') {
        final bytes = _archives[version];
        if (bytes == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          final archiveName = 'wren-$version-linux-x64.tar.gz';
          final digest = _badChecksums.contains(version)
              ? '0' * 64
              : sha256.convert(bytes).toString();
          request.response.write('$digest  $archiveName\n');
        }
        await request.response.close();
        return;
      }
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  Future<void> close() async {
    await _server?.close(force: true);
  }
}
