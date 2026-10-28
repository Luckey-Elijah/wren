import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io' as io;

import 'package:pub_semver/pub_semver.dart';

const _minimumDartVersion = '2.19.0';
const _linuxCatalog =
    'https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json';
const _macosCatalog =
    'https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json';

/// Runs the Wren CLI and returns its process exit status.
///
/// [catalogJson] and [host] make the command boundary usable with local catalog
/// fixtures. Production callers should omit both values.
Future<int> runWren(
  List<String> arguments, {
  StringSink? stdoutSink,
  StringSink? stderrSink,
  String? catalogJson,
  HostPlatform? host,
}) async {
  final out = stdoutSink ?? io.stdout;
  final err = stderrSink ?? io.stderr;
  final parsed = _parseArguments(arguments);
  if (parsed.error != null) {
    err.writeln('wren: ${parsed.error}');
    err.writeln(_usage);
    return 2;
  }

  if (parsed.help) {
    out.writeln(_usage);
    return 0;
  }

  if (parsed.command != 'releases') {
    err.writeln('wren: unknown command "${parsed.command}".');
    err.writeln(_usage);
    return 2;
  }

  final targetHost = host ?? HostPlatform.current;
  if (targetHost == null) {
    err.writeln(
      'wren: this host is unsupported. Wren supports Linux x86_64 and macOS arm64.',
    );
    return 4;
  }

  try {
    final catalog = catalogJson == null
        ? await ReleaseCatalog.fetch(targetHost.catalogUri, host: targetHost)
        : ReleaseCatalog.parse(catalogJson, host: targetHost);
    if (parsed.releaseVersion case final version?) {
      final eligibility = catalog.eligibilityForVersion(version);
      if (eligibility.release case final release?) {
        out.writeln(
          'Flutter $version is eligible for ${targetHost.label}: '
          '${release.channel}, bundled Dart ${release.dartVersion}.',
        );
        return 0;
      }
      err.writeln(
        'wren: Flutter $version is not eligible for ${targetHost.label}: '
        '${eligibility.reason}',
      );
      return 4;
    }
    if (catalog.releases.isEmpty) {
      out.writeln('No eligible Flutter releases for ${targetHost.label}.');
      return 0;
    }
    out.writeln('Eligible Flutter releases for ${targetHost.label}:');
    for (final release in catalog.releases) {
      out.writeln(
        '${release.version}  ${release.channel}  Dart ${release.dartVersion}',
      );
    }
    return 0;
  } on ReleaseCatalogException catch (error) {
    err.writeln('wren: ${error.message}');
    return 4;
  }
}

const _usage =
    'Usage: wren [--verbose] releases [<release>]\n'
    'Commands:\n'
    '  releases   List eligible stable and beta Flutter releases\n'
    '             Check one release with: wren releases <release>';

class _ParsedArguments {
  const _ParsedArguments({
    this.command = '',
    this.releaseVersion,
    this.verbose = false,
    this.help = false,
    this.error,
  });

  final String command;
  final String? releaseVersion;
  final bool verbose;
  final bool help;
  final String? error;
}

_ParsedArguments _parseArguments(List<String> arguments) {
  var verbose = false;
  final remaining = <String>[];
  for (final argument in arguments) {
    if (argument == '--verbose') {
      verbose = true;
    } else {
      remaining.add(argument);
    }
  }

  if (remaining.isEmpty) {
    return _ParsedArguments(error: 'a command is required.');
  }
  if (remaining.length == 1 &&
      (remaining.single == '--help' || remaining.single == '-h')) {
    return _ParsedArguments(verbose: verbose, help: true);
  }
  if (remaining.any((argument) => argument.startsWith('-'))) {
    return _ParsedArguments(
      error:
          'unknown option "${remaining.firstWhere((a) => a.startsWith('-'))}".',
    );
  }
  if (remaining.length > 2) {
    return _ParsedArguments(error: 'unexpected argument "${remaining[2]}".');
  }
  return _ParsedArguments(
    command: remaining.first,
    releaseVersion: remaining.length == 2 ? remaining[1] : null,
    verbose: verbose,
  );
}

