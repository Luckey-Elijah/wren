import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'package:wren/wren.dart' show FlutterRelease, HostPlatform;

const _flutterGitUrl = 'https://github.com/flutter/flutter.git';
const _engineRevisionPattern = r'^[a-fA-F0-9]{40}$';
const _dartExecutable = 'bin/cache/dart-sdk/bin/dart';
const _commonRequiredDirectories = <String>[
  'bin/cache/artifacts/engine/common/flutter_patched_sdk',
  'bin/cache/artifacts/engine/common/flutter_patched_sdk_product',
  'bin/cache/flutter_web_sdk',
  'bin/cache/pkg/sky_engine',
  'bin/cache/pkg/flutter_gpu',
];
const _commonSourceStampFiles = <String>[
  'engine-dart-sdk.stamp',
  'engine.stamp',
  'flutter_sdk.stamp',
  'flutter_web_sdk.stamp',
  'engine.realm',
];
const _dartRequiredFiles = <String>[_dartExecutable];
const _linuxRequiredFiles = <String>[
  'bin/cache/artifacts/engine/linux-x64/gen_snapshot',
  'bin/cache/artifacts/engine/linux-x64/flutter_tester',
  'bin/cache/artifacts/engine/linux-x64/libflutter_linux_gtk.so',
  'bin/cache/artifacts/engine/linux-x64-profile/flutter_linux/libflutter_linux_gtk.so',
  'bin/cache/artifacts/engine/linux-x64-release/flutter_linux/libflutter_linux_gtk.so',
];

List<String> _requiredDirectories(HostPlatform host) => [
  ..._commonRequiredDirectories,
  if (host == HostPlatform.linuxX64)
    'bin/cache/artifacts/engine/linux-x64-profile/flutter_linux',
  if (host == HostPlatform.linuxX64)
    'bin/cache/artifacts/engine/linux-x64-release/flutter_linux',
  if (host == HostPlatform.macosArm64)
    'bin/cache/artifacts/engine/darwin-arm64/FlutterMacOS.xcframework',
  if (host == HostPlatform.macosArm64)
    'bin/cache/artifacts/engine/darwin-arm64-profile/FlutterMacOS.xcframework',
  if (host == HostPlatform.macosArm64)
    'bin/cache/artifacts/engine/darwin-arm64-release/FlutterMacOS.xcframework',
];

List<String> _requiredFiles(HostPlatform host) => [
  ..._dartRequiredFiles,
  if (host == HostPlatform.linuxX64) ..._linuxRequiredFiles,
  if (host == HostPlatform.macosArm64) ...[
    'bin/cache/artifacts/engine/darwin-arm64/gen_snapshot',
    'bin/cache/artifacts/engine/darwin-arm64/FlutterMacOS.xcframework/Info.plist',
    'bin/cache/artifacts/engine/darwin-arm64-profile/FlutterMacOS.xcframework/Info.plist',
    'bin/cache/artifacts/engine/darwin-arm64-release/FlutterMacOS.xcframework/Info.plist',
  ],
];

List<String> _sourceStampFiles(HostPlatform host) => [
  ..._commonSourceStampFiles,
  if (host == HostPlatform.linuxX64) 'linux-sdk.stamp' else 'macos-sdk.stamp',
];

List<String> _sourceArtifactPaths(HostPlatform host) => [
  'bin/cache/dart-sdk',
  'bin/cache/artifacts/engine/common',
  if (host == HostPlatform.linuxX64) ...[
    'bin/cache/artifacts/engine/linux-x64',
    'bin/cache/artifacts/engine/linux-x64-profile',
    'bin/cache/artifacts/engine/linux-x64-release',
  ],
  if (host == HostPlatform.macosArm64) ...[
    'bin/cache/artifacts/engine/darwin-arm64',
    'bin/cache/artifacts/engine/darwin-arm64-profile',
    'bin/cache/artifacts/engine/darwin-arm64-release',
  ],
  'bin/cache/flutter_web_sdk',
  'bin/cache/pkg/sky_engine',
  'bin/cache/pkg/flutter_gpu',
];

String _archiveVariant(HostPlatform host) =>
    host == HostPlatform.linuxX64 ? 'linux-x64' : 'darwin-arm64';

List<String> _precacheArguments(HostPlatform host) => [
  'precache',
  if (host == HostPlatform.linuxX64) '--linux' else '--macos',
  '--web',
];

/// Local storage and source locations for one Wren installation.
///
/// The optional values are also useful for exercising installs against a
/// temporary Git repository without contacting GitHub.
/// Provides the data directory and Flutter source repository for Wren.
class InstallEnvironment {
  /// Creates an environment with optional directory and repository overrides.
  new({Directory? dataDirectory, Uri? flutterRepository})
    : dataDirectory = dataDirectory ?? _defaultDataDirectory(),
      flutterRepository = flutterRepository ?? Uri.parse(_flutterGitUrl);

  /// Root directory for Wren-managed data.
  final Directory dataDirectory;

  /// Git repository used to create Flutter release checkouts.
  final Uri flutterRepository;
}

/// Describes the result of a Flutter release installation.
class InstallResult {
  /// Creates an installation result.
  const new({required this.message, required this.alreadyInstalled});

  /// User-facing result message.
  final String message;

  /// Whether Wren reused an installation that was already ready.
  final bool alreadyInstalled;
}

/// Describes an installed Flutter release and its readiness.
class InstalledRelease {
  /// Creates a summary of an installed release.
  const new({
    required this.channel,
    required this.version,
    required this.host,
    required this.needsRepair,
    this.dartVersion,
    this.repairReason,
  });

  /// Release channel, such as `stable` or `beta`.
  final String channel;

  /// Flutter version.
  final String version;

  /// Host operating system associated with this installation.
  final String host;

  /// Canonical bundled Dart version recorded at installation time.
  final String? dartVersion;

  /// Whether a required file or identity check failed.
  final bool needsRepair;

  /// Reason the release needs repair, when known.
  final String? repairReason;
}

/// An operation that Wren could not complete.
class InstallException implements Exception {
  /// Creates an installation exception with an actionable message.
  const new(this.message);

  /// Explanation of the failed operation.
  final String message;
}

/// An SDK launch failure with its Wren process exit status.
class SdkLaunchException implements Exception {
  /// Creates a launch failure.
  const new({required this.status, required this.message});

  /// Wren process exit status to return.
  final int status;

  /// Actionable explanation for the user.
  final String message;
}

/// Installs and inspects Wren-managed Flutter releases.
class FlutterInstaller {
  /// Creates an installer backed by [environment].
  new(this.environment, {this.onProgress});

  /// Storage and repository configuration used by this installer.
  final InstallEnvironment environment;

  /// Optional callback for progress messages.
  final void Function(String message)? onProgress;

