import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:wren/src/tracing.dart';

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

class _OptionalArtifactGroup {
  const new({
    required this.id,
    required this.stampFiles,
    required this.arguments,
    required this.pathPrefixes,
  });

  final String id;
  final List<String> stampFiles;
  final List<String> arguments;
  final List<String> pathPrefixes;
}

/// Artifact footprints used by Linux Flutter checkouts from 3.7 onward.
///
/// The framework cache layout is intentionally selected from the pinned
/// Flutter version. Linux host artifacts remain in the required-source
/// inventory; optional target groups use their own engine or Fuchsia roots.
List<_OptionalArtifactGroup> _linuxOptionalArtifactGroups(String version) {
  final parsed = Version.parse(version);
  if (parsed < Version(3, 7, 0)) {
    throw InstallException(
      'optional artifact repair does not support Flutter $version.',
    );
  }

  final legacy = parsed < Version(3, 10, 0);
  return [
    _OptionalArtifactGroup(
      id: 'android-engine',
      stampFiles: legacy
          ? const ['android-sdk.stamp']
          : const [
              'android-sdk.stamp',
              'android-internal-build-artifacts.stamp',
            ],
      arguments: legacy
          ? const ['precache', '--android_gen_snapshot', '--no-universal']
          : const [
              'precache',
              '--android_gen_snapshot',
              '--android_internal_build',
              '--no-universal',
            ],
      pathPrefixes: const ['bin/cache/artifacts/engine/android-'],
    ),
    const _OptionalArtifactGroup(
      id: 'fuchsia-linux',
      stampFiles: ['fuchsia-linux.stamp'],
      arguments: ['precache', '--fuchsia', '--no-universal'],
      pathPrefixes: ['bin/cache/artifacts/fuchsia/sdk/core/linux-amd64/'],
    ),
    const _OptionalArtifactGroup(
      id: 'flutter-runner',
      stampFiles: [
        'flutter_runner.stamp',
        'flutter_runner_debug_symbols.stamp',
      ],
      arguments: ['precache', '--flutter_runner', '--no-universal'],
      pathPrefixes: ['bin/cache/artifacts/flutter_runner/'],
    ),
  ];
}

/// Local storage and source locations for one Wren installation.
///
/// The optional values are also useful for exercising installs against a
/// temporary Git repository without contacting GitHub.
/// Provides the data directory and Flutter source repository for Wren.
class InstallEnvironment {
  /// Creates an environment with optional directory and repository overrides.
  new({Directory? dataDirectory, Uri? flutterRepository, this.waitCancellation})
    : dataDirectory = dataDirectory ?? _defaultDataDirectory(),
      flutterRepository = flutterRepository ?? Uri.parse(_flutterGitUrl);

  /// Root directory for Wren-managed data.
  final Directory dataDirectory;

  /// Git repository used to create Flutter release checkouts.
  final Uri flutterRepository;

  /// Optional cancellation signal used while waiting for an install lock.
  ///
  /// When omitted, Ctrl-C cancels the current lock wait.
  final Stream<void>? waitCancellation;
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

/// Files reclaimed or previewed by a cleanup invocation.
class CleanupResult {
  /// Creates a cleanup result.
  const new({required this.stages, required this.sources});

  /// Orphaned staging directories reclaimed or selected for reclamation.
  final List<String> stages;

  /// Unreferenced shared sources reclaimed or selected for reclamation.
  final List<String> sources;
}

/// Describes a retained shared source repair.
class RepairResult {
  /// Creates a source repair result.
  const new({
    required this.sourceKey,
    required this.replaced,
    this.privateFilesRepaired = false,
    this.optionalArtifactsRepaired = false,
    this.optionalArtifactsValidated = false,
  });

  /// Shared artifact source that was checked or replaced.
  final String sourceKey;

  /// Whether the damaged source was replaced.
  final bool replaced;

  /// Whether release-private files were restored from the retained source.
  final bool privateFilesRepaired;

  /// Whether optional device or build-target files were restored.
  final bool optionalArtifactsRepaired;

  /// Whether present optional artifacts were validated.
  final bool optionalArtifactsValidated;
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

/// An install wait cancelled by the caller.
class InstallCancelledException implements Exception {
  /// Creates a cancellation result with an actionable message.
  new(this.message);

  /// Explanation of the cancelled operation.
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
  new(this.environment, {this.onProgress, this.traceSpan});

  /// Storage and repository configuration used by this installer.
  final InstallEnvironment environment;

  /// Optional callback for progress messages.
  final void Function(String message)? onProgress;

  /// Optional per-invocation trace callback.
  final TraceSpanRunner? traceSpan;

  Future<T> _traceOperation<T>(String name, Future<T> Function() operation) =>
      traceSpan?.call<T>(name, operation) ?? operation();

  Future<Directory> _acquireOperationLock(
    Directory lock, {
    void Function()? onWait,
    Stream<void>? cancellation,
  }) => _traceOperation(
    'lock.wait',
    () => _acquireLock(lock, onWait: onWait, cancellation: cancellation),
  );