enum HostPlatform {
  linuxX64(
    label: 'Linux x86_64',
    catalogUrl: _linuxCatalog,
    catalogOs: 'linux',
    catalogArchitecture: 'x64',
  ),
  macosArm64(
    label: 'macOS arm64',
    catalogUrl: _macosCatalog,
    catalogOs: 'macos',
    catalogArchitecture: 'arm64',
  );

  const HostPlatform({
    required this.label,
    required this.catalogUrl,
    required this.catalogOs,
    required this.catalogArchitecture,
  });

  final String label;
  final String catalogUrl;
  final String catalogOs;
  final String catalogArchitecture;

  static HostPlatform? get current {
    final abi = Abi.current();
    if (io.Platform.isLinux && abi == Abi.linuxX64) return linuxX64;
    if (io.Platform.isMacOS && abi == Abi.macosArm64) return macosArm64;
    return null;
  }

  Uri get catalogUri => Uri.parse(catalogUrl);
}

class FlutterRelease {
  const FlutterRelease({
    required this.version,
    required this.channel,
    required this.frameworkRevision,
    required this.dartVersion,
    required this.dartSemVersion,
    required this.archive,
    required this.archiveSha256,
  });

  final String version;
  final String channel;
  final String frameworkRevision;
  final String dartVersion;
  final Version dartSemVersion;
  final String archive;
  final String archiveSha256;
}

class ReleaseCatalog {
  const ReleaseCatalog(this.releases, [this._eligibilityByVersion = const {}]);

  final List<FlutterRelease> releases;
  final Map<String, ReleaseEligibility> _eligibilityByVersion;

  /// Resolves an explicitly requested Flutter version, including a reason if
  /// the catalog knows the release but Wren cannot install it on this host.
  ReleaseEligibility eligibilityForVersion(String version) =>
      _eligibilityByVersion[version] ??
      ReleaseEligibility.ineligible(
        'Flutter release $version is not present in the host catalog.',
      );

  static Future<ReleaseCatalog> fetch(
    Uri uri, {
    required HostPlatform host,
    io.HttpClient? client,
  }) async {
    final http = client ?? io.HttpClient();
    final ownsClient = client == null;
    try {
      final request = await http
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != io.HttpStatus.ok) {
        throw ReleaseCatalogException(
          'could not read the Flutter release catalog (HTTP ${response.statusCode}).',
        );
      }
      final body = await utf8.decoder.bind(response).join();
      return parse(body, host: host);
    } on ReleaseCatalogException {
      rethrow;
    } on Object catch (error) {
      throw ReleaseCatalogException(
        'could not read the Flutter release catalog: $error',
      );
    } finally {
      if (ownsClient) http.close();
    }
  }

  static ReleaseCatalog parse(String json, {required HostPlatform host}) {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      throw ReleaseCatalogException(
        'Flutter release catalog is not valid JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, Object?> || decoded['releases'] is! List) {
      throw const ReleaseCatalogException(
        'Flutter release catalog has an invalid structure.',
      );
    }

    final eligible = <FlutterRelease>[];
    final eligibilityByVersion = <String, ReleaseEligibility>{};
    for (final item in decoded['releases']! as List<Object?>) {
      if (item is! Map<String, Object?>) continue;
      final result = _eligibility(item, host);
      final version = item['version'];
      if (version is String) eligibilityByVersion[version] = result;
      if (result.release != null) eligible.add(result.release!);
    }
    eligible.sort((a, b) {
      final channelOrder = _channelOrder(a.channel)
          .compareTo(_channelOrder(b.channel));
      if (channelOrder != 0) return channelOrder;
      return Version.parse(b.version).compareTo(Version.parse(a.version));
    });
    return ReleaseCatalog(
      List.unmodifiable(eligible),
      Map.unmodifiable(eligibilityByVersion),
    );
  }

  static ReleaseEligibility eligibilityFor(
    Map<String, Object?> entry, {
    required HostPlatform host,
  }) => _eligibility(entry, host);
}

