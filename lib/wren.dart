import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:pub_semver/pub_semver.dart';

import 'src/installer.dart';

export 'src/installer.dart'
    show InstallEnvironment, InstallException, InstallResult;

const _minimumDartVersion = '2.19.0';
const _linuxCatalog =
    'https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json';
const _macosCatalog =
    'https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json';

/// Shared values and services for one invocation of the Wren CLI.
///
/// A fresh context is constructed for each [runWren] call and then shared by
/// every command registered for that run.
class WrenContext {
  WrenContext({
    StringSink? stdoutSink,
    StringSink? stderrSink,
    this.catalogJson,
    this.hostOverride,
    this.configuredInstallEnvironment,
  }) : _stdoutSink = stdoutSink ?? io.stdout,
       _stderrSink = stderrSink ?? io.stderr;

  final StringSink _stdoutSink;
  final StringSink _stderrSink;
  final String? catalogJson;
  final HostPlatform? hostOverride;
  final InstallEnvironment? configuredInstallEnvironment;

  String get minimumDartVersion => _minimumDartVersion;
  StringSink get stdoutSink => _stdoutSink;
  StringSink get stderrSink => _stderrSink;
  HostPlatform? get host => hostOverride ?? HostPlatform.current;
  InstallEnvironment get installEnvironment =>
      configuredInstallEnvironment ?? InstallEnvironment();

  FlutterInstaller get installer => FlutterInstaller(
    installEnvironment,
    onProgress: (message) => stderrSink.writeln(message),
  );

  Future<ReleaseCatalog> loadReleaseCatalog(HostPlatform targetHost) =>
      catalogJson == null
      ? ReleaseCatalog.fetch(targetHost.catalogUri, host: targetHost)
      : Future.value(ReleaseCatalog.parse(catalogJson!, host: targetHost));
}

/// Wren-specific command base with shared output, verbosity and context.
abstract class WrenCommand extends Command<int> {
  WrenCommand(this.context) {
    argParser.addFlag(
      'verbose',
      negatable: false,
      help: 'Show additional Wren diagnostic output.',
    );
  }

  final WrenContext context;

  bool get verbose =>
      (globalResults?.flag('verbose') ?? false) ||
      (argResults?.flag('verbose') ?? false);

  void writeOut(Object? message) => context.stdoutSink.writeln(message);
  void writeError(Object? message) => context.stderrSink.writeln(message);

  Never failUsage(String message) => usageException(message);
}

/// Composition wrapper which only accepts Wren-owned commands.
class WrenCommandRunner {
  WrenCommandRunner(this.context)
    : _runner = _WrenPackageCommandRunner(context);

  final WrenContext context;
  final _WrenPackageCommandRunner _runner;

  void addCommand(WrenCommand command) => _runner.addCommand(command);

  Future<int> run(Iterable<String> arguments) async {
    final args = arguments.toList(growable: false);
    try {
      if (args.isEmpty || args.every((argument) => argument == '--verbose')) {
        context.stderrSink
          ..writeln('wren: a command is required.')
          ..writeln(_runner.usage);
        return 2;
      }
      return await _runner.run(args) ?? 0;
    } on UsageException catch (error) {
      context.stderrSink
        ..writeln('wren: ${error.message}')
        ..writeln(error.usage);
      return 2;
    } on ReleaseCatalogException catch (error) {
      context.stderrSink.writeln('wren: ${error.message}');
      return 4;
    } on InstallException catch (error) {
      context.stderrSink.writeln('wren: ${error.message}');
      return 4;
    } on Object catch (error) {
      context.stderrSink.writeln('wren: command failed: $error');
      return 4;
    }
  }
}

class _WrenPackageCommandRunner extends CommandRunner<int> {
  _WrenPackageCommandRunner(this.context)
    : super('wren', 'A standalone Flutter and Dart version manager.') {
    argParser.addFlag(
      'verbose',
      negatable: false,
      help: 'Show additional Wren diagnostic output.',
    );
  }

  final WrenContext context;

  @override
  void printUsage() => context.stdoutSink.write(usage);
}