  /// Removes provable crash-orphaned stages and unreferenced shared sources.
  ///
  /// Relevant operation locks are held while candidates are rechecked and,
  /// unless [dryRun] is true, removed. The shared Flutter repository and
  /// Wren executable backups are outside the candidate set.
  Future<CleanupResult> cleanup({bool dryRun = false}) async {
    final root = environment.dataDirectory.absolute.path;
    final stages = <String>[];
    final sources = <String>[];
    final staging = Directory(p.join(root, 'staging'));

    if (staging.existsSync()) {
      final entries = staging.listSync(followLinks: false);
      for (final entry in entries) {
        if (FileSystemEntity.typeSync(entry.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        final name = p.basename(entry.path);
        final operationLockName = _stageOperationLockName(name);
        final lockPath = operationLockName == null
            ? null
            : p.join(root, 'locks', operationLockName);
        if (lockPath == null) continue;

        _progress('Checking orphaned stage $name');
        final lock = await _acquireOperationLock(
          Directory(lockPath),
          cancellation: _waitCancellation,
          onWait: () => _progress('Waiting for active work on stage $name'),
        );
        try {
          if (!Directory(entry.path).existsSync()) continue;
          stages.add(name);
          if (!dryRun) {
            await Directory(entry.path).delete(recursive: true);
          }
        } finally {
          await _releaseLock(lock);
        }
      }
    }

    final sourcesDirectory = Directory(p.join(root, 'sources'));
    if (sourcesDirectory.existsSync()) {
      final entries = sourcesDirectory.listSync(followLinks: false);
      for (final entry in entries) {
        if (FileSystemEntity.typeSync(entry.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        final sourceKey = p.basename(entry.path);
        _progress('Checking shared source $sourceKey');
        final lock = await _acquireOperationLock(
          Directory(p.join(root, 'locks', 'source-$sourceKey')),
          cancellation: _waitCancellation,
          onWait: () => _progress('Waiting for shared source $sourceKey'),
        );
        try {
          if (!Directory(entry.path).existsSync() ||
              _sourceIsRetained(root, sourceKey)) {
            continue;
          }
          sources.add(sourceKey);
          if (!dryRun) {
            await Directory(entry.path).delete(recursive: true);
          }
        } finally {
          await _releaseLock(lock);
        }
      }
    }

    return CleanupResult(stages: stages, sources: sources);
  }

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

  /// Validates and, if needed, replaces the shared source for [releaseVersion].
  ///
  /// This operation only changes the retained shared source. It does not
  /// mutate the live cache of any installed release, so editors may continue
  /// using those release paths while the source is rebuilt.
  Future<RepairResult> repair(
    String releaseVersion, {
    required HostPlatform host,
    required Future<bool?> Function(String message) confirmExternalUse,
  }) async {
    final root = environment.dataDirectory.absolute;
    final releases = Directory(p.join(root.path, 'releases'));
    Directory? target;
    Map<String, Object?>? manifest;
    if (releases.existsSync()) {
      await for (final entity in releases.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final marker = File(p.join(entity.path, '.wren-release.json'));
        if (!marker.existsSync()) continue;
        try {
          final data = jsonDecode(await marker.readAsString());
          if (data is Map<String, Object?> &&
              data['version'] == releaseVersion &&
              data['host'] == host.catalogOs &&
              data['architecture'] == host.catalogArchitecture &&
              p.basename(entity.path).endsWith('-${_archiveVariant(host)}')) {
            target = entity;
            manifest = data;
            break;
          }
        } on Object {
          // Invalid records cannot identify the requested release.
        }
      }
    }
    final releaseDirectory = target;
    final initialManifest = manifest;
    if (releaseDirectory == null || initialManifest == null) {
      throw InstallException('Flutter $releaseVersion is not installed.');
    }
    var releaseManifest = Map<String, Object?>.from(initialManifest);
    final releaseKey = p.basename(releaseDirectory.path);
    final releaseLock = await _acquireLock(
      Directory(p.join(root.path, 'locks', 'install-$releaseKey')),
      cancellation: _waitCancellation,
      onWait: () =>
          _progress('Waiting for Flutter $releaseVersion install work'),
    );
    Directory? lifecycleLock;
    try {
      lifecycleLock = await _acquireOperationLock(
        Directory(p.join(root.path, 'locks', 'lifecycle-$releaseKey')),
        cancellation: _waitCancellation,
        onWait: () => _progress('Waiting for Flutter $releaseVersion users'),
      );
      final lifecycleManifest = jsonDecode(
        await File(p.join(releaseDirectory.path, '.wren-release.json'))
            .readAsString(),
      );
      if (lifecycleManifest is! Map<String, Object?> ||
          lifecycleManifest['state'] != 'ready') {
        throw InstallException(
          'Flutter $releaseVersion is no longer available for repair.',
        );
      }
      releaseManifest = Map<String, Object?>.from(lifecycleManifest);
      releaseManifest = await _ensureReleaseCheckoutFileRecords(
        releaseDirectory,
        root,
        releaseManifest,
      );
      final frameworkRevision = releaseManifest['frameworkRevision'];
      final engineRevision = releaseManifest['engineRevision'];
      final sourceKey = releaseManifest['sourceKey'];
      if (releaseManifest['state'] != 'ready' ||
          frameworkRevision is! String ||
          !RegExp(_engineRevisionPattern).hasMatch(frameworkRevision) ||
          engineRevision is! String ||
          !RegExp(_engineRevisionPattern).hasMatch(engineRevision) ||
          sourceKey is! String ||
          sourceKey != _sourceKey(engineRevision, host)) {
        throw InstallException(
          'Flutter $releaseVersion has invalid release or source identity.',
        );
      }

      final actualFramework = await _gitText(
        releaseDirectory.path,
        ['rev-parse', 'HEAD'],
        userMessage: 'could not read the installed Flutter framework identity',
      );
      if (actualFramework.toLowerCase() != frameworkRevision.toLowerCase()) {
        throw InstallException(
          'Flutter $releaseVersion checkout does not match its recorded '
          'framework revision.',
        );
      }
      final actualEngine = (await File(
        p.join(releaseDirectory.path, 'bin/internal/engine.version'),
      ).readAsString()).trim();
      if (actualEngine.toLowerCase() != engineRevision.toLowerCase()) {
        throw InstallException(
          'Flutter $releaseVersion checkout does not match its recorded '
          'engine revision.',
        );
      }
      _releaseCheckoutFileRecords(releaseManifest);

      final source = Directory(p.join(root.path, 'sources', sourceKey));
      final sourceLock = await _acquireOperationLock(
        Directory(p.join(root.path, 'locks', 'source-$sourceKey')),
        cancellation: _waitCancellation,
        onWait: () => _progress('Waiting for shared source $sourceKey'),
      );
      try {
        // A removal may have been waiting for the same source lock. Re-read the
        // target after acquiring it so we never publish for a removed release.
        final latestData = jsonDecode(
          await File(p.join(releaseDirectory.path, '.wren-release.json'))
              .readAsString(),
        );
        if (latestData is! Map<String, Object?> ||
            latestData['state'] != 'ready' ||
            latestData['sourceKey'] != sourceKey) {
          throw InstallException(
            'Flutter $releaseVersion is no longer available for repair.',
          );
        }
        releaseManifest = Map<String, Object?>.from(latestData);

        var sourceIsValid = true;
        try {
          await _validateSource(
            source,
            engineRevision: engineRevision,
            host: host,
          );
        } on InstallException {
          sourceIsValid = false;
        }
        if (sourceIsValid) {
          final privateFilesRepaired = await _repairPrivateReleaseFiles(
            releaseDirectory,
            source,
            releaseManifest: releaseManifest,
            releaseKey: releaseKey,
            releaseVersion: releaseVersion,
            externalUse: releaseManifest['externalUse'] == true,
            confirmExternalUse: confirmExternalUse,
          );
          final optionalArtifactOutcome = await _repairOptionalArtifacts(
            releaseDirectory,
            root,
            releaseKey: releaseKey,
            releaseVersion: releaseVersion,
            frameworkRevision: frameworkRevision,
            engineRevision: engineRevision,
            host: host,
            confirmExternalUse: confirmExternalUse,
          );
          final readiness = await _readiness(releaseDirectory, root);
          if (readiness?.needsRepair ?? true) {
            throw InstallException(
              'Flutter $releaseVersion still needs repair: '
              '${readiness?.repairReason ?? 'release validation failed'}.',
            );
          }
          return RepairResult(
            sourceKey: sourceKey,
            replaced: false,
            privateFilesRepaired: privateFilesRepaired,
            optionalArtifactsRepaired: optionalArtifactOutcome.repaired,
            optionalArtifactsValidated: optionalArtifactOutcome.validated,
          );
        }
        // An invalid retained source is rebuilt from the pinned Flutter
        // checkout below. The current source remains untouched until the new
        // source has been fully validated.

        final stagingRoot = Directory(
          p.join(root.path, 'staging', 'repair-$releaseKey-${_randomId()}'),
        );
        final checkout = Directory(p.join(stagingRoot.path, 'checkout'));
        final sourceStage = Directory(p.join(stagingRoot.path, 'source'));
        final sourceBackup = Directory(
          p.join(stagingRoot.path, 'source-backup'),
        );
        var worktreeCreated = false;
        var oldSourceMoved = false;
        var newSourcePublished = false;
        try {
          await checkout.parent.create(recursive: true);
          await _requireGit();
          final gitLock = await _acquireLock(
            Directory(p.join(root.path, 'locks', 'flutter-git')),
            cancellation: _waitCancellation,
            onWait: () => _progress('Waiting for the shared Flutter Git lock'),
          );
          try {
            await _ensureSharedRepository(root);
            await _fetchFrameworkCommit(
              root,
              frameworkRevision,
              releaseVersion,
            );
            await _runGit(root, [
              '--git-dir',
              p.join(root.path, 'flutter.git'),
              'worktree',
              'add',
              '--detach',
              checkout.path,
              frameworkRevision,
            ], userMessage: 'could not create a repair Flutter worktree');
            worktreeCreated = true;
          } finally {
            await _releaseLock(gitLock);
          }

          final actualFramework = await _gitText(checkout.path, [
            'rev-parse',
            'HEAD',
          ], userMessage: 'could not verify the repair Flutter checkout');
          if (actualFramework.toLowerCase() !=
              frameworkRevision.toLowerCase()) {
            throw const InstallException(
              'repair Flutter checkout does not match the installed release.',
            );
          }
          final actualEngine = (await File(
            p.join(checkout.path, 'bin/internal/engine.version'),
          ).readAsString()).trim();
          if (actualEngine.toLowerCase() != engineRevision.toLowerCase()) {
            throw const InstallException(
              'repair Flutter checkout has a different engine revision.',
            );
          }

          final dartVersion = releaseManifest['canonicalDartVersion'];
          final archive = releaseManifest['archive'];
          final archiveSha256 = releaseManifest['archiveSha256'];
          if (dartVersion is! String ||
              archive is! String ||
              archiveSha256 is! String) {
            throw InstallException(
              'Flutter $releaseVersion is missing validation metadata.',
            );
          }
          final release = FlutterRelease(
            version: releaseVersion,
            channel: releaseManifest['channel']! as String,
            frameworkRevision: frameworkRevision,
            dartVersion: dartVersion,
            dartSemVersion: Version.parse(dartVersion),
            archive: archive,
            archiveSha256: archiveSha256,
          );
          _progress('Rebuilding shared source for Flutter $releaseVersion');
          await _runFlutter(
            checkout,
            _precacheArguments(host),
            userMessage: 'Flutter failed to prepare a replacement source',
          );
          await _validateCheckout(
            checkout,
            release: release,
            frameworkRevision: frameworkRevision,
            engineRevision: engineRevision,
            host: host,
          );
          await _createSource(
            checkout,
            sourceStage,
            engineRevision: engineRevision,
            host: host,
          );
          await _validateSource(
            sourceStage,
            engineRevision: engineRevision,
            host: host,
          );

          if (source.existsSync() ||
              FileSystemEntity.typeSync(source.path, followLinks: false) ==
                  FileSystemEntityType.link) {
            await source.rename(sourceBackup.path);
            oldSourceMoved = true;
          }
          await sourceStage.rename(source.path);
          newSourcePublished = true;
          // Recheck the published copy before discarding the damaged backup.
          await _validateSource(
            source,
            engineRevision: engineRevision,
            host: host,
          );
          final privateFilesRepaired = await _repairPrivateReleaseFiles(
            releaseDirectory,
            source,
            releaseManifest: releaseManifest,
            releaseKey: releaseKey,
            releaseVersion: releaseVersion,
            externalUse: releaseManifest['externalUse'] == true,
            confirmExternalUse: confirmExternalUse,
          );
          final optionalArtifactOutcome = await _repairOptionalArtifacts(
            releaseDirectory,
            root,
            releaseKey: releaseKey,
            releaseVersion: releaseVersion,
            frameworkRevision: frameworkRevision,
            engineRevision: engineRevision,
            host: host,
            confirmExternalUse: confirmExternalUse,
          );
          final readiness = await _readiness(releaseDirectory, root);
          if (readiness?.needsRepair ?? true) {
            throw InstallException(
              'Flutter $releaseVersion still needs repair: '
              '${readiness?.repairReason ?? 'release validation failed'}.',
            );
          }
          if (sourceBackup.existsSync()) {
            await sourceBackup.delete(recursive: true);
          }
          return RepairResult(
            sourceKey: sourceKey,
            replaced: true,
            privateFilesRepaired: privateFilesRepaired,
            optionalArtifactsRepaired: optionalArtifactOutcome.repaired,
            optionalArtifactsValidated: optionalArtifactOutcome.validated,
          );
        } catch (error) {
          if (newSourcePublished && source.existsSync()) {
            await source.delete(recursive: true);
          }
          if (oldSourceMoved && sourceBackup.existsSync()) {
            await sourceBackup.rename(source.path);
          }
          if (error is InstallException || error is InstallCancelledException) {
            rethrow;
          }
          throw InstallException(
            'Flutter $releaseVersion source repair failed: $error',
          );
        } finally {
          if (worktreeCreated) await _discardWorktree(root, checkout.path);
          if (stagingRoot.existsSync()) {
            await stagingRoot.delete(recursive: true);
          }
        }
      } finally {
        await _releaseLock(sourceLock);
      }
    } finally {
      if (lifecycleLock != null) await _releaseLock(lifecycleLock);
      await _releaseLock(releaseLock);
    }
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
    final lifecycleLock = await _acquireOperationLock(
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

  /// Returns the fixed SDK root for [releaseVersion] and records that an
  /// external tool may continue to use its files.
  Future<String> sdkPath(
    String releaseVersion, {
    required HostPlatform host,
  }) async {
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
          // Invalid records are reported as unavailable below.
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
    final lifecycleLock = await _acquireOperationLock(
      Directory(p.join(root, 'locks', 'lifecycle-$releaseKey')),
    );
    try {
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

      final marker = File(p.join(candidate.path, '.wren-release.json'));
      final data = jsonDecode(await marker.readAsString());
      if (data is! Map<String, Object?>) {
        throw SdkLaunchException(
          status: 3,
          message:
              'Flutter $releaseVersion needs repair; run '
              '`wren repair $releaseVersion`.',
        );
      }
      if (data['externalUse'] != true) {
        await _publishManifest(candidate.path, {...data, 'externalUse': true});
      }
      return await candidate.resolveSymbolicLinks();
    } finally {
      await _releaseLock(lifecycleLock);
    }
  }

  /// Removes an installed release after Wren-launched and external users
  /// have released it. A failed deletion leaves a non-ready record for retry.
  Future<void> remove(
    String releaseVersion, {
    required HostPlatform host,
    required Future<bool?> Function(String message) confirmExternalUse,
    required Future<bool?> Function(String message) confirmSharedRepository,
    required Future<void> Function() onUnavailable,
  }) async {
    final root = environment.dataDirectory.absolute.path;
    final variant = _archiveVariant(host);
    final releases = Directory(p.join(root, 'releases'));
    Directory? target;
    Map<String, Object?>? manifest;
    if (releases.existsSync()) {
      await for (final entity in releases.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final marker = File(p.join(entity.path, '.wren-release.json'));
        if (!marker.existsSync()) continue;
        try {
          final data = jsonDecode(await marker.readAsString());
          if (data is Map<String, Object?> &&
              data['version'] == releaseVersion &&
              data['host'] == host.catalogOs &&
              data['architecture'] == host.catalogArchitecture &&
              p.basename(entity.path).endsWith('-$variant')) {
            target = entity;
            manifest = data;
            break;
          }
        } on Object {
          // Invalid release metadata cannot identify a requested release.
        }
      }
    }
    final removals = Directory(p.join(root, 'removals'));
    if (target == null && removals.existsSync()) {
      await for (final entity in removals.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          final data = jsonDecode(await entity.readAsString());
          if (data is Map<String, Object?> &&
              data['version'] == releaseVersion &&
              data['host'] == host.catalogOs &&
              data['architecture'] == host.catalogArchitecture &&
              data['releaseKey'] is String) {
            manifest = data;
            target = Directory(
              p.join(root, 'releases', data['releaseKey']! as String),
            );
            break;
          }
        } on Object {
          // Invalid removal records cannot identify a requested release.
        }
      }
    }
    if (target == null || manifest == null) {
      throw InstallException('Flutter $releaseVersion is not installed.');
    }

    final releaseKey = p.basename(target.path);
    final releaseLock = await _acquireOperationLock(
      Directory(p.join(root, 'locks', 'install-$releaseKey')),
      cancellation: _waitCancellation,
      onWait: () =>
          _progress('Waiting for Flutter $releaseVersion install work'),
    );
    try {
      final lifecycleLock = await _acquireOperationLock(
        Directory(p.join(root, 'locks', 'lifecycle-$releaseKey')),
        cancellation: _waitCancellation,
        onWait: () => _progress('Waiting for Flutter $releaseVersion users'),
      );
      try {
        final leases = Directory(p.join(root, 'leases', releaseKey));
        while (leases.existsSync() && leases.listSync().isNotEmpty) {
          _progress('Waiting for Flutter $releaseVersion to finish running');
          await _waitBriefly();
        }

        if (manifest['externalUse'] == true) {
          final confirmed = await confirmExternalUse(
            'Flutter $releaseVersion was exposed to an editor or external '
            'Close editors using it and confirm removal.',
          );
          if (confirmed != true) {
            throw InstallCancelledException(
              'removal cancelled; Flutter $releaseVersion was not changed.',
            );
          }
        }

        manifest = Map<String, Object?>.from(manifest)
          ..['state'] = 'removing'
          ..['releaseKey'] = releaseKey;
        await removals.create(recursive: true);
        await File(p.join(removals.path, '$releaseKey.json'))
            .writeAsString(jsonEncode(manifest), flush: true);
        if (target.existsSync()) {
          await _publishManifest(target.path, manifest);
        }
        await onUnavailable();

        final sourceKey = manifest['sourceKey'];
        final sourceLock = sourceKey is String
            ? await _acquireOperationLock(
                Directory(p.join(root, 'locks', 'source-$sourceKey')),
                cancellation: _waitCancellation,
                onWait: () => _progress('Waiting for shared artifact users'),
              )
            : null;
        try {
          if (sourceKey is String && !_sourceIsReferenced(root, sourceKey)) {
            final source = Directory(p.join(root, 'sources', sourceKey));
            if (source.existsSync()) await source.delete(recursive: true);
          }
          if (target.existsSync()) {
            await _discardWorktree(Directory(root), target.path);
          }
          if (Directory(target.path).existsSync()) {
            await Directory(target.path).delete(recursive: true);
          }
        } finally {
          if (sourceLock != null) await _releaseLock(sourceLock);
        }
        final journal = File(p.join(removals.path, '$releaseKey.json'));
        if (journal.existsSync()) await journal.delete();
      } finally {
        await _releaseLock(lifecycleLock);
      }
    } finally {
      await _releaseLock(releaseLock);
    }

    final remaining = releases.existsSync()
        ? releases.listSync().whereType<Directory>().where(
            (entry) =>
                File(p.join(entry.path, '.wren-release.json')).existsSync(),
          )
        : const <Directory>[];
    if (remaining.isEmpty) {
      final repository = Directory(p.join(root, 'flutter.git'));
      if (repository.existsSync()) {
        final confirmed = await confirmSharedRepository(
          'This was the final installed Flutter release. Delete the unused '
          'shared Flutter Git repository?',
        );
        if (confirmed == true) {
          final repoLock = await _acquireOperationLock(
            Directory(p.join(root, 'locks', 'flutter-git')),
            cancellation: _waitCancellation,
            onWait: () =>
                _progress('Waiting for shared Flutter Git operations'),
          );
          try {
            if (repository.existsSync()) {
              await repository.delete(recursive: true);
            }
          } finally {
            await _releaseLock(repoLock);
          }
        } else {
          _progress('Kept the shared Flutter Git repository.');
        }
      }
    }
  }

  Future<void> _waitBriefly() async {
    final cancelled = Completer<void>();
    final subscription = _waitCancellation.listen((_) {
      if (!cancelled.isCompleted) cancelled.complete();
    });
    try {
      await Future.any<void>([
        Future<void>.delayed(const Duration(milliseconds: 100)),
        cancelled.future,
      ]);
      if (cancelled.isCompleted) {
        throw InstallCancelledException(
          'cancelled while waiting for Flutter SDK users.',
        );
      }
    } finally {
      await subscription.cancel();
    }
  }

  bool _sourceIsReferenced(String root, String sourceKey) {
    final releases = Directory(p.join(root, 'releases'));
    if (!releases.existsSync()) return false;
    for (final entity in releases.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final marker = File(p.join(entity.path, '.wren-release.json'));
      if (!marker.existsSync()) continue;
      try {
        final data = jsonDecode(marker.readAsStringSync());
        if (data is Map<String, Object?> &&
            data['state'] == 'ready' &&
            data['sourceKey'] == sourceKey) {
          return true;
        }
      } on Object {
        // An unreadable record is not a provable reference.
      }
    }
    return false;
  }

  bool _sourceIsRetained(String root, String sourceKey) {
    for (final directoryName in ['releases', 'removals']) {
      final directory = Directory(p.join(root, directoryName));
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is! File && entity is! Directory) continue;
        final marker = entity is File
            ? entity
            : File(p.join(entity.path, '.wren-release.json'));
        if (entity is File && !entity.path.endsWith('.json')) continue;
        if (!marker.existsSync()) continue;
        try {
          final data = jsonDecode(marker.readAsStringSync());
          if (data is! Map<String, Object?> || data['sourceKey'] is! String) {
            return true;
          }
          if (data['sourceKey'] == sourceKey) return true;
        } on Object {
          // Unreadable records prevent proving that this source is orphaned.
          return true;
        }
      }
    }
    return false;
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
              if (reason.isEmpty &&
                  (data['privateFilesNeedRepair'] == true ||
                      data['optionalArtifactsNeedRepair'] == true)) {
                reason =
                    data['readinessReason'] as String? ??
                    'release artifact contents need repair';
              }
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
    final releaseLock = await _acquireOperationLock(
      Directory(lockPath),
      cancellation: _waitCancellation,
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
      Directory? heldSourceLock;
      try {
        _progress('Preparing Flutter ${release.version} for ${host.label}');
        await _requireGit();
        final repoLock = await _acquireOperationLock(
          Directory(p.join(root.path, 'locks', 'flutter-git')),
          cancellation: _waitCancellation,
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

        heldSourceLock = await _acquireOperationLock(
          Directory(p.join(root.path, 'locks', 'source-$resolvedSourceKey')),
          cancellation: _waitCancellation,
          onWait: () => _progress('Waiting for the shared engine source lock'),
        );
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
          await _traceOperation(
            'flutter.artifact_download_extract',
            () => _runFlutter(
              checkoutStage,
              _precacheArguments(host),
              userMessage:
                  'Flutter failed to download or extract required artifacts',
            ),
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
          await _traceOperation(
            'flutter.artifact_validation',
            () => _runFlutter(
              checkoutStage,
              _precacheArguments(host),
              userMessage:
                  'Flutter failed to validate or prepare required artifacts',
            ),
          );
          await _validateCheckout(
            checkoutStage,
            release: release,
            frameworkRevision: checkoutRevision,
            engineRevision: engineRevision,
            host: host,
          );
        }
        _validatePrivateCacheBoundary(checkoutStage, root);

        await checkoutStage.rename(releasePath);
        checkoutPublished = true;
        final worktreeRepairLock = await _acquireOperationLock(
          Directory(p.join(root.path, 'locks', 'flutter-git')),
          cancellation: _waitCancellation,
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
          'checkoutFiles': await _checkoutFileRecords(Directory(releasePath)),
          'state': 'ready',
        };
        await _publishManifest(releasePath, manifest);
        return InstallResult(
          message: 'Installed Flutter ${release.version} for ${host.label}.',
          alreadyInstalled: false,
        );
      } on InstallCancelledException {
        rethrow;
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
        if (heldSourceLock != null) {
          await _releaseLock(heldSourceLock);
        }
      }
    } finally {
      await _releaseLock(releaseLock);
    }
  }

  Stream<void> get _waitCancellation =>
      environment.waitCancellation ?? ProcessSignal.sigint.watch().map((_) {});

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
      final missingArtifact = _readinessMissingArtifact(source.path, host);
      if (missingArtifact != null) {
        throw InstallException(
          'the retained host artifact source is missing: $missingArtifact.',
        );
      }
      for (final executable in [
        _dartExecutable,
        ..._readinessHostExecutables(host),
      ]) {
        final file = File(p.join(source.path, executable));
        if ((file.statSync().mode & 0x49) == 0) {
          throw InstallException(
            'the retained host artifact source executable is not runnable: '
            '$executable.',
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

  Future<bool> _repairPrivateReleaseFiles(
    Directory release,
    Directory source, {
    required Map<String, Object?> releaseManifest,
    required String releaseKey,
    required String releaseVersion,
    required bool externalUse,
    required Future<bool?> Function(String message) confirmExternalUse,
  }) async {
    var damagedPaths = await _changedPrivateArtifactFiles(
      release,
      source,
      releaseManifest,
    );
    if (damagedPaths.isEmpty) {
      await _setPrivateRepairMarker(release, needsRepair: false);
      return false;
    }
    await _setPrivateRepairMarker(release, needsRepair: true);

    await _waitForReleaseUsers(releaseKey, releaseVersion);
    if (externalUse) {
      final confirmed = await confirmExternalUse(
        'Flutter $releaseVersion was exposed to an editor or external tool. '
        'Close editors using it and confirm private-file repair.',
      );
      if (confirmed != true) {
        throw InstallCancelledException(
          'repair cancelled; Flutter $releaseVersion was not changed.',
        );
      }
    }
    damagedPaths = await _changedPrivateArtifactFiles(
      release,
      source,
      releaseManifest,
    );
    if (damagedPaths.isEmpty) {
      await _setPrivateRepairMarker(release, needsRepair: false);
      return false;
    }

    final stage = Directory(
      p.join(
        environment.dataDirectory.absolute.path,
        'staging',
        'repair-private-$releaseKey-${_randomId()}',
      ),
    );
    final replacements = <String>[];
    final published = <String>[];
    final backups = <String>[];
    try {
      final sourceInventory = await _readSourceInventory(
        source,
        releaseManifest,
      );
      final checkoutModes = _readReleaseCheckoutModes(releaseManifest);
      final retainedContents = await _readSourceStampValues(
        source,
        releaseManifest,
      );
      for (final relativePath in damagedPaths) {
        final sourceFile = File(p.join(source.path, relativePath));
        final stagedFile = File(
          p.join(stage.path, 'replacements', relativePath),
        );
        await stagedFile.parent.create(recursive: true);
        if (sourceFile.existsSync()) {
          await sourceFile.copy(stagedFile.path);
        } else {
          final stamp = retainedContents[relativePath];
          if (stamp == null) {
            throw InstallException(
              'trusted repair source is missing $relativePath.',
            );
          }
          await stagedFile.writeAsString(stamp, flush: true);
        }
        final sourceMode = sourceFile.existsSync()
            ? sourceFile.statSync().mode & 0x1ff
            : checkoutModes[relativePath] ?? 0x1a4;
        final chmod = await Process.run('chmod', [
          sourceMode.toRadixString(8),
          stagedFile.path,
        ]);
        if (chmod.exitCode != 0) {
          throw InstallException(
            'could not preserve permissions for $relativePath.',
          );
        }
        final expectedDigest = sourceInventory[relativePath];
        final stagedDigest = await sha256.bind(stagedFile.openRead()).first;
        if (expectedDigest == null ||
            stagedDigest.toString() != expectedDigest) {
          throw InstallException(
            'could not validate staged private artifact $relativePath.',
          );
        }
        replacements.add(relativePath);
      }

      for (final relativePath in replacements) {
        final destination = p.join(release.path, relativePath);
        final stagedPath = p.join(stage.path, 'replacements', relativePath);
        final backupPath = p.join(stage.path, 'backups', relativePath);
        await Directory(p.dirname(destination)).create(recursive: true);
        final existingType = FileSystemEntity.typeSync(
          destination,
          followLinks: false,
        );
        if (existingType != FileSystemEntityType.notFound) {
          await Directory(p.dirname(backupPath)).create(recursive: true);
          await _renameEntity(destination, backupPath, existingType);
          backups.add(relativePath);
        }
        await File(stagedPath).rename(destination);
        published.add(relativePath);
      }

      final remainingDamage = await _changedPrivateArtifactFiles(
        release,
        source,
        releaseManifest,
      );
      if (remainingDamage.isNotEmpty) {
        throw InstallException(
          'private artifact validation failed after repair: '
          '${remainingDamage.first}.',
        );
      }
      await _setPrivateRepairMarker(release, needsRepair: false);
      return true;
    } catch (_) {
      for (final relativePath in published.reversed) {
        await _deletePathIfPresent(p.join(release.path, relativePath));
      }
      for (final relativePath in backups.reversed) {
        final backupPath = p.join(stage.path, 'backups', relativePath);
        if (FileSystemEntity.typeSync(backupPath, followLinks: false) !=
            FileSystemEntityType.notFound) {
          await _renameEntity(
            backupPath,
            p.join(release.path, relativePath),
            FileSystemEntity.typeSync(backupPath, followLinks: false),
          );
        }
      }
      rethrow;
    } finally {
      if (stage.existsSync()) await stage.delete(recursive: true);
    }
  }

  Future<_OptionalArtifactRepairOutcome> _repairOptionalArtifacts(
    Directory release,
    Directory root, {
    required String releaseKey,
    required String releaseVersion,
    required String frameworkRevision,
    required String engineRevision,
    required HostPlatform host,
    required Future<bool?> Function(String message) confirmExternalUse,
  }) async {
    if (host != HostPlatform.linuxX64) {
      return const _OptionalArtifactRepairOutcome();
    }
    final marker = File(p.join(release.path, '.wren-release.json'));
    final decodedManifest = jsonDecode(await marker.readAsString());
    if (decodedManifest is! Map<String, Object?>) {
      throw const InstallException('installed release metadata is invalid.');
    }
    final releaseManifest = Map<String, Object?>.from(decodedManifest);
    final externalUse = releaseManifest['externalUse'] == true;
    final groups = _linuxOptionalArtifactGroups(releaseVersion);
    final recordsValue = releaseManifest['optionalArtifactGroups'];
    if (recordsValue != null && recordsValue is! Map<String, Object?>) {
      await _setOptionalRepairMarker(release, needsRepair: true);
      throw const InstallException(
        'the optional artifact inventory is invalid.',
      );
    }
    final records = Map<String, Object?>.from(
      recordsValue as Map<String, Object?>? ?? const {},
    );
    final knownGroupIds = groups.map((group) => group.id).toSet();
    if (records.keys.any((id) => !knownGroupIds.contains(id))) {
      await _setOptionalRepairMarker(release, needsRepair: true);
      throw const InstallException(
        'the optional artifact inventory contains an unsupported group.',
      );
    }

    var repaired = false;
    var validated = false;
    var observedGroup = false;
    for (final group in groups) {
      final existingRecord = records[group.id];
      final hasStamp = group.stampFiles.any(
        (stamp) => File(p.join(release.path, 'bin/cache', stamp)).existsSync(),
      );
      final hasFiles = await _optionalGroupFiles(
        release,
        group,
      ).then((files) => files.isNotEmpty);
      if (existingRecord == null && !hasStamp && !hasFiles) {
        continue;
      }
      observedGroup = true;

      if (existingRecord != null) {
        _validateOptionalGroupRecord(
          existingRecord,
          group,
          releaseVersion: releaseVersion,
          frameworkRevision: frameworkRevision,
          engineRevision: engineRevision,
        );
        if (await _optionalGroupMatches(release, group, existingRecord)) {
          validated = true;
          continue;
        }
      }

      // Preserve the damaged state if the trusted group source is unavailable.
      await _setOptionalRepairMarker(release, needsRepair: true);
      releaseManifest
        ..['optionalArtifactsNeedRepair'] = true
        ..['readiness'] = 'needs-repair'
        ..['readinessReason'] = 'optional artifact contents need repair';
      final staged = await _stageOptionalArtifactGroup(
        release,
        root,
        group,
        releaseKey: releaseKey,
        releaseVersion: releaseVersion,
        frameworkRevision: frameworkRevision,
        engineRevision: engineRevision,
      );
      try {
        if (existingRecord != null &&
            !_sameOptionalGroupInventory(existingRecord, staged.record)) {
          throw InstallException(
            'trusted ${group.id} artifacts no longer match the retained '
            'Flutter $releaseVersion inventory.',
          );
        }

        final contentsMatch = await _optionalGroupMatches(
          release,
          group,
          staged.record,
        );
        validated = true;
        records[group.id] = staged.record;
        final updatedManifest = Map<String, Object?>.from(releaseManifest)
          ..['optionalArtifactGroups'] = records;
        if (!contentsMatch) {
          await _waitForReleaseUsers(releaseKey, releaseVersion);
          if (externalUse) {
            final confirmed = await confirmExternalUse(
              'Flutter $releaseVersion was exposed to an editor or external '
              'tool. Close editors using it and confirm optional artifact '
              'repair.',
            );
            if (confirmed != true) {
              throw InstallCancelledException(
                'repair cancelled; Flutter $releaseVersion was not changed.',
              );
            }
          }
          await _publishOptionalArtifactGroup(
            release,
            group,
            staged,
            updatedManifest,
          );
          repaired = true;
        } else {
          await _publishManifest(release.path, updatedManifest);
        }
      } finally {
        await _discardWorktree(root, staged.checkout.path);
        if (staged.stagingRoot.existsSync()) {
          await staged.stagingRoot.delete(recursive: true);
        }
      }
    }

    if (observedGroup ||
        (recordsValue is Map<String, Object?> && recordsValue.isNotEmpty)) {
      await _setOptionalRepairMarker(release, needsRepair: false);
    }
    return _OptionalArtifactRepairOutcome(
      repaired: repaired,
      validated: validated,
    );
  }

  void _validateOptionalGroupRecord(
    Object? value,
    _OptionalArtifactGroup group, {
    required String releaseVersion,
    required String frameworkRevision,
    required String engineRevision,
  }) {
    if (value is! Map<String, Object?> ||
        value['version'] != releaseVersion ||
        value['frameworkRevision'] != frameworkRevision ||
        value['engineRevision'] != engineRevision ||
        value['files'] is! List<Object?> ||
        value['stamps'] is! Map<String, Object?>) {
      throw InstallException(
        'the retained ${group.id} artifact inventory is invalid.',
      );
    }
    final files = value['files']! as List<Object?>;
    if (files.isEmpty) {
      throw InstallException(
        'the retained ${group.id} artifact inventory is empty.',
      );
    }
    for (final item in files) {
      if (item is! Map<String, Object?> ||
          item['path'] is! String ||
          item['sha256'] is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(item['sha256']! as String) ||
          item['mode'] is! int) {
        throw InstallException(
          'the retained ${group.id} artifact inventory is invalid.',
        );
      }
      final path = p.normalize(item['path']! as String);
      if (p.isAbsolute(path) ||
          p.split(path).contains('..') ||
          !_optionalGroupOwnsPath(group, path)) {
        throw InstallException(
          'the retained ${group.id} artifact inventory is invalid.',
        );
      }
    }
    final stamps = value['stamps']! as Map<String, Object?>;
    if (stamps.isEmpty ||
        stamps.keys.any(
          (stamp) =>
              !group.stampFiles.contains(stamp) || stamps[stamp] is! String,
        )) {
      throw InstallException(
        'the retained ${group.id} artifact stamps are invalid.',
      );
    }
  }

  Future<bool> _optionalGroupMatches(
    Directory release,
    _OptionalArtifactGroup group,
    Object? record,
  ) async {
    if (record is! Map<String, Object?>) return false;
    final expectedFiles = record['files'];
    final expectedStamps = record['stamps'];
    if (expectedFiles is! List<Object?> ||
        expectedStamps is! Map<String, Object?>) {
      return false;
    }
    final expectedPaths = <String>{};
    for (final item in expectedFiles) {
      if (item is! Map<String, Object?> ||
          item['path'] is! String ||
          item['sha256'] is! String ||
          item['mode'] is! int) {
        return false;
      }
      final relative = item['path']! as String;
      expectedPaths.add(relative);
      final file = File(p.join(release.path, relative));
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return false;
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != item['sha256'] ||
          (file.statSync().mode & 0x1ff) != item['mode']) {
        return false;
      }
    }
    if (expectedPaths.isEmpty) return false;
    final actualFiles = await _optionalGroupFiles(release, group);
    if (actualFiles.map((entry) => entry['path']! as String).toSet().length !=
            expectedPaths.length ||
        !actualFiles.every(
          (entry) => expectedPaths.contains(entry['path']! as String),
        )) {
      return false;
    }
    if (expectedStamps.values.any((value) => value is! String)) {
      return false;
    }
    return true;
  }

  Future<List<Map<String, Object?>>> _optionalGroupFiles(
    Directory release,
    _OptionalArtifactGroup group,
  ) async {
    final cache = Directory(p.join(release.path, 'bin/cache'));
    if (!cache.existsSync()) return const [];
    final files = <Map<String, Object?>>[];
    await for (final entity in cache.list(
      recursive: true,
      followLinks: false,
    )) {
      if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final relative = p.relative(entity.path, from: release.path);
      if (!_optionalGroupOwnsPath(group, relative)) continue;
      final file = File(entity.path);
      final digest = await sha256.bind(file.openRead()).first;
      files.add({
        'path': relative,
        'sha256': digest.toString(),
        'mode': file.statSync().mode & 0x1ff,
      });
    }
    files.sort(
      (left, right) =>
          (left['path']! as String).compareTo(right['path']! as String),
    );
    return files;
  }

  bool _optionalGroupOwnsPath(
    _OptionalArtifactGroup group,
    String relativePath,
  ) => group.pathPrefixes.any(relativePath.startsWith);

  bool _sameOptionalGroupInventory(Object? left, Object? right) {
    if (left is! Map<String, Object?> || right is! Map<String, Object?>) {
      return false;
    }
    return jsonEncode(left['files']) == jsonEncode(right['files']) &&
        jsonEncode(left['stamps']) == jsonEncode(right['stamps']);
  }

  Future<_StagedOptionalArtifactGroup> _stageOptionalArtifactGroup(
    Directory release,
    Directory root,
    _OptionalArtifactGroup group, {
    required String releaseKey,
    required String releaseVersion,
    required String frameworkRevision,
    required String engineRevision,
  }) async {
    final stagingRoot = Directory(
      p.join(
        root.path,
        'staging',
        'repair-optional-$releaseKey-${group.id}-${_randomId()}',
      ),
    );
    final checkout = Directory(p.join(stagingRoot.path, 'checkout'));
    var worktreeCreated = false;
    try {
      await stagingRoot.create(recursive: true);
      await _requireGit();
      final gitLock = await _acquireOperationLock(
        Directory(p.join(root.path, 'locks', 'flutter-git')),
        cancellation: _waitCancellation,
        onWait: () => _progress('Waiting for the shared Flutter Git lock'),
      );
      try {
        await _ensureSharedRepository(root);
        await _fetchFrameworkCommit(root, frameworkRevision, releaseVersion);
        await _runGit(root, [
          '--git-dir',
          p.join(root.path, 'flutter.git'),
          'worktree',
          'add',
          '--detach',
          checkout.path,
          frameworkRevision,
        ], userMessage: 'could not create an optional repair worktree');
        worktreeCreated = true;
      } finally {
        await _releaseLock(gitLock);
      }

      final actualFramework = await _gitText(checkout.path, [
        'rev-parse',
        'HEAD',
      ], userMessage: 'could not verify the optional repair checkout');
      if (actualFramework.toLowerCase() != frameworkRevision.toLowerCase()) {
        throw const InstallException(
          'optional repair checkout does not match the installed release.',
        );
      }
      final actualEngine = (await File(
        p.join(checkout.path, 'bin/internal/engine.version'),
      ).readAsString()).trim();
      if (actualEngine.toLowerCase() != engineRevision.toLowerCase()) {
        throw const InstallException(
          'optional repair checkout has a different engine revision.',
        );
      }

      final liveCache = Directory(p.join(release.path, 'bin/cache'));
      final stagedCache = Directory(p.join(checkout.path, 'bin/cache'));
      if (stagedCache.existsSync()) {
        await stagedCache.delete(recursive: true);
      }
      await _copyTree(liveCache, stagedCache);
      await _clearOptionalGroupPaths(checkout, group);
      for (final stamp in group.stampFiles) {
        final file = File(p.join(stagedCache.path, stamp));
        if (file.existsSync()) await file.delete();
      }

      _progress('Validating optional ${group.id} artifacts');
      await _runFlutter(
        checkout,
        group.arguments,
        userMessage:
            'Flutter failed to validate optional ${group.id} artifacts',
      );

      final files = await _optionalGroupFiles(checkout, group);
      if (files.isEmpty) {
        throw InstallException(
          'Flutter did not provide a trusted ${group.id} artifact inventory.',
        );
      }
      final stamps = <String, Object?>{};
      for (final stamp in group.stampFiles) {
        final file = File(p.join(checkout.path, 'bin/cache', stamp));
        if (file.existsSync()) stamps[stamp] = await file.readAsString();
      }
      if (stamps.isEmpty) {
        throw InstallException(
          'Flutter did not provide a trusted ${group.id} artifact stamp.',
        );
      }
      return _StagedOptionalArtifactGroup(
        stagingRoot: stagingRoot,
        checkout: checkout,
        record: {
          'version': releaseVersion,
          'frameworkRevision': frameworkRevision,
          'engineRevision': engineRevision,
          'files': files,
          'stamps': stamps,
        },
      );
    } catch (error) {
      if (worktreeCreated) await _discardWorktree(root, checkout.path);
      if (stagingRoot.existsSync()) {
        await stagingRoot.delete(recursive: true);
      }
      if (error is InstallException || error is InstallCancelledException) {
        rethrow;
      }
      throw InstallException(
        'Flutter $releaseVersion optional ${group.id} repair failed: $error',
      );
    }
  }

  Future<void> _clearOptionalGroupPaths(
    Directory checkout,
    _OptionalArtifactGroup group,
  ) async {
    for (final prefix in group.pathPrefixes) {
      final absolutePrefix = p.join(checkout.path, prefix);
      final relativePrefix = p.relative(absolutePrefix, from: checkout.path);
      final prefixName = p.basename(relativePrefix);
      if (prefixName.endsWith('-')) {
        final parent = Directory(p.dirname(absolutePrefix));
        if (!parent.existsSync()) continue;
        await for (final entity in parent.list(followLinks: false)) {
          if (p.basename(entity.path).startsWith(prefixName) &&
              FileSystemEntity.typeSync(entity.path, followLinks: false) ==
                  FileSystemEntityType.directory) {
            await Directory(entity.path).delete(recursive: true);
          }
        }
      } else {
        final type = FileSystemEntity.typeSync(
          absolutePrefix,
          followLinks: false,
        );
        if (type == FileSystemEntityType.directory) {
          await Directory(absolutePrefix).delete(recursive: true);
        } else if (type == FileSystemEntityType.file) {
          await File(absolutePrefix).delete();
        }
      }
    }
  }

  Future<void> _publishOptionalArtifactGroup(
    Directory release,
    _OptionalArtifactGroup group,
    _StagedOptionalArtifactGroup staged,
    Map<String, Object?> updatedManifest,
  ) async {
    final replacementRoot = Directory(
      p.join(staged.stagingRoot.path, 'replacement'),
    );
    final backupRoot = Directory(p.join(staged.stagingRoot.path, 'backup'));
    final expectedFiles = staged.record['files']! as List<Object?>;
    final expectedPaths = <String>{};
    final replacedPaths = <String>[];
    final backedUpPaths = <String>[];
    final changedPaths = (await _optionalGroupFiles(
      release,
      group,
    )).map((entry) => entry['path']! as String).toSet();
    try {
      for (final item in expectedFiles) {
        final record = item! as Map<String, Object?>;
        final relative = record['path']! as String;
        expectedPaths.add(relative);
        final source = File(p.join(staged.checkout.path, relative));
        final replacement = File(p.join(replacementRoot.path, relative));
        await replacement.parent.create(recursive: true);
        await source.copy(replacement.path);
        final chmod = await Process.run('chmod', [
          (record['mode']! as int).toRadixString(8),
          replacement.path,
        ]);
        if (chmod.exitCode != 0) {
          throw InstallException(
            'could not preserve permissions for optional artifact $relative.',
          );
        }
        final digest = await sha256.bind(replacement.openRead()).first;
        if (digest.toString() != record['sha256']) {
          throw InstallException(
            'could not validate staged optional artifact $relative.',
          );
        }
      }

      final stampRecords = staged.record['stamps']! as Map<String, Object?>;
      for (final entry in stampRecords.entries) {
        final replacement = File(
          p.join(replacementRoot.path, 'bin/cache', entry.key),
        );
        await replacement.parent.create(recursive: true);
        await replacement.writeAsString(entry.value! as String, flush: true);
      }

      for (final relative in changedPaths) {
        final destination = p.join(release.path, relative);
        final backup = p.join(backupRoot.path, relative);
        final type = FileSystemEntity.typeSync(destination, followLinks: false);
        if (type != FileSystemEntityType.notFound) {
          await Directory(p.dirname(backup)).create(recursive: true);
          await _renameEntity(destination, backup, type);
          backedUpPaths.add(relative);
        }
        if (!expectedPaths.contains(relative)) continue;
        final stagedFile = File(p.join(replacementRoot.path, relative));
        await Directory(p.dirname(destination)).create(recursive: true);
        await stagedFile.rename(destination);
        replacedPaths.add(relative);
      }
      for (final relative in expectedPaths.difference(changedPaths)) {
        final destination = p.join(release.path, relative);
        final stagedFile = File(p.join(replacementRoot.path, relative));
        await Directory(p.dirname(destination)).create(recursive: true);
        await stagedFile.rename(destination);
        replacedPaths.add(relative);
      }

      for (final entry in stampRecords.entries) {
        final destination = p.join(release.path, 'bin/cache', entry.key);
        final backup = p.join(backupRoot.path, 'bin/cache', entry.key);
        final type = FileSystemEntity.typeSync(destination, followLinks: false);
        if (type != FileSystemEntityType.notFound) {
          await Directory(p.dirname(backup)).create(recursive: true);
          await _renameEntity(destination, backup, type);
          backedUpPaths.add(p.relative(destination, from: release.path));
        }
        final stagedStamp = File(
          p.join(replacementRoot.path, 'bin/cache', entry.key),
        );
        await Directory(p.dirname(destination)).create(recursive: true);
        await stagedStamp.rename(destination);
        replacedPaths.add(p.relative(destination, from: release.path));
      }
      await _publishManifest(release.path, updatedManifest);
    } catch (_) {
      for (final relative in replacedPaths.reversed) {
        await _deletePathIfPresent(p.join(release.path, relative));
      }
      for (final relative in backedUpPaths.reversed) {
        final backup = p.join(backupRoot.path, relative);
        if (FileSystemEntity.typeSync(backup, followLinks: false) !=
            FileSystemEntityType.notFound) {
          await _renameEntity(
            backup,
            p.join(release.path, relative),
            FileSystemEntity.typeSync(backup, followLinks: false),
          );
        }
      }
      rethrow;
    }
  }

  Future<void> _setOptionalRepairMarker(
    Directory release, {
    required bool needsRepair,
  }) async {
    final marker = File(p.join(release.path, '.wren-release.json'));
    final decoded = jsonDecode(await marker.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const InstallException('installed release metadata is invalid.');
    }
    final updated = Map<String, Object?>.from(decoded);
    if (needsRepair) {
      updated['optionalArtifactsNeedRepair'] = true;
      updated['readiness'] = 'needs-repair';
      updated['readinessReason'] = 'optional artifact contents need repair';
    } else {
      updated.remove('optionalArtifactsNeedRepair');
      if (updated['readinessReason'] ==
          'optional artifact contents need repair') {
        updated
          ..remove('readiness')
          ..remove('readinessReason');
      }
    }
    if (jsonEncode(updated) != jsonEncode(decoded)) {
      await _publishManifest(release.path, updated);
    }
  }

  Future<void> _setPrivateRepairMarker(
    Directory release, {
    required bool needsRepair,
  }) async {
    final marker = File(p.join(release.path, '.wren-release.json'));
    final decoded = jsonDecode(await marker.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const InstallException('installed release metadata is invalid.');
    }
    final updated = Map<String, Object?>.from(decoded);
    if (needsRepair) {
      updated['privateFilesNeedRepair'] = true;
      updated['readiness'] = 'needs-repair';
      updated['readinessReason'] =
          'release-private artifact contents need repair';
    } else {
      updated.remove('privateFilesNeedRepair');
      if (updated['readinessReason'] ==
          'release-private artifact contents need repair') {
        updated
          ..remove('readiness')
          ..remove('readinessReason');
      }
    }
    if (jsonEncode(updated) != jsonEncode(decoded)) {
      await _publishManifest(release.path, updated);
    }
  }

  Future<List<String>> _changedPrivateArtifactFiles(
    Directory release,
    Directory source,
    Map<String, Object?> releaseManifest,
  ) async {
    final expected = await _readSourceInventory(source, releaseManifest);
    final checkoutModes = _readReleaseCheckoutModes(releaseManifest);
    final changed = <String>[];
    for (final entry in expected.entries) {
      final path = entry.key;
      final sourceFile = File(p.join(source.path, path));
      final releasePath = p.join(release.path, path);
      if (FileSystemEntity.typeSync(releasePath, followLinks: false) !=
          FileSystemEntityType.file) {
        changed.add(path);
        continue;
      }
      final releaseFile = File(releasePath);
      final digest = await sha256.bind(releaseFile.openRead()).first;
      final actualMode = releaseFile.statSync().mode & 0x1ff;
      final expectedMode = sourceFile.existsSync()
          ? sourceFile.statSync().mode & 0x1ff
          : checkoutModes[path];
      if (digest.toString() != entry.value ||
          (expectedMode != null && actualMode != expectedMode)) {
        changed.add(path);
      }
    }
    return changed;
  }

  Future<Map<String, String>> _readSourceInventory(
    Directory source,
    Map<String, Object?> releaseManifest,
  ) async {
    final marker = File(p.join(source.path, '.wren-source.json'));
    final data = jsonDecode(await marker.readAsString());
    if (data is! Map<String, Object?> || data['inventory'] is! List<Object?>) {
      throw const InstallException(
        'the retained host artifact source has no trusted file inventory.',
      );
    }
    final inventory = <String, String>{};
    for (final value in data['inventory']! as List<Object?>) {
      if (value is! Map<String, Object?> ||
          value['path'] is! String ||
          value['sha256'] is! String) {
        throw const InstallException(
          'the retained host artifact source inventory is invalid.',
        );
      }
      final path = p.normalize(value['path']! as String);
      if (p.isAbsolute(path) || p.split(path).contains('..')) {
        throw const InstallException(
          'the retained host artifact source inventory is invalid.',
        );
      }
      inventory[path] = value['sha256']! as String;
    }
    for (final record in _releaseCheckoutFileRecords(releaseManifest)) {
      inventory[record['path']! as String] = record['sha256']! as String;
    }
    final stamps = data['stamps'];
    if (stamps is! Map<String, Object?>) {
      throw const InstallException(
        'the retained host artifact source has no trusted cache stamps.',
      );
    }
    for (final entry in stamps.entries) {
      if (entry.value is! String) {
        throw const InstallException(
          'the retained host artifact source cache stamps are invalid.',
        );
      }
      final path = p.join('bin/cache', entry.key);
      inventory[path] = sha256
          .convert(utf8.encode(entry.value! as String))
          .toString();
    }
    return inventory;
  }

  Future<Map<String, String>> _readSourceStampValues(
    Directory source,
    Map<String, Object?> releaseManifest,
  ) async {
    final data = jsonDecode(
      await File(p.join(source.path, '.wren-source.json')).readAsString(),
    );
    if (data is! Map<String, Object?> ||
        data['stamps'] is! Map<String, Object?>) {
      throw const InstallException(
        'the retained host artifact source has no trusted cache stamps.',
      );
    }
    final values = <String, String>{
      for (final entry in (data['stamps']! as Map<String, Object?>).entries)
        if (entry.value is String)
          p.join('bin/cache', entry.key): entry.value! as String,
    };
    for (final record in _releaseCheckoutFileRecords(releaseManifest)) {
      values[record['path']! as String] = utf8.decode(
        base64.decode(record['content']! as String),
      );
    }
    return values;
  }

  Map<String, int> _readReleaseCheckoutModes(
    Map<String, Object?> releaseManifest,
  ) {
    return {
      for (final value in _releaseCheckoutFileRecords(releaseManifest))
        if (value['path'] is String && value['mode'] is int)
          value['path']! as String: value['mode']! as int,
    };
  }

  List<Map<String, Object?>> _releaseCheckoutFileRecords(
    Map<String, Object?> releaseManifest,
  ) {
    final records = releaseManifest['checkoutFiles'];
    if (records == null) return const [];
    _validateCheckoutFileRecords(records);
    return (records as List<Object?>).cast<Map<String, Object?>>();
  }

  Future<Map<String, Object?>> _ensureReleaseCheckoutFileRecords(
    Directory release,
    Directory root,
    Map<String, Object?> releaseManifest,
  ) async {
    if (releaseManifest['checkoutFiles'] != null) return releaseManifest;
    final revision = releaseManifest['frameworkRevision'];
    if (revision is! String ||
        !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(revision)) {
      throw const InstallException(
        'the installed Flutter framework identity is invalid.',
      );
    }
    final gitDirectory = p.join(root.path, 'flutter.git');
    final blob = await Process.run('git', [
      '--git-dir',
      gitDirectory,
      'show',
      '$revision:bin/flutter',
    ], workingDirectory: release.path);
    if (blob.exitCode != 0 || blob.stdout is! String) {
      throw InstallException(
        'could not load the trusted Flutter launcher from revision $revision.',
      );
    }
    final treeEntry = await Process.run('git', [
      '--git-dir',
      gitDirectory,
      'ls-tree',
      revision,
      '--',
      'bin/flutter',
    ], workingDirectory: release.path);
    final fields = '${treeEntry.stdout}'.trim().split(RegExp(r'\s+'));
    if (treeEntry.exitCode != 0 ||
        fields.length < 2 ||
        !{'100644', '100755'}.contains(fields.first)) {
      throw InstallException(
        'could not read the trusted Flutter launcher mode at revision '
        '$revision.',
      );
    }
    final bytes = utf8.encode(blob.stdout! as String);
    final updated = Map<String, Object?>.from(releaseManifest)
      ..['checkoutFiles'] = [
        {
          'path': 'bin/flutter',
          'sha256': sha256.convert(bytes).toString(),
          'mode': fields.first == '100755' ? 0x1ed : 0x1a4,
          'content': base64.encode(bytes),
        },
      ];
    await _publishManifest(release.path, updated);
    return updated;
  }

  Future<List<Map<String, Object?>>> _checkoutFileRecords(
    Directory checkout,
  ) async {
    const path = 'bin/flutter';
    final file = File(p.join(checkout.path, path));
    final bytes = await file.readAsBytes();
    return [
      {
        'path': path,
        'sha256': sha256.convert(bytes).toString(),
        'mode': file.statSync().mode & 0x1ff,
        'content': base64.encode(bytes),
      },
    ];
  }

  void _validateCheckoutFileRecords(Object? value) {
    if (value is! List<Object?> || value.isEmpty) {
      throw const InstallException(
        'the retained Flutter checkout inventory is missing.',
      );
    }
    for (final entry in value) {
      if (entry is! Map<String, Object?> ||
          entry['path'] != 'bin/flutter' ||
          entry['sha256'] is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(entry['sha256']! as String) ||
          entry['mode'] is! int ||
          entry['content'] is! String) {
        throw const InstallException(
          'the retained Flutter checkout inventory is invalid.',
        );
      }
      final bytes = base64.decode(entry['content']! as String);
      if (sha256.convert(bytes).toString() != entry['sha256']) {
        throw const InstallException(
          'the retained Flutter checkout inventory is damaged.',
        );
      }
    }
  }

  Future<void> _waitForReleaseUsers(
    String releaseKey,
    String releaseVersion,
  ) async {
    final leases = Directory(
      p.join(environment.dataDirectory.absolute.path, 'leases', releaseKey),
    );
    while (leases.existsSync() && leases.listSync().isNotEmpty) {
      _progress('Waiting for Flutter $releaseVersion to finish running');
      await _waitBriefly();
    }
  }

  Future<void> _renameEntity(
    String source,
    String destination,
    FileSystemEntityType type,
  ) async {
    switch (type) {
      case FileSystemEntityType.file:
        await File(source).rename(destination);
      case FileSystemEntityType.directory:
        await Directory(source).rename(destination);
      case FileSystemEntityType.link:
        await Link(source).rename(destination);
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw FileSystemException(
          'cannot move unsupported repair path',
          source,
        );
    }
  }

  Future<void> _deletePathIfPresent(String path) async {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        await File(path).delete();
      case FileSystemEntityType.directory:
        await Directory(path).delete(recursive: true);
      case FileSystemEntityType.link:
        await Link(path).delete();
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        break;
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
    final lock = await _acquireOperationLock(
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

class _OptionalArtifactRepairOutcome {
  const new({this.repaired = false, this.validated = false});

  final bool repaired;
  final bool validated;
}

class _StagedOptionalArtifactGroup {
  const new({
    required this.stagingRoot,
    required this.checkout,
    required this.record,
  });

  final Directory stagingRoot;
  final Directory checkout;
  final Map<String, Object?> record;
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
  Stream<void>? cancellation,
}) async {
  await lock.parent.create(recursive: true);
  var reportedWait = false;
  final cancelled = Completer<void>();
  StreamSubscription<void>? cancellationSubscription;
  try {
    for (var attempt = 0; attempt < 36000; attempt++) {
      try {
        await lock.create(recursive: true);
        final owner = File(p.join(lock.path, 'owner'));
        await owner.create(exclusive: true);
        await owner.writeAsString('$pid\n', flush: true);
        return lock;
      } on FileSystemException {
        if (!lock.existsSync()) continue;
        if (await _isStaleLock(lock)) {
          try {
            final staleLock = Directory('${lock.path}.stale-${_randomId()}');
            await lock.rename(staleLock.path);
            await staleLock.delete(recursive: true);
          } on FileSystemException {
            // Another waiter may have replaced or removed it first.
          }
          continue;
        }
        if (!reportedWait) {
          reportedWait = true;
          onWait?.call();
          if (cancellation != null) {
            cancellationSubscription = cancellation.listen((_) {
              if (!cancelled.isCompleted) cancelled.complete();
            });
          }
        }
        if (cancellationSubscription == null) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        } else {
          await Future.any<void>([
            Future<void>.delayed(const Duration(milliseconds: 100)),
            cancelled.future,
          ]);
          if (cancelled.isCompleted) {
            throw InstallCancelledException(
              'cancelled while waiting for Wren install lock ${lock.path}.',
            );
          }
        }
      }
    }
    throw InstallException(
      'timed out waiting for Wren install lock ${lock.path}.',
    );
  } finally {
    await cancellationSubscription?.cancel();
  }
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
  if (!lock.existsSync()) return;
  final releasedLock = Directory('${lock.path}.released-${_randomId()}');
  try {
    await lock.rename(releasedLock.path);
  } on FileSystemException {
    if (lock.existsSync()) rethrow;
    // A stale-lock recovery may have moved it already.
    return;
  }
  try {
    await releasedLock.delete(recursive: true);
  } on FileSystemException {
    // The active lock is already gone; only an orphaned tombstone remains.
  }
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

String? _stageOperationLockName(String stageName) {
  if (stageName == 'flutter-repo') return 'flutter-git';
  if (stageName.startsWith('install-') &&
      stageName.length > 'install-'.length) {
    return 'install-${stageName.substring('install-'.length)}';
  }
  final repairMatch = RegExp(r'^repair-(?:private-)?(.+)-[a-fA-F0-9]{32}$')
      .firstMatch(stageName);
  if (repairMatch == null) return null;
  return 'install-${repairMatch.group(1)}';
}

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