  /// Lists published releases and performs the inexpensive launch-readiness
  /// checks used by Wren before selecting an SDK.
  /// Lists published releases and checks their launch readiness.
  Future<List<InstalledRelease>> listInstalled() async {
    final releasesDirectory = Directory(
      p.join(environment.dataDirectory.absolute.path, 'releases'),
    );
    if (!releasesDirectory.existsSync()) return const [];

    final installed = <InstalledRelease>[];
    await for (final entity in releasesDirectory.list(followLinks: false)) {
      if (entity is! Directory ||
          FileSystemEntity.typeSync(entity.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        continue;
      }
      final marker = File(p.join(entity.path, '.wren-release.json'));
      if (!marker.existsSync()) continue;
      final result = await _readiness(entity, releasesDirectory.parent);
      if (result == null) continue;
      installed.add(result);
    }
    installed.sort((left, right) {
      final channelOrder = _readinessChannelOrder(left.channel)
          .compareTo(_readinessChannelOrder(right.channel));
      if (channelOrder != 0) return channelOrder;
      try {
        return Version.parse(right.version)
            .compareTo(Version.parse(left.version));
      } on FormatException {
        return right.version.compareTo(left.version);
      }
    });
    return List.unmodifiable(installed);
  }

  /// Runs [executable] from the exact installed [releaseVersion].
  ///
  /// The per-release use lease remains present until the child exits.
  Future<int> launch(
    String releaseVersion, {
    required HostPlatform host,
    required String executable,
    required List<String> arguments,
    required StringSink stdoutSink,
    required StringSink stderrSink,
    required IOSink? stdoutByteSink,
    required IOSink? stderrByteSink,
    required Stream<List<int>> stdinStream,
  }) async {
    if (executable != 'flutter' && executable != 'dart') {
      throw ArgumentError.value(executable, 'executable');
    }
    final root = environment.dataDirectory.absolute.path;
    final releasesDirectory = Directory(p.join(root, 'releases'));
    Directory? candidate;
    if (releasesDirectory.existsSync()) {
      await for (final entity in releasesDirectory.list(followLinks: false)) {
        if (entity is! Directory ||
            FileSystemEntity.typeSync(entity.path, followLinks: false) !=
                FileSystemEntityType.directory) {
          continue;
        }
        final marker = File(p.join(entity.path, '.wren-release.json'));
        if (!marker.existsSync()) continue;
        try {
          final data = jsonDecode(await marker.readAsString());
          if (data is Map<String, Object?> &&
              data['version'] == releaseVersion &&
              data['host'] == host.catalogOs &&
              data['architecture'] == host.catalogArchitecture) {
            candidate = entity;
            break;
          }
        } on Object {
          // Invalid records are diagnosed by the common readiness check below.
        }
      }
    }
    if (candidate == null) {
      throw SdkLaunchException(
        status: 3,
        message:
            'Flutter $releaseVersion is not installed for ${host.label}; '
            'run `wren install $releaseVersion`.',
      );
    }
    final releaseKey = p.basename(candidate.path);
    // Lifecycle mutations use this lock while checking for active leases.
    final lifecycleLock = await _acquireLock(
      Directory(p.join(root, 'locks', 'lifecycle-$releaseKey')),
    );
    var lifecycleLockHeld = true;
    var leaseCreated = false;
    final leaseDirectory = Directory(p.join(root, 'leases', releaseKey));
    final lease = File(p.join(leaseDirectory.path, '$pid-${_randomId()}'));
    try {
      await leaseDirectory.create(recursive: true);
      await lease.create(exclusive: true);
      leaseCreated = true;
      await lease.writeAsString('$pid\n');
      final installed = await listInstalled();
      InstalledRelease? selected;
      for (final release in installed) {
        if (release.version == releaseVersion &&
            release.host == host.catalogOs) {
          selected = release;
          break;
        }
      }
      if (selected == null) {
        throw SdkLaunchException(
          status: 3,
          message:
              'Flutter $releaseVersion is not installed for ${host.label}; '
              'run `wren install $releaseVersion`.',
        );
      }
      if (selected.needsRepair) {
        throw SdkLaunchException(
          status: 3,
          message:
              'Flutter $releaseVersion needs repair; run '
              '`wren repair $releaseVersion`.',
        );
      }
      await _releaseLock(lifecycleLock);
      lifecycleLockHeld = false;

      final releasePath = candidate.path;
      final binary = p.join(
        releasePath,
        executable == 'flutter' ? 'bin/flutter' : _dartExecutable,
      );
      late final Process process;
      try {
        process = await Process.start(binary, arguments);
      } on Object catch (error) {
        throw SdkLaunchException(
          status: 5,
          message:
              'could not start Flutter $releaseVersion $executable: '
              '$error',
        );
      }
      final stdoutDone = stdoutByteSink == null
          ? process.stdout
                .transform(utf8.decoder)
                .listen(stdoutSink.write)
                .asFuture<void>()
          : stdoutByteSink.addStream(process.stdout);
      final stderrDone = stderrByteSink == null
          ? process.stderr
                .transform(utf8.decoder)
                .listen(stderrSink.write)
                .asFuture<void>()
          : stderrByteSink.addStream(process.stderr);
      final stdinSubscription = stdinStream.listen(
        process.stdin.add,
        onDone: process.stdin.close,
        onError: (Object _) => process.stdin.close(),
      );
      final childStatus = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      await stdinSubscription.cancel();
      if (stdoutByteSink != null) await stdoutByteSink.flush();
      if (stderrByteSink != null) await stderrByteSink.flush();
      return childStatus < 0 ? 128 + -childStatus : childStatus;
    } finally {
      if (lifecycleLockHeld) await _releaseLock(lifecycleLock);
      if (leaseCreated && lease.existsSync()) await lease.delete();
      if (leaseDirectory.existsSync() && leaseDirectory.listSync().isEmpty) {
        await leaseDirectory.delete();
      }
    }
  }

  Future<InstalledRelease?> _readiness(
    Directory release,
    Directory root,
  ) async {
    final marker = File(p.join(release.path, '.wren-release.json'));
    String? channel;
    String? version;
    String? hostName;
    Map<String, Object?>? releaseData;
    var reason = 'release metadata is invalid';
    try {
      final data = jsonDecode(await marker.readAsString());
      if (data is! Map<String, Object?>) {
        return _invalidRelease(release, 'release metadata is invalid');
      }
      releaseData = data;
      channel = data['channel'] as String?;
      version = data['version'] as String?;
      hostName = data['host'] as String?;
      final architecture = data['architecture'] as String?;
      final host = _hostFromIdentity(hostName, architecture);
      if (channel == null ||
          version == null ||
          host == null ||
          data['state'] != 'ready' ||
          p.basename(release.path) !=
              '$channel-$version-${_readinessVariant(host)}') {
        reason = 'recorded release identity does not match its installation';
      } else {
        final frameworkRevision = data['frameworkRevision'];
        final engineRevision = data['engineRevision'];
        final sourceKey = data['sourceKey'];
        if (frameworkRevision is! String ||
            !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(frameworkRevision)) {
          reason = 'recorded framework identity is invalid';
        } else if (engineRevision is! String ||
            !RegExp(_engineRevisionPattern).hasMatch(engineRevision)) {
          reason = 'recorded engine identity is invalid';
        } else if (sourceKey !=
            '$engineRevision-${host.catalogOs}-${host.catalogArchitecture}') {
          reason = 'recorded shared source identity is invalid';
        } else {
          final actualFramework = await _gitText(release.path, [
            'rev-parse',
            'HEAD',
          ], userMessage: 'could not read framework identity');
          if (actualFramework.toLowerCase() !=
              frameworkRevision.toLowerCase()) {
            reason = 'framework checkout does not match its recorded identity';
          } else {
            final actualEngine = (await File(
              p.join(release.path, 'bin/internal/engine.version'),
            ).readAsString()).trim();
            if (actualEngine.toLowerCase() != engineRevision.toLowerCase()) {
              reason = 'engine revision does not match its recorded identity';
            } else {
              final source = Directory(
                p.join(root.path, 'sources', sourceKey! as String),
              );
              reason =
                  await _quickReadinessReason(
                    release,
                    source,
                    data,
                    engineRevision,
                    host,
                  ) ??
                  '';
            }
          }
        }
      }
    } on Object catch (error) {
      reason = 'could not validate installed release: $error';
    }

    final current = releaseData;
    if (current == null) {
      return _invalidRelease(release, reason);
    }
    final needsRepair = reason.isNotEmpty;
    final updated = Map<String, Object?>.from(current)
      ..remove('readiness')
      ..remove('readinessReason');
    if (needsRepair) {
      updated['readiness'] = 'needs-repair';
      updated['readinessReason'] = reason;
    }
    if (jsonEncode(updated) != jsonEncode(current)) {
      await _publishManifest(release.path, updated);
    }
    if (channel == null || version == null || hostName == null) {
      return _invalidRelease(release, reason);
    }
    return InstalledRelease(
      channel: channel,
      version: version,
      host: hostName,
      needsRepair: needsRepair,
      dartVersion: current['canonicalDartVersion'] as String?,
      repairReason: needsRepair ? reason : null,
    );
  }

  InstalledRelease _invalidRelease(Directory release, String reason) =>
      InstalledRelease(
        channel: 'unknown',
        version: p.basename(release.path),
        host: 'unknown',
        needsRepair: true,
        repairReason: reason,
      );

  Future<String?> _quickReadinessReason(
    Directory release,
    Directory source,
    Map<String, Object?> releaseData,
    String engineRevision,
    HostPlatform host,
  ) async {
    final missing = _readinessMissingArtifact(release.path, host);
    if (missing != null) return 'required artifact is missing: $missing';
    for (final executable in [
      'bin/flutter',
      _dartExecutable,
      ..._readinessHostExecutables(host),
    ]) {
      final file = File(p.join(release.path, executable));
      if ((file.statSync().mode & 0x49) == 0) {
        return 'required executable is not runnable: $executable';
      }
    }
    final stampReason = _stampReadinessReason(release, engineRevision, host);
    if (stampReason != null) return stampReason;
    final cache = Directory(p.join(release.path, 'bin/cache'));
    final sourcesPath = p.join(
      environment.dataDirectory.absolute.path,
      'sources',
    );
    for (final entity in cache.listSync(recursive: true, followLinks: false)) {
      if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
          FileSystemEntityType.link) {
        continue;
      }
      try {
        if (p.isWithin(
          sourcesPath,
          Link(entity.path).resolveSymbolicLinksSync(),
        )) {
          return 'private cache links into the shared artifact source';
        }
      } on FileSystemException {
        return 'private cache contains a broken symbolic link';
      }
    }
    final sourceMarker = File(p.join(source.path, '.wren-source.json'));
    if (!sourceMarker.existsSync()) {
      return 'shared artifact source is missing';
    }
    try {
      final metadata = jsonDecode(await sourceMarker.readAsString());
      if (metadata is! Map<String, Object?> ||
          metadata['state'] != 'ready' ||
          metadata['engineRevision'] != engineRevision ||
          metadata['host'] != host.catalogOs ||
          metadata['architecture'] != host.catalogArchitecture ||
          metadata['archiveVariant'] != _readinessVariant(host) ||
          jsonEncode(metadata['artifacts']) !=
              jsonEncode(_readinessSourceArtifacts(host)) ||
          !_hasValidSourceInventory(metadata['inventory'])) {
        return 'shared artifact source metadata is incoherent';
      }
      for (final path in _readinessSourceArtifacts(host)) {
        if (!Directory(p.join(source.path, path)).existsSync()) {
          return 'shared artifact source is missing: $path';
        }
      }
      final sourceMissing = _readinessMissingArtifact(source.path, host);
      if (sourceMissing != null) {
        return 'shared artifact source is missing: $sourceMissing';
      }
      for (final executable in [
        _dartExecutable,
        ..._readinessHostExecutables(host),
      ]) {
        final file = File(p.join(source.path, executable));
        if ((file.statSync().mode & 0x49) == 0) {
          return 'shared artifact source executable is not runnable: '
              '$executable';
        }
      }
      final stamps = metadata['stamps'];
      final stampFiles = _readinessStampFiles(host);
      if (stamps is! Map<String, Object?> ||
          stampFiles
              .where((path) => path != 'engine.realm')
              .any((path) => '${stamps[path]}'.trim() != engineRevision) ||
          stamps['engine.realm'] == null) {
        return 'shared artifact source stamps are incoherent';
      }
      for (final stamp in stampFiles) {
        if (File(p.join(release.path, 'bin/cache', stamp)).readAsStringSync() !=
            stamps[stamp]) {
          return 'release cache stamps do not match shared source metadata';
        }
      }
    } on Object {
      return 'shared artifact source metadata is invalid';
    }
    final dartVersion = releaseData['canonicalDartVersion'];
    if (dartVersion is! String || !_readinessIsSemVersion(dartVersion)) {
      return 'recorded Dart identity is missing';
    }
    return null;
  }