/// Runs Wren's command tree and returns its process exit status.
///
/// [catalogJson], [host], and [installEnvironment] make the CLI invocation
/// seam usable with local fixtures. Production callers should omit them.
Future<int> runWren(
  List<String> arguments, {
  StringSink? stdoutSink,
  StringSink? stderrSink,
  String? catalogJson,
  HostPlatform? host,
  InstallEnvironment? installEnvironment,
}) async {
  final context = WrenContext(
    stdoutSink: stdoutSink,
    stderrSink: stderrSink,
    catalogJson: catalogJson,
    hostOverride: host,
    configuredInstallEnvironment: installEnvironment,
  );
  final runner = WrenCommandRunner(context)
    ..addCommand(_ReleasesCommand(context))
    ..addCommand(_InstallCommand(context))
    ..addCommand(_ListCommand(context));
  return runner.run(arguments);
}

class _ReleasesCommand extends WrenCommand {
  _ReleasesCommand(super.context);

  @override
  String get name => 'releases';

  @override
  String get description =>
      'List eligible stable and beta Flutter releases.\n'
      'Optionally check one release version.';

  @override
  Future<int> run() async {
    if (argResults!.rest.length > 1) {
      failUsage('unexpected argument "${argResults!.rest[1]}".');
    }
    final targetHost = context.host;
    if (targetHost == null) {
      writeError(
        'wren: this host is unsupported. Wren supports Linux x86_64 and macOS arm64.',
      );
      return 4;
    }
    final catalog = await context.loadReleaseCatalog(targetHost);
    final version = argResults!.rest.isEmpty ? null : argResults!.rest.single;
    if (version != null) {
      final eligibility = catalog.eligibilityForVersion(version);
      if (eligibility.release case final release?) {
        writeOut(
          'Flutter $version is eligible for ${targetHost.label}: '
          '${release.channel}, bundled Dart ${release.dartVersion}.',
        );
        return 0;
      }
      writeError(
        'wren: Flutter $version is not eligible for ${targetHost.label}: '
        '${eligibility.reason}',
      );
      return 4;
    }
    if (catalog.releases.isEmpty) {
      writeOut('No eligible Flutter releases for ${targetHost.label}.');
      return 0;
    }
    writeOut('Eligible Flutter releases for ${targetHost.label}:');
    for (final release in catalog.releases) {
      writeOut(
        '${release.version}  ${release.channel}  Dart ${release.dartVersion}',
      );
    }
    return 0;
  }
}

class _InstallCommand extends WrenCommand {
  _InstallCommand(super.context);

  @override
  String get name => 'install';

  @override
  String get description => 'Install an eligible stable Flutter release.';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      failUsage(
        argResults!.rest.isEmpty
            ? '`install` requires a Flutter release version.'
            : 'unexpected argument "${argResults!.rest[1]}".',
      );
    }
    final targetHost = context.host;
    if (targetHost == null) {
      writeError(
        'wren: this host is unsupported. Wren supports Linux x86_64 and macOS arm64.',
      );
      return 4;
    }
    final catalog = await context.loadReleaseCatalog(targetHost);
    final version = argResults!.rest.single;
    final eligibility = catalog.eligibilityForVersion(version);
    final release = eligibility.release;
    if (release == null) {
      writeError(
        'wren: Flutter $version cannot be installed: ${eligibility.reason}',
      );
      return 4;
    }
    final result = await context.installer.install(release, host: targetHost);
    writeOut(result.message);
    return 0;
  }
}

class _ListCommand extends WrenCommand {
  _ListCommand(super.context);

  @override
  String get name => 'list';

  @override
  List<String> get aliases => const ['ls'];

  @override
  String get description => 'List installed Flutter releases and readiness.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      failUsage('unexpected argument "${argResults!.rest.first}".');
    }
    final releases = await context.installer.listInstalled();
    if (releases.isEmpty) {
      writeOut('No Flutter releases are installed.');
      return 0;
    }
    writeOut('Installed Flutter releases:');
    for (final release in releases) {
      final readiness = release.needsRepair ? 'needs repair' : 'ready';
      final reason = release.repairReason == null
          ? ''
          : ' — ${release.repairReason}';
      writeOut(
        '${release.version}  ${release.channel}  ${release.host}  $readiness$reason',
      );
    }
    return 0;
  }
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