class ReleaseEligibility {
  const ReleaseEligibility.eligible(this.release) : reason = null;
  const ReleaseEligibility.ineligible(this.reason) : release = null;

  final FlutterRelease? release;
  final String? reason;
  bool get isEligible => release != null;
}

ReleaseEligibility _eligibility(Map<String, Object?> entry, HostPlatform host) {
  final channel = entry['channel'];
  final version = entry['version'];
  if (channel != 'stable' && channel != 'beta') {
    return const ReleaseEligibility.ineligible(
      'channel is not supported (stable or beta).',
    );
  }
  final channelName = channel as String;
  if (version is! String || !_isSemVersion(version)) {
    return const ReleaseEligibility.ineligible(
      'Flutter version is missing or invalid.',
    );
  }

  final archive = entry['archive'];
  if (archive is! String || !_hasNativeArchive(archive, host)) {
    return ReleaseEligibility.ineligible(
      'no native ${host.label} artifact is available.',
    );
  }
  if (entry['dart_sdk_arch'] != host.catalogArchitecture) {
    return ReleaseEligibility.ineligible(
      'bundled Dart artifact is not native ${host.catalogArchitecture}.',
    );
  }

  final rawDartVersion = entry['dart_sdk_version'];
  final dartVersion = rawDartVersion is String
      ? _canonicalDartVersion(rawDartVersion)
      : null;
  if (dartVersion == null) {
    return const ReleaseEligibility.ineligible(
      'bundled Dart version is missing or unknown.',
    );
  }
  final dartSemVersion = Version.parse(dartVersion);
  if (dartSemVersion < Version.parse(_minimumDartVersion)) {
    return ReleaseEligibility.ineligible(
      'bundled Dart $dartVersion is below the minimum $_minimumDartVersion.',
    );
  }

  final frameworkRevision = entry['hash'];
  final sha256 = entry['sha256'];
  if (frameworkRevision is! String || frameworkRevision.isEmpty) {
    return const ReleaseEligibility.ineligible(
      'framework revision is missing.',
    );
  }
  if (sha256 is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
    return const ReleaseEligibility.ineligible(
      'archive SHA-256 is missing or invalid.',
    );
  }

  return ReleaseEligibility.eligible(
    FlutterRelease(
      version: version,
      channel: channelName,
      frameworkRevision: frameworkRevision,
      dartVersion: dartVersion,
      dartSemVersion: dartSemVersion,
      archive: archive,
      archiveSha256: sha256,
    ),
  );
}

String? _canonicalDartVersion(String value) {
  final build = RegExp(r'\(\s*build\s+([^\s)]+)\s*\)').firstMatch(value);
  final candidate = build?.group(1) ?? value.trim();
  return _isSemVersion(candidate) ? candidate : null;
}

bool _isSemVersion(String value) {
  try {
    Version.parse(value);
    return true;
  } on FormatException {
    return false;
  }
}

bool _hasNativeArchive(String archive, HostPlatform host) {
  final normalized = archive.toLowerCase().replaceAll('\\', '/');
  final segments = normalized.split('/');
  if (host == HostPlatform.linuxX64) {
    return segments.contains('linux') &&
        normalized.contains('flutter_linux_') &&
        !normalized.contains('arm64');
  }
  return segments.contains('macos') &&
      normalized.contains('flutter_macos_') &&
      normalized.contains('arm64');
}

int _channelOrder(String channel) => channel == 'stable' ? 0 : 1;

class ReleaseCatalogException implements Exception {
  const ReleaseCatalogException(this.message);

  final String message;
}