  String? _stampReadinessReason(
    Directory release,
    String engineRevision,
    HostPlatform host,
  ) {
    for (final stamp in _readinessStampFiles(host)) {
      final file = File(p.join(release.path, 'bin/cache', stamp));
      if (!file.existsSync()) return 'Flutter cache stamp is missing: $stamp';
      if (stamp != 'engine.realm' &&
          file.readAsStringSync().trim() != engineRevision) {
        return 'Flutter cache stamp does not match engine revision: $stamp';
      }
    }
    return null;
  }

  HostPlatform? _hostFromIdentity(String? host, String? architecture) {
    if (host == 'linux' && architecture == 'x64') return HostPlatform.linuxX64;
    if (host == 'macos' && architecture == 'arm64') {
      return HostPlatform.macosArm64;
    }
    return null;
  }

  int _readinessChannelOrder(String channel) => channel == 'stable' ? 0 : 1;

  String _readinessVariant(HostPlatform host) =>
      host == HostPlatform.linuxX64 ? 'linux-x64' : 'darwin-arm64';

  List<String> _readinessStampFiles(HostPlatform host) => [
    'engine-dart-sdk.stamp',
    'engine.stamp',
    'flutter_sdk.stamp',
    if (host == HostPlatform.linuxX64) 'linux-sdk.stamp',
    if (host == HostPlatform.macosArm64) 'macos-sdk.stamp',
    'flutter_web_sdk.stamp',
    'engine.realm',
  ];

  List<String> _readinessSourceArtifacts(HostPlatform host) => [
    'bin/cache/dart-sdk',
    'bin/cache/artifacts/engine/common',
    if (host == HostPlatform.linuxX64) ...[
      'bin/cache/artifacts/engine/linux-x64',
      'bin/cache/artifacts/engine/linux-x64-profile',
      'bin/cache/artifacts/engine/linux-x64-release',
    ],
    if (host == HostPlatform.macosArm64) ...[
      'bin/cache/artifacts/engine/darwin-arm64',
      'bin/cache/artifacts/engine/darwin-arm64-profile',
      'bin/cache/artifacts/engine/darwin-arm64-release',
    ],
    'bin/cache/flutter_web_sdk',
    'bin/cache/pkg/sky_engine',
    'bin/cache/pkg/flutter_gpu',
  ];

  List<String> _readinessHostExecutables(HostPlatform host) =>
      host == HostPlatform.linuxX64
      ? const [
          'bin/cache/artifacts/engine/linux-x64/gen_snapshot',
          'bin/cache/artifacts/engine/linux-x64/flutter_tester',
        ]
      : const ['bin/cache/artifacts/engine/darwin-arm64/gen_snapshot'];

  String? _readinessMissingArtifact(String rootPath, HostPlatform host) {
    final directories = <String>[
      'bin/cache/artifacts/engine/common/flutter_patched_sdk',
      'bin/cache/artifacts/engine/common/flutter_patched_sdk_product',
      'bin/cache/flutter_web_sdk',
      'bin/cache/pkg/sky_engine',
      'bin/cache/pkg/flutter_gpu',
      if (host == HostPlatform.linuxX64)
        'bin/cache/artifacts/engine/linux-x64-profile/flutter_linux',
      if (host == HostPlatform.linuxX64)
        'bin/cache/artifacts/engine/linux-x64-release/flutter_linux',
      if (host == HostPlatform.macosArm64)
        'bin/cache/artifacts/engine/darwin-arm64/FlutterMacOS.xcframework',
      if (host == HostPlatform.macosArm64) 'bin/cache/artifacts/engine/darwin-arm64-profile/FlutterMacOS.xcframework',
      if (host == HostPlatform.macosArm64) 'bin/cache/artifacts/engine/darwin-arm64-release/FlutterMacOS.xcframework',
    ];
    final files = <String>[
      _dartExecutable,
      if (host == HostPlatform.linuxX64) ...[
        'bin/cache/artifacts/engine/linux-x64/gen_snapshot',
        'bin/cache/artifacts/engine/linux-x64/flutter_tester',
        'bin/cache/artifacts/engine/linux-x64/libflutter_linux_gtk.so',
        'bin/cache/artifacts/engine/linux-x64-profile/flutter_linux/libflutter_linux_gtk.so',
        'bin/cache/artifacts/engine/linux-x64-release/flutter_linux/libflutter_linux_gtk.so',
      ],
      if (host == HostPlatform.macosArm64) ...[
        'bin/cache/artifacts/engine/darwin-arm64/gen_snapshot',
        'bin/cache/artifacts/engine/darwin-arm64/FlutterMacOS.xcframework/Info.plist',
        'bin/cache/artifacts/engine/darwin-arm64-profile/FlutterMacOS.xcframework/Info.plist',
        'bin/cache/artifacts/engine/darwin-arm64-release/FlutterMacOS.xcframework/Info.plist',
      ],
    ];
    for (final path in directories) {
      if (FileSystemEntity.typeSync(p.join(rootPath, path)) !=
          FileSystemEntityType.directory) {
        return path;
      }
    }
    for (final path in files) {
      if (FileSystemEntity.typeSync(p.join(rootPath, path)) !=
          FileSystemEntityType.file) {
        return path;
      }
    }
    return null;
  }

  bool _hasValidSourceInventory(Object? value) {
    if (value is! List<Object?>) return false;
    for (final entry in value) {
      if (entry is! Map<String, Object?> ||
          entry['path'] is! String ||
          entry['sha256'] is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(entry['sha256']! as String)) {
        return false;
      }
      final path = p.normalize(entry['path']! as String);
      if (p.isAbsolute(path) || p.split(path).contains('..')) return false;
    }
    return true;
  }

  bool _readinessIsSemVersion(String value) {
    try {
      Version.parse(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Installs [release] for [host] and returns its published result.
  Future<InstallResult> install(
    FlutterRelease release, {
    required HostPlatform host,
  }) async {
    if (!RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(release.frameworkRevision)) {
      throw const InstallException(
        'the Flutter catalog has a missing or invalid framework revision.',
      );
    }
    if (release.channel != 'stable' && release.channel != 'beta') {
      throw const InstallException(
        'the Flutter release catalog specifies an unsupported channel.',
      );
    }
    final root = environment.dataDirectory.absolute;
    final releaseKey =
        '${release.channel}-${release.version}-${_archiveVariant(host)}';
    final releasePath = p.join(root.path, 'releases', releaseKey);
    final lockPath = p.join(root.path, 'locks', 'install-$releaseKey');
    final releaseLock = await _acquireLock(
      Directory(lockPath),
      onWait: () => _progress(
        'Waiting for another install of Flutter ${release.version}',
      ),
    );
    try {
      final existing = await _existingInstall(releasePath, release, host);
      if (existing == _ExistingInstall.healthy) {
        return InstallResult(
          message: 'Flutter ${release.version} is already installed and ready.',
          alreadyInstalled: true,
        );
      }
      if (existing == _ExistingInstall.damaged) {
        throw InstallException(
          'Flutter ${release.version} is installed but needs repair; run '
          '`wren repair ${release.version}`.',
        );
      }

      if (Directory(releasePath).existsSync()) {
        await _removeIncompleteWorktree(releasePath, root);
      }
      await Directory(releasePath).parent.create(recursive: true);
      final stagingRoot = Directory(
        p.join(root.path, 'staging', 'install-$releaseKey'),
      );
      final checkoutStage = Directory(p.join(stagingRoot.path, 'checkout'));
      var checkoutPublished = false;
      var worktreeCreated = false;
      if (stagingRoot.existsSync()) {
        if (Directory(p.join(root.path, 'flutter.git')).existsSync()) {
          await _discardWorktree(root, checkoutStage.path);
        }
        await stagingRoot.delete(recursive: true);
      }
      await stagingRoot.create(recursive: true);
      try {
        _progress('Preparing Flutter ${release.version} for ${host.label}');
        await _requireGit();
        final repoLock = await _acquireLock(
          Directory(p.join(root.path, 'locks', 'flutter-git')),
          onWait: () => _progress('Waiting for the shared Flutter Git lock'),
        );
        try {
          await _ensureSharedRepository(root);
          await _fetchFrameworkCommit(
            root,
            release.frameworkRevision,
            release.version,
          );
          await _runGit(root, [
            '--git-dir',
            p.join(root.path, 'flutter.git'),
            'worktree',
            'add',
            '--detach',
            checkoutStage.path,
            release.frameworkRevision,
          ], userMessage: 'could not create a detached Flutter worktree');
          worktreeCreated = true;
        } finally {
          await _releaseLock(repoLock);
        }

        final checkoutRevision = await _gitText(checkoutStage.path, [
          'rev-parse',
          'HEAD',
        ], userMessage: 'could not verify the Flutter checkout revision');
        if (checkoutRevision.toLowerCase() !=
            release.frameworkRevision.toLowerCase()) {
          throw const InstallException(
            'Flutter checkout revision does not match the release catalog.',
          );
        }
        final releaseTag = await _gitText(checkoutStage.path, [
          'describe',
          '--tags',
          '--exact-match',
          'HEAD',
        ], userMessage: 'could not verify the Flutter release tag');
        if (releaseTag != release.version) {
          throw InstallException(
            'Flutter revision $checkoutRevision is not tagged as '
            '${release.version}.',
          );
        }
        final engineRevision = (await File(
          p.join(checkoutStage.path, 'bin/internal/engine.version'),
        ).readAsString()).trim();
        if (!RegExp(_engineRevisionPattern).hasMatch(engineRevision)) {
          throw const InstallException(
            'the selected Flutter checkout has a missing or invalid engine '
            'revision.',
          );
        }
        final resolvedSourceKey = _sourceKey(engineRevision, host);
        final resolvedSourcePath = p.join(
          root.path,
          'sources',
          resolvedSourceKey,
        );

        final sourceLock = await _acquireLock(
          Directory(p.join(root.path, 'locks', 'source-$resolvedSourceKey')),
          onWait: () => _progress('Waiting for the shared engine source lock'),
        );
        try {
          var artifactsPrepared = false;
          final sourceDirectory = Directory(resolvedSourcePath);
          if (sourceDirectory.existsSync()) {
            await _validateSource(
              sourceDirectory,
              engineRevision: engineRevision,
              host: host,
            );
            await _materializeSource(sourceDirectory, checkoutStage, host);
          } else {
            _progress('Downloading ${host.label} and web artifacts');
            // Flutter's artifact updater validates storage-provider transfer
            // checksums and rejects archives it cannot extract. Wren checks
            // the runtime identity and resulting host artifact layout.
            await _runFlutter(
              checkoutStage,
              _precacheArguments(host),
              userMessage:
                  'Flutter failed to download or extract required artifacts',
            );
            await _validateCheckout(
              checkoutStage,
              release: release,
              frameworkRevision: checkoutRevision,
              engineRevision: engineRevision,
              host: host,
            );
            artifactsPrepared = true;
            final sourceStage = Directory(p.join(stagingRoot.path, 'source'));
            await _createSource(
              checkoutStage,
              sourceStage,
              engineRevision: engineRevision,
              host: host,
            );
            await sourceDirectory.parent.create(recursive: true);
            await sourceStage.rename(sourceDirectory.path);
          }
          if (!artifactsPrepared) {
            _progress('Validating ${host.label} and web artifacts');
            await _runFlutter(
              checkoutStage,
              _precacheArguments(host),
              userMessage:
                  'Flutter failed to validate or prepare required artifacts',
            );
            await _validateCheckout(
              checkoutStage,
              release: release,
              frameworkRevision: checkoutRevision,
              engineRevision: engineRevision,
              host: host,
            );
          }
        } finally {
          await _releaseLock(sourceLock);
        }
        _validatePrivateCacheBoundary(checkoutStage, root);

        await checkoutStage.rename(releasePath);
        checkoutPublished = true;
        final worktreeRepairLock = await _acquireLock(
          Directory(p.join(root.path, 'locks', 'flutter-git')),
        );
        try {
          await _runGit(root, [
            '--git-dir',
            p.join(root.path, 'flutter.git'),
            'worktree',
            'repair',
            releasePath,
          ], userMessage: 'could not update Flutter worktree metadata');
        } finally {
          await _releaseLock(worktreeRepairLock);
        }

        final manifest = <String, Object?>{
          'format': 1,
          'channel': release.channel,
          'version': release.version,
          'frameworkRevision': checkoutRevision,
          'engineRevision': engineRevision,
          'host': host.catalogOs,
          'architecture': host.catalogArchitecture,
          'canonicalDartVersion': release.dartVersion,
          'archive': release.archive,
          'archiveSha256': release.archiveSha256,
          'sourceKey': resolvedSourceKey,
          'state': 'ready',
        };
        await _publishManifest(releasePath, manifest);
        return InstallResult(
          message: 'Installed Flutter ${release.version} for ${host.label}.',
          alreadyInstalled: false,
        );
      } on InstallException {
        rethrow;
      } on Object catch (error) {
        throw InstallException(
          'Flutter ${release.version} installation failed: $error',
        );
      } finally {
        final ready = File(p.join(releasePath, '.wren-release.json'))
            .existsSync();
        if (!ready) {
          if (checkoutPublished) {
            await _discardWorktree(root, releasePath);
            if (Directory(releasePath).existsSync()) {
              await Directory(releasePath).delete(recursive: true);
            }
          } else if (worktreeCreated) {
            await _discardWorktree(root, checkoutStage.path);
          }
        }
        if (stagingRoot.existsSync()) {
          await stagingRoot.delete(recursive: true);
        }
      }
    } finally {
      await _releaseLock(releaseLock);
    }
  }

  void _progress(String message) => onProgress?.call(message);

  Future<void> _requireGit() async {
    try {
      final result = await Process.run('git', ['--version']);
      if (result.exitCode != 0) {
        throw StateError('git --version exited ${result.exitCode}');
      }
    } on Object catch (error) {
      throw InstallException(
        'Git is required to install Flutter. Install Git and retry. ($error)',
      );
    }
  }

  Future<void> _ensureSharedRepository(Directory root) async {
    final repository = Directory(p.join(root.path, 'flutter.git'));
    if (repository.existsSync()) return;
    await repository.parent.create(recursive: true);
    final stagingRepository = Directory(
      p.join(root.path, 'staging', 'flutter-repo'),
    );
    await stagingRepository.parent.create(recursive: true);
    if (stagingRepository.existsSync()) {
      await stagingRepository.delete(recursive: true);
    }
    await _runGit(root, [
      'init',
      '--bare',
      stagingRepository.path,
    ], userMessage: 'could not initialize Wren’s shared Flutter repository');
    await _runGit(root, [
      '--git-dir',
      stagingRepository.path,
      'remote',
      'add',
      'origin',
      environment.flutterRepository.toString(),
    ], userMessage: 'could not configure the Flutter Git remote');
    try {
      await stagingRepository.rename(repository.path);
    } catch (_) {
      if (repository.existsSync()) {
        await stagingRepository.delete(recursive: true);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _fetchFrameworkCommit(
    Directory root,
    String revision,
    String version,
  ) async {
    await _runGit(root, [
      '--git-dir',
      p.join(root.path, 'flutter.git'),
      'fetch',
      '--filter=blob:none',
      '--no-tags',
      'origin',
      revision,
      'refs/tags/$version:refs/tags/$version',
    ], userMessage: 'could not fetch Flutter framework revision $revision');
  }

  Future<void> _validateCheckout(
    Directory checkout, {
    required FlutterRelease release,
    required String frameworkRevision,
    required String engineRevision,
    required HostPlatform host,
  }) async {
    final missingArtifact = _missingRequiredArtifact(checkout.path, host);
    if (missingArtifact != null) {
      throw InstallException(
        'required Flutter artifact is missing: $missingArtifact.',
      );
    }

    final flutterExecutable = File(p.join(checkout.path, 'bin/flutter'));
    final dartExecutable = File(p.join(checkout.path, _dartExecutable));
    _requireExecutable(flutterExecutable, 'Flutter');
    _requireExecutable(dartExecutable, 'Dart');
    for (final artifact in _hostExecutables(host)) {
      _requireExecutable(File(p.join(checkout.path, artifact)), artifact);
    }

    final flutter = await _run(
      flutterExecutable.path,
      ['--version', '--machine'],
      workingDirectory: checkout.path,
      userMessage: 'the installed Flutter tool did not run',
    );
    final versionData = _decodeVersionOutput('${flutter.stdout}');
    // Flutter reports [user-branch] for a detached worktree. Its framework
    // revision and release tag are still checked against the catalog below.
    final reportedChannel = versionData['channel'];
    if ((reportedChannel != release.channel &&
            reportedChannel != '[user-branch]') ||
        versionData['flutterVersion'] != release.version ||
        versionData['frameworkRevision'] != frameworkRevision ||
        versionData['engineRevision'] != engineRevision) {
      throw InstallException(
        'Flutter runtime identity does not match the selected catalog release '
        '(channel ${versionData['channel']}, version '
        '${versionData['flutterVersion']}, framework '
        '${versionData['frameworkRevision']}, engine '
        '${versionData['engineRevision']}).',
      );
    }
    final runtimeDartVersion = versionData['dartSdkVersion'];
    if (runtimeDartVersion is! String ||
        !_sameVersion(runtimeDartVersion, release.dartVersion)) {
      throw InstallException(
        'Flutter reports bundled Dart ${runtimeDartVersion ?? 'unknown'}; '
        'the release catalog specifies ${release.dartVersion}.',
      );
    }

    final dart = await _run(
      dartExecutable.path,
      ['--version'],
      workingDirectory: checkout.path,
      userMessage: 'the bundled Dart executable did not run',
    );
    final dartOutput = '${dart.stdout}\n${dart.stderr}';
    final match = RegExp(r'Dart SDK version:\s+([^\s]+)')
        .firstMatch(dartOutput);
    final reportedDartVersion = match?.group(1);
    if (reportedDartVersion == null ||
        !_sameVersion(reportedDartVersion, release.dartVersion)) {
      throw InstallException(
        'bundled Dart reports ${reportedDartVersion ?? 'an unknown version'}; '
        'the release catalog specifies ${release.dartVersion}.',
      );
    }
    final reportedDartHost = RegExp('on "([^"]+)"')
        .firstMatch(dartOutput)
        ?.group(1);
    final expectedDartHost = host == HostPlatform.linuxX64
        ? 'linux_x64'
        : 'macos_arm64';
    if (reportedDartHost != expectedDartHost) {
      throw InstallException(
        'bundled Dart runs as ${reportedDartHost ?? 'an unknown host'}; '
        'Wren requires native $expectedDartHost.',
      );
    }
  }

  Future<_ExistingInstall> _existingInstall(
    String releasePath,
    FlutterRelease release,
    HostPlatform host,
  ) async {
    final marker = File(p.join(releasePath, '.wren-release.json'));
    if (!marker.existsSync()) return _ExistingInstall.incomplete;
    try {
      final data =
          jsonDecode(await marker.readAsString()) as Map<String, Object?>;
      if (data['state'] != 'ready' ||
          data['channel'] != release.channel ||
          data['version'] != release.version ||
          data['frameworkRevision'] != release.frameworkRevision ||
          data['host'] != host.catalogOs ||
          data['architecture'] != host.catalogArchitecture) {
        return _ExistingInstall.damaged;
      }
      if (_missingRequiredArtifact(releasePath, host) != null) {
        return _ExistingInstall.damaged;
      }
      return _ExistingInstall.healthy;
    } on Object {
      return _ExistingInstall.damaged;
    }
  }

  Future<void> _createSource(
    Directory checkout,
    Directory sourceStage, {
    required String engineRevision,
    required HostPlatform host,
  }) async {
    await sourceStage.create(recursive: true);
    // Keep immutable artifact payloads in the source; stamps, tool snapshots,
    // downloads, and other mutable cache state stay in the release checkout.
    final artifactPaths = _sourceArtifactPaths(host);
    final stampFiles = _sourceStampFiles(host);
    for (final relativePath in artifactPaths) {
      final source = Directory(p.join(checkout.path, relativePath));
      if (!source.existsSync()) {
        throw InstallException(
          'cannot retain missing shared artifact $relativePath.',
        );
      }
      await _copyTree(
        source,
        Directory(p.join(sourceStage.path, relativePath)),
      );
    }
    for (final relativePath in artifactPaths) {
      if (!Directory(p.join(sourceStage.path, relativePath)).existsSync()) {
        throw InstallException(
          'shared artifact source is incomplete at $relativePath.',
        );
      }
    }
    final stamps = <String, String>{};
    for (final relativePath in stampFiles) {
      final stamp = File(p.join(checkout.path, 'bin/cache', relativePath));
      if (stamp.existsSync()) {
        stamps[relativePath] = await stamp.readAsString();
      }
    }
    for (final relativePath in stampFiles.where(
      (path) => path != 'engine.realm',
    )) {
      if (stamps[relativePath]?.trim() != engineRevision) {
        throw InstallException(
          'Flutter cache stamp $relativePath does not match engine revision '
          '$engineRevision.',
        );
      }
    }
    if (stamps['engine.realm'] == null) {
      throw const InstallException('Flutter cache is missing engine.realm.');
    }
    await _publishManifest(sourceStage.path, {
      'format': 1,
      'engineRevision': engineRevision,
      'host': host.catalogOs,
      'architecture': host.catalogArchitecture,
      'archiveVariant': _archiveVariant(host),
      'artifacts': artifactPaths,
      'stamps': stamps,
      'inventory': await _sourceInventory(sourceStage, host),
      'state': 'ready',
    }, filename: '.wren-source.json');
  }

  Future<void> _validateSource(
    Directory source, {
    required String engineRevision,
    required HostPlatform host,
  }) async {
    final marker = File(p.join(source.path, '.wren-source.json'));
    if (!marker.existsSync()) {
      throw const InstallException(
        'the retained host artifact source is damaged.',
      );
    }
    final artifactPaths = _sourceArtifactPaths(host);
    final stampFiles = _sourceStampFiles(host);
    try {
      final data =
          jsonDecode(await marker.readAsString()) as Map<String, Object?>;
      if (data['state'] != 'ready' ||
          data['engineRevision'] != engineRevision ||
          data['host'] != host.catalogOs ||
          data['architecture'] != host.catalogArchitecture ||
          data['archiveVariant'] != _archiveVariant(host) ||
          jsonEncode(data['artifacts']) != jsonEncode(artifactPaths)) {
        throw const InstallException(
          'the retained host artifact source is damaged.',
        );
      }
      for (final relativePath in artifactPaths) {
        if (!Directory(p.join(source.path, relativePath)).existsSync()) {
          throw const InstallException(
            'the retained host artifact source is damaged.',
          );
        }
      }
      if (jsonEncode(data['inventory']) !=
          jsonEncode(await _sourceInventory(source, host))) {
        throw const InstallException(
          'the retained host artifact source is damaged.',
        );
      }
      final stamps = data['stamps'];
      if (stamps is! Map<String, Object?> ||
          stamps.keys.toSet().difference(stampFiles.toSet()).isNotEmpty ||
          !stamps.keys.toSet().containsAll(
            stampFiles.where((path) => path != 'engine.realm'),
          ) ||
          stampFiles
              .where((path) => path != 'engine.realm')
              .any((path) => '${stamps[path]}'.trim() != engineRevision) ||
          stamps['engine.realm'] == null) {
        throw const InstallException(
          'the retained host artifact source is damaged.',
        );
      }
    } on InstallException {
      rethrow;
    } on Object {
      throw const InstallException(
        'the retained host artifact source is damaged.',
      );
    }
  }

  Future<void> _materializeSource(
    Directory source,
    Directory checkout,
    HostPlatform host,
  ) async {
    final data = jsonDecode(
      await File(p.join(source.path, '.wren-source.json')).readAsString(),
    ) as Map<String, Object?>;
    for (final relativePath in _sourceArtifactPaths(host)) {
      final destination = Directory(p.join(checkout.path, relativePath));
      if (destination.existsSync()) await destination.delete(recursive: true);
      await _copyTree(
        Directory(p.join(source.path, relativePath)),
        destination,
      );
    }
    final stamps = data['stamps']! as Map<String, Object?>;
    for (final entry in stamps.entries) {
      await File(p.join(checkout.path, 'bin/cache', entry.key))
          .writeAsString(entry.value! as String, flush: true);
    }
  }

  Future<void> _publishManifest(
    String directory,
    Map<String, Object?> manifest, {
    String filename = '.wren-release.json',
  }) async {
    final target = File(p.join(directory, filename));
    final temporary = File('${target.path}.tmp-${_randomId()}');
    await temporary.writeAsString(jsonEncode(manifest), flush: true);
    await temporary.rename(target.path);
  }

  Future<void> _removeIncompleteWorktree(String path, Directory root) async {
    if (Directory(p.join(root.path, 'flutter.git')).existsSync()) {
      await _discardWorktree(root, path);
    }
    if (Directory(path).existsSync()) {
      await Directory(path).delete(recursive: true);
    }
  }

  Future<void> _discardWorktree(Directory root, String path) async {
    final lock = await _acquireLock(
      Directory(p.join(root.path, 'locks', 'flutter-git')),
    );
    try {
      final result = await Process.run('git', [
        '--git-dir',
        p.join(root.path, 'flutter.git'),
        'worktree',
        'remove',
        '--force',
        path,
      ]);
      if (result.exitCode != 0 && Directory(path).existsSync()) {
        await Directory(path).delete(recursive: true);
      }
      await Process.run('git', [
        '--git-dir',
        p.join(root.path, 'flutter.git'),
        'worktree',
        'prune',
      ]);
    } finally {
      await _releaseLock(lock);
    }
  }

  Future<String> _gitText(
    String workingDirectory,
    List<String> arguments, {
    required String userMessage,
  }) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: workingDirectory,
    );
    if (result.exitCode != 0) {
      throw InstallException('$userMessage: ${_processDetails(result)}');
    }
    return '${result.stdout}'.trim();
  }

  Future<void> _runGit(
    Directory root,
    List<String> arguments, {
    required String userMessage,
  }) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: root.path,
    );
    if (result.exitCode != 0) {
      throw InstallException('$userMessage: ${_processDetails(result)}');
    }
  }

  Future<ProcessResult> _runFlutter(
    Directory checkout,
    List<String> arguments, {
    required String userMessage,
  }) => _run(
    p.join(checkout.path, 'bin/flutter'),
    arguments,
    workingDirectory: checkout.path,
    userMessage: userMessage,
  );

  Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required String userMessage,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
      if (result.exitCode != 0) {
        throw InstallException('$userMessage: ${_processDetails(result)}');
      }
      return result;
    } on InstallException {
      rethrow;
    } on Object catch (error) {
      throw InstallException('$userMessage: $error');
    }
  }

  void _requireExecutable(File file, String name) {
    if (!file.existsSync()) {
      throw InstallException(
        'required $name executable is missing: ${file.path}.',
      );
    }
    final mode = file.statSync().mode;
    if (mode & 0x49 == 0) {
      throw InstallException(
        'required $name file is not executable: ${file.path}.',
      );
    }
  }
}

enum _ExistingInstall { incomplete, healthy, damaged }

List<String> _hostExecutables(HostPlatform host) =>
    host == HostPlatform.linuxX64
    ? const [
        'bin/cache/artifacts/engine/linux-x64/gen_snapshot',
        'bin/cache/artifacts/engine/linux-x64/flutter_tester',
      ]
    : const ['bin/cache/artifacts/engine/darwin-arm64/gen_snapshot'];

String? _missingRequiredArtifact(String rootPath, HostPlatform host) {
  for (final relativePath in _requiredDirectories(host)) {
    if (FileSystemEntity.typeSync(p.join(rootPath, relativePath)) !=
        FileSystemEntityType.directory) {
      return relativePath;
    }
  }
  for (final relativePath in _requiredFiles(host)) {
    if (FileSystemEntity.typeSync(p.join(rootPath, relativePath)) !=
        FileSystemEntityType.file) {
      return relativePath;
    }
  }
  return null;
}

Future<List<Map<String, String>>> _sourceInventory(
  Directory source,
  HostPlatform host,
) async {
  final entries = <Map<String, String>>[];
  for (final relativePath in _sourceArtifactPaths(host)) {
    final root = Directory(p.join(source.path, relativePath));
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        if (FileSystemEntity.typeSync(entity.path, followLinks: false) ==
            FileSystemEntityType.link) {
          throw const InstallException(
            'the retained host artifact source contains a symbolic link.',
          );
        }
        continue;
      }
      final digest = await sha256.bind(File(entity.path).openRead()).first;
      entries.add({
        'path': p.relative(entity.path, from: source.path),
        'sha256': digest.toString(),
      });
    }
  }
  entries.sort((left, right) => left['path']!.compareTo(right['path']!));
  return entries;
}

Directory _defaultDataDirectory() {
  final env = Platform.environment;
  final override = env['WREN_DATA_DIR'];
  if (override != null && override.trim().isNotEmpty) {
    return Directory(override);
  }
  final xdg = env['XDG_DATA_HOME'];
  if (xdg != null && xdg.trim().isNotEmpty) {
    return Directory(p.join(xdg, 'wren'));
  }
  final home = env['HOME'];
  final base = home == null || home.isEmpty ? Directory.current.path : home;
  return Directory(p.join(base, '.local', 'share', 'wren'));
}

Future<Directory> _acquireLock(
  Directory lock, {
  void Function()? onWait,
}) async {
  await lock.parent.create(recursive: true);
  var reportedWait = false;
  for (var attempt = 0; attempt < 36000; attempt++) {
    try {
      await lock.create();
      await File(p.join(lock.path, 'owner')).writeAsString('$pid\n');
      return lock;
    } on FileSystemException {
      if (!lock.existsSync()) rethrow;
      if (await _isStaleLock(lock)) {
        try {
          await lock.delete(recursive: true);
        } on FileSystemException {
          // Another waiter may have removed it first.
        }
        continue;
      }
      if (!reportedWait) {
        reportedWait = true;
        onWait?.call();
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw InstallException(
    'timed out waiting for Wren install lock ${lock.path}.',
  );
}

Future<bool> _isStaleLock(Directory lock) async {
  final ownerFile = File(p.join(lock.path, 'owner'));
  final modified = lock.statSync().modified;
  final age = DateTime.now().difference(modified);
  if (!ownerFile.existsSync()) return age > const Duration(seconds: 3);
  final ownerPid = int.tryParse((await ownerFile.readAsString()).trim());
  if (ownerPid == null) return age > const Duration(seconds: 3);
  final probe = await Process.run('kill', ['-0', '$ownerPid']);
  return probe.exitCode != 0 && age > const Duration(seconds: 3);
}

Future<void> _releaseLock(Directory lock) async {
  if (lock.existsSync()) await lock.delete(recursive: true);
}

Future<void> _copyTree(
  Directory source,
  Directory destination, {
  Set<String>? activeDirectories,
}) async {
  final active = activeDirectories ?? <String>{};
  final canonicalSource = p.normalize(await source.resolveSymbolicLinks());
  if (!active.add(canonicalSource)) {
    throw FileSystemException(
      'artifact directory links contain a cycle',
      source.path,
    );
  }
  if (await _copyWithReflink(source, destination)) {
    active.remove(canonicalSource);
    return;
  }
  await destination.create(recursive: true);
  try {
    await for (final entity in source.list(followLinks: false)) {
      final targetPath = p.join(destination.path, p.basename(entity.path));
      switch (FileSystemEntity.typeSync(entity.path, followLinks: false)) {
        case FileSystemEntityType.directory:
          await _copyTree(
            Directory(entity.path),
            Directory(targetPath),
            activeDirectories: active,
          );
        case FileSystemEntityType.file:
          await File(entity.path).copy(targetPath);
        case FileSystemEntityType.link:
          final link = Link(entity.path);
          final resolvedTarget = await link.resolveSymbolicLinks();
          switch (FileSystemEntity.typeSync(resolvedTarget)) {
            case FileSystemEntityType.directory:
              await _copyTree(
                Directory(resolvedTarget),
                Directory(targetPath),
                activeDirectories: active,
              );
            case FileSystemEntityType.file:
              await File(resolvedTarget).copy(targetPath);
            case FileSystemEntityType.notFound:
            case FileSystemEntityType.link:
            case FileSystemEntityType.pipe:
            case FileSystemEntityType.unixDomainSock:
              throw FileSystemException(
                'artifact link target is not a file or directory',
                entity.path,
              );
          }
        case FileSystemEntityType.notFound:
        case FileSystemEntityType.pipe:
        case FileSystemEntityType.unixDomainSock:
          throw FileSystemException(
            'artifact disappeared while copying',
            entity.path,
          );
      }
    }
  } finally {
    active.remove(canonicalSource);
  }
}

Future<bool> _copyWithReflink(Directory source, Directory destination) async {
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (FileSystemEntity.typeSync(entity.path, followLinks: false) ==
        FileSystemEntityType.link) {
      return false;
    }
  }
  await destination.parent.create(recursive: true);
  ProcessResult result;
  try {
    result = await Process.run('cp', [
      '-a',
      '--reflink=auto',
      source.path,
      destination.path,
    ]);
  } on Object {
    return false;
  }
  if (result.exitCode == 0) return true;
  if (destination.existsSync()) await destination.delete(recursive: true);
  return false;
}

void _validatePrivateCacheBoundary(Directory checkout, Directory root) {
  final cache = Directory(p.join(checkout.path, 'bin/cache'));
  final sharedSources = p.join(root.path, 'sources');
  for (final entity in cache.listSync(recursive: true, followLinks: false)) {
    if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
        FileSystemEntityType.link) {
      continue;
    }
    final resolved = p.normalize(
      p.absolute(Link(entity.path).resolveSymbolicLinksSync()),
    );
    if (p.isWithin(sharedSources, resolved)) {
      throw InstallException(
        'private Flutter cache path ${entity.path} links into the shared '
        'artifact source.',
      );
    }
  }
}

Map<String, Object?> _decodeVersionOutput(Object output) {
  try {
    final decoded = jsonDecode('$output');
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException {
    // The failure below adds an actionable Flutter-specific message.
  }
  throw const InstallException(
    'Flutter returned invalid --version --machine JSON.',
  );
}

bool _sameVersion(String left, String right) {
  try {
    return Version.parse(left) == Version.parse(right);
  } on FormatException {
    return false;
  }
}

String _sourceKey(String engineRevision, HostPlatform host) =>
    '$engineRevision-${host.catalogOs}-${host.catalogArchitecture}';

String _randomId() {
  final random = Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

String _processDetails(ProcessResult result) {
  final output = '${result.stderr}\n${result.stdout}'.trim();
  return output.isEmpty ? 'exit code ${result.exitCode}' : output;
}
