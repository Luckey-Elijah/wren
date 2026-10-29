import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:wren/src/installer.dart';
import 'package:wren/src/tracing.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

export 'src/installer.dart'
    show
        CleanupResult,
        InstallCancelledException,
        InstallEnvironment,
        InstallException,
        InstallResult,
        InstalledRelease,
        RepairResult;

/// Testable SDK launch boundary used by [WrenContext].
typedef SdkLauncher = Future<int> Function({
  required String release,
  required String executable,
  required List<String> arguments,
});

/// Confirms a change that may alter the Dart language version.
typedef WrenConfirmation = Future<bool?> Function(String message);

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
  /// Creates shared configuration and services for one CLI invocation.
  new({
    StringSink? stdoutSink,
    StringSink? stderrSink,
    this.catalogJson,
    this.hostOverride,
    this.configuredInstallEnvironment,
    this.flutterReleaseOverride,
    this.globalFallbackOverride,
    this.confirmation,
    this.projectDirectory,
    this.installedReleasesOverride,
    this.sdkLauncher,
    this.wrenExecutable,
    this.stdinStream,
    DateTime? traceStartedAt,
    Stopwatch? traceElapsed,
  }) : _stdoutSink = stdoutSink ?? io.stdout,
       _stderrSink = stderrSink ?? io.stderr,
       // These values are internal invocation state, not public settings.
       // Keep the public constructor names while assigning private fields.
       // ignore: prefer_initializing_formals
       _traceStartedAt = traceStartedAt,
       // Keep this invocation timer private to the context implementation.
       // ignore: prefer_initializing_formals
       _traceElapsed = traceElapsed;

  final StringSink _stdoutSink;
  final StringSink _stderrSink;
  final DateTime? _traceStartedAt;
  final Stopwatch? _traceElapsed;

  /// Optional serialized catalog for local fixture runs.
  final String? catalogJson;

  /// Optional host override for local fixture runs.
  final HostPlatform? hostOverride;

  /// Optional installation configuration for local fixture runs.
  final InstallEnvironment? configuredInstallEnvironment;

  /// Optional environment override for selecting a Flutter release.
  final String? flutterReleaseOverride;

  /// Optional global fallback override for local CLI fixture runs.
  String? globalFallbackOverride;

  /// Optional confirmation handler. A null result means confirmation is
  /// unavailable, such as when the process is running without a terminal.
  final WrenConfirmation? confirmation;

  /// Optional current directory for local CLI fixture runs.
  final io.Directory? projectDirectory;

  /// Optional installed-release list for local CLI fixture runs.
  final List<InstalledRelease>? installedReleasesOverride;

  /// Optional SDK process launcher for local CLI fixture runs.
  final SdkLauncher? sdkLauncher;

  /// Executable used by generated PATH shims.
  ///
  /// Production setup uses the running Wren executable. The override allows
  /// CLI tests to run generated shims against a controlled child process.
  final String? wrenExecutable;

  /// Input forwarded to SDK processes; defaults to the current process stdin.
  final Stream<List<int>>? stdinStream;

  List<String> _sdkArguments = const [];
  TraceSession? _trace;

  /// Runs [operation] under a named trace span when tracing is enabled.
  Future<T> traceOperation<T>(String name, Future<T> Function() operation) =>
      _trace?.span(name, operation) ?? operation();

  /// Byte-capable stdout sink when the caller supplied one.
  io.IOSink? get stdoutByteSink =>
      _stdoutSink is io.IOSink ? _stdoutSink : null;

  /// Byte-capable stderr sink when the caller supplied one.
  io.IOSink? get stderrByteSink =>
      _stderrSink is io.IOSink ? _stderrSink : null;

  /// Minimum supported bundled Dart version.
  String get minimumDartVersion => _minimumDartVersion;

  /// Destination for command output.
  StringSink get stdoutSink => _stdoutSink;

  /// Destination for diagnostics and progress messages.
  StringSink get stderrSink => _stderrSink;

  /// Host selected for this invocation, if supported.
  HostPlatform? get host => hostOverride ?? HostPlatform.current;

  /// Installation paths and repository settings for this invocation.
  InstallEnvironment get installEnvironment =>
      configuredInstallEnvironment ?? InstallEnvironment();

  /// Installer configured for this invocation.
  FlutterInstaller get installer => FlutterInstaller(
    installEnvironment,
    onProgress: (message) => stderrSink.writeln(message),
    traceSpan: _trace?.span,
  );

  /// Loads eligible Flutter releases for [targetHost].
  Future<ReleaseCatalog> loadReleaseCatalog(HostPlatform targetHost) =>
      traceOperation(
        'catalog.load',
        () => catalogJson == null
            ? ReleaseCatalog.fetch(targetHost.catalogUri, host: targetHost)
            : Future.value(
                ReleaseCatalog.parse(catalogJson!, host: targetHost),
              ),
      );

  /// Global fallback configured by `set -g`, if any.
  Future<String?> get globalFallback =>
      traceOperation('config.read_global_fallback', () async {
        if (globalFallbackOverride != null) return globalFallbackOverride;
        final config = io.File(
          '${installEnvironment.dataDirectory.absolute.path}/config.json',
        );
        if (!config.existsSync()) return null;
        try {
          final decoded = jsonDecode(config.readAsStringSync());
          if (decoded is Map<String, Object?> &&
              decoded['globalFallback'] is String) {
            return (decoded['globalFallback']! as String).trim();
          }
        } on Object {
          // An unreadable preference is treated as unset; doctor diagnoses it.
        }
        return null;
      });

  /// Prepares a global fallback update without writing the config file.
  _PreparedGlobalFallback _prepareGlobalFallback(String release) {
    final config = io.File(
      '${installEnvironment.dataDirectory.absolute.path}/config.json',
    );
    var values = <String, Object?>{};
    if (config.existsSync()) {
      final decoded = jsonDecode(config.readAsStringSync());
      if (decoded is! Map<String, Object?>) {
        throw const InstallException(
          'Wren config.json must contain an object.',
        );
      }
      values = Map<String, Object?>.from(decoded);
    }
    values['globalFallback'] = release;
    return _PreparedGlobalFallback(
      config: config,
      release: release,
      contents: '${const JsonEncoder.withIndent('  ').convert(values)}\n',
    );
  }

  /// Persists a prepared global fallback update.
  Future<void> _setGlobalFallback(_PreparedGlobalFallback update) async {
    await traceOperation('config.write_global_fallback', () async {
      update.config.parent.createSync(recursive: true);
      _replaceFileAtomically(
        update.config,
        update.contents,
        temporarySuffix: '.tmp',
      );
      globalFallbackOverride = update.release;
    });
  }

  Future<void> _clearGlobalFallback(String release) async {
    await traceOperation('config.clear_global_fallback', () async {
      if (globalFallbackOverride == release) globalFallbackOverride = null;
      final config = io.File(
        '${installEnvironment.dataDirectory.absolute.path}/config.json',
      );
      if (!config.existsSync()) return;
      final decoded = jsonDecode(config.readAsStringSync());
      if (decoded is! Map<String, Object?> ||
          decoded['globalFallback'] != release) {
        return;
      }
      final values = Map<String, Object?>.from(decoded)
        ..remove('globalFallback');
      if (values.isEmpty) {
        await config.delete();
      } else {
        _replaceFileAtomically(
          config,
          '${const JsonEncoder.withIndent('  ').convert(values)}\n',
          temporarySuffix: '.tmp',
        );
      }
    });
  }

  /// Asks the user to confirm a language-version change.
  Future<bool?> confirm(String message) async {
    if (confirmation != null) return await confirmation!(message);
    if (!io.stdin.hasTerminal) return null;
    stderrSink
      ..writeln(message)
      ..write('Continue? [y/N] ');
    final answer = io.stdin.readLineSync();
    return answer != null &&
        const {'y', 'yes'}.contains(answer.trim().toLowerCase());
  }

  /// Selects from only the current directory's pubspec and the global fallback.
  Future<String?> selectProjectRelease(
    HostPlatform host,
    List<InstalledRelease> installed,
  ) => traceOperation(
    'release.select',
    () => _selectProjectRelease(host, installed),
  );

  Future<String?> _selectProjectRelease(
    HostPlatform host,
    List<InstalledRelease> installed,
  ) async {
    final project = projectDirectory ?? io.Directory.current;
    final pubspec = io.File('${project.path}/pubspec.yaml');
    if (pubspec.existsSync()) {
      try {
        final yaml = loadYaml(pubspec.readAsStringSync());
        final environment = yaml is YamlMap ? yaml['environment'] : null;
        final flutterText = environment is YamlMap
            ? environment['flutter']
            : null;
        final dartText = environment is YamlMap ? environment['sdk'] : null;
        if (flutterText is String && dartText is String) {
          final flutterConstraint = VersionConstraint.parse(flutterText);
          final dartConstraint = VersionConstraint.parse(dartText);
          final matching =
              installed.where((release) {
                if (release.host != host.catalogOs ||
                    release.dartVersion == null) {
                  return false;
                }
                try {
                  final flutterVersion = Version.parse(release.version);
                  final dartVersion = Version.parse(release.dartVersion!);
                  final constraintsMatch =
                      flutterConstraint.allows(flutterVersion) &&
                      dartConstraint.allows(dartVersion);
                  final betaExplicitlyAllowed =
                      release.channel != 'beta' ||
                      (_explicitlyAllowsPrerelease(
                            flutterText,
                            flutterVersion,
                          ) &&
                          _explicitlyAllowsPrerelease(dartText, dartVersion));
                  return constraintsMatch && betaExplicitlyAllowed;
                } on FormatException {
                  return false;
                }
              }).toList()..sort(
                (left, right) =>
                    Version.parse(right.version)
                        .compareTo(Version.parse(left.version)),
              );
          if (matching.isNotEmpty) return matching.first.version;
        }
      } on Object {
        // Missing, malformed, or invalid constraints leave fallback eligible.
      }
    }
    final fallback = await globalFallback;
    return fallback == null || fallback.isEmpty ? null : fallback;
  }

  /// Starts the selected SDK command.
  Future<int> launchSdk(
    String release, {
    required HostPlatform host,
    required String executable,
    required List<String> arguments,
  }) => traceOperation(
    'sdk.child_process',
    () =>
        sdkLauncher?.call(
          release: release,
          executable: executable,
          arguments: arguments,
        ) ??
        installer.launch(
          release,
          host: host,
          executable: executable,
          arguments: arguments,
          stdoutSink: stdoutSink,
          stderrSink: stderrSink,
          stdoutByteSink: stdoutByteSink,
          stderrByteSink: stderrByteSink,
          stdinStream: stdinStream ?? io.stdin,
        ),
  );
}

bool _explicitlyAllowsPrerelease(String constraint, Version version) {
  if (!version.isPreRelease) return true;
  final prereleaseVersion = RegExp(r'\d+\.\d+\.\d+-[0-9A-Za-z.-]+')
      .allMatches(constraint);
  return prereleaseVersion.any((match) {
    try {
      final bound = Version.parse(match.group(0)!);
      return bound.major == version.major &&
          bound.minor == version.minor &&
          bound.patch == version.patch;
    } on FormatException {
      return false;
    }
  });
}

/// Wren-specific command base with shared output, verbosity and context.
abstract class WrenCommand extends Command<int> {
  /// Creates a Wren command with shared [context].
  new(this.context, {bool sdkCommand = false}) {
    if (!sdkCommand) {
      argParser.addFlag(
        'verbose',
        negatable: false,
        help: 'Show additional Wren diagnostic output.',
      );
    }
  }

  /// Shared values and services for this invocation.
  final WrenContext context;

  /// Whether this command or its invocation enabled verbose output.
  bool get verbose =>
      (globalResults?.flag('verbose') ?? false) ||
      (argResults?.flag('verbose') ?? false);

  /// Writes a line to standard output.
  void writeOut(Object? message) => context.stdoutSink.writeln(message);

  /// Writes a line to standard error.
  void writeError(Object? message) => context.stderrSink.writeln(message);

  /// Raises a command usage error with [message].
  Never failUsage(String message) => usageException(message);
}

/// Composition wrapper which only accepts Wren-owned commands.
class WrenCommandRunner {
  /// Creates a command runner with [context].
  new(this.context) : _runner = _WrenPackageCommandRunner(context);

  /// Shared invocation context.
  final WrenContext context;
  final _WrenPackageCommandRunner _runner;

  /// Registers a Wren command.
  void addCommand(WrenCommand command) => _runner.addCommand(command);

  /// Runs [arguments] and returns Wren's exit status.
  Future<int> run(Iterable<String> arguments) async {
    var args = arguments.toList(growable: false);
    String? explicitTracePath;
    var traceEnabled = false;
    try {
      final traceArguments = _extractTraceOption(args);
      args = traceArguments.arguments;
      traceEnabled = traceArguments.enabled;
      explicitTracePath = traceArguments.path;
      if (traceEnabled) {
        try {
          context._trace = await TraceSession.open(
            explicitPath: explicitTracePath,
            dataDirectory:
                context.installEnvironment.dataDirectory.absolute.path,
            startedAt: context._traceStartedAt,
            elapsed: context._traceElapsed,
          );
          if (context._traceStartedAt != null) {
            await context._trace!.recordStartup(
              context._traceElapsed!.elapsedMicroseconds,
            );
          }
        } on Object catch (error) {
          context.stderrSink.writeln('wren: could not open trace file: $error');
          return 4;
        }
      }
      final sdkCommandIndex = _sdkCommandIndex(args);
      if (sdkCommandIndex != null) {
        context._sdkArguments = args.skip(sdkCommandIndex + 1).toList();
        args = args.take(sdkCommandIndex + 1).toList(growable: false);
      }
      if (args.isEmpty || args.every((argument) => argument == '--verbose')) {
        context.stderrSink
          ..writeln('wren: a command is required.')
          ..writeln(_runner.usage);
        return await _finishTrace(2, '');
      }
      final command = _commandName(args);
      final status = context._trace == null
          ? await _runCommand(args)
          : await context.traceOperation<int>(
              'cli.dispatch',
              () => _runCommand(args),
            );
      return await _finishTrace(status, command);
    } on UsageException catch (error) {
      context.stderrSink
        ..writeln('wren: ${error.message}')
        ..writeln(error.usage);
      return await _finishTrace(2, _commandName(args));
    } on SdkLaunchException catch (error) {
      context.stderrSink.writeln('wren: ${error.message}');
      return await _finishTrace(error.status, _commandName(args));
    } on ReleaseCatalogException catch (error) {
      context.stderrSink.writeln('wren: ${error.message}');
      return await _finishTrace(4, _commandName(args));
    } on InstallException catch (error) {
      context.stderrSink.writeln('wren: ${error.message}');
      return await _finishTrace(4, _commandName(args));
    } on InstallCancelledException catch (error) {
      context.stderrSink.writeln('wren: ${error.message}');
      return await _finishTrace(6, _commandName(args));
    } on Object catch (error) {
      context.stderrSink.writeln('wren: command failed: $error');
      return await _finishTrace(4, _commandName(args));
    }
  }

  Future<int> _runCommand(List<String> arguments) async {
    try {
      return await _runner.run(arguments) ?? 0;
    } on UsageException catch (error) {
      context.stderrSink
        ..writeln('wren: ${error.message}')
        ..writeln(error.usage);
      return 2;
    } on SdkLaunchException catch (error) {
      context.stderrSink.writeln('wren: ${error.message}');
      return error.status;
    } on ReleaseCatalogException catch (error) {
      context.stderrSink.writeln('wren: ${error.message}');
      return 4;
    } on InstallException catch (error) {
      context.stderrSink.writeln('wren: ${error.message}');
      return 4;
    } on InstallCancelledException catch (error) {
      context.stderrSink.writeln('wren: ${error.message}');
      return 6;
    } on Object catch (error) {
      context.stderrSink.writeln('wren: command failed: $error');
      return 4;
    }
  }

  Future<int> _finishTrace(int status, String command) async {
    final trace = context._trace;
    if (trace == null) return status;
    try {
      await trace.finish(
        command: command,
        host: context.host?.label,
        wrenVersion: '1.0.0',
        exitStatus: status,
      );
      return status;
    } on Object catch (error) {
      context.stderrSink.writeln('wren: could not write trace file: $error');
      return 4;
    } finally {
      context._trace = null;
    }
  }

  _TraceOptionResult _extractTraceOption(List<String> arguments) {
    final commandIndex = _firstCommandIndex(arguments);
    final boundary = commandIndex ?? arguments.length;
    final kept = <String>[];
    var enabled = false;
    String? path;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (index >= boundary ||
          (argument != '--trace' && !argument.startsWith('--trace='))) {
        kept.add(argument);
        continue;
      }
      if (enabled) {
        throw UsageException(
          'only one --trace option is allowed.',
          _runner.usage,
        );
      }
      enabled = true;
      if (argument.startsWith('--trace=')) {
        path = argument.substring('--trace='.length);
        if (path.isEmpty) {
          throw UsageException(
            '--trace requires a non-empty path.',
            _runner.usage,
          );
        }
      }
    }
    return _TraceOptionResult(arguments: kept, enabled: enabled, path: path);
  }

  int? _firstCommandIndex(List<String> arguments) {
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--release') {
        if (index + 1 >= arguments.length) return null;
        index++;
      } else if (argument == '--verbose' ||
          argument == '--help' ||
          argument == '-h') {
        continue;
      } else if (argument.startsWith('-')) {
        continue;
      } else {
        return index;
      }
    }
    return null;
  }

  String _commandName(List<String> arguments) {
    final index = _firstCommandIndex(arguments);
    return index == null ? '' : arguments[index];
  }

  int? _sdkCommandIndex(List<String> arguments) {
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--verbose' || argument == '--help' || argument == '-h') {
        continue;
      }
      if (argument == '--release') {
        if (index + 1 >= arguments.length) return null;
        index++;
        continue;
      }
      if (argument.startsWith('--release=')) continue;
      if (argument == 'flutter' || argument == 'dart') return index;
      return null;
    }
    return null;
  }
}

class _TraceOptionResult {
  const new({required this.arguments, required this.enabled, this.path});

  final List<String> arguments;
  final bool enabled;
  final String? path;
}

class _WrenPackageCommandRunner extends CommandRunner<int> {
  new(this.context)
    : super('wren', 'A standalone Flutter and Dart version manager.') {
    argParser
      ..addFlag(
        'verbose',
        negatable: false,
        help: 'Show additional Wren diagnostic output.',
      )
      ..addOption(
        'release',
        help: 'Run an SDK command with this exact installed Flutter release.',
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
  String? flutterReleaseOverride,
  String? globalFallback,
  WrenConfirmation? confirmation,
  io.Directory? projectDirectory,
  List<InstalledRelease>? installedReleases,
  SdkLauncher? sdkLauncher,
  String? wrenExecutable,
  Stream<List<int>>? stdinStream,
}) async {
  final tracingRequested = _traceOptionPresentBeforeCommand(arguments);
  final traceStartedAt = tracingRequested ? DateTime.now().toUtc() : null;
  final traceElapsed = tracingRequested ? (Stopwatch()..start()) : null;
  final context = WrenContext(
    stdoutSink: stdoutSink,
    stderrSink: stderrSink,
    catalogJson: catalogJson,
    hostOverride: host,
    configuredInstallEnvironment: installEnvironment,
    flutterReleaseOverride: flutterReleaseOverride,
    globalFallbackOverride: globalFallback,
    confirmation: confirmation,
    projectDirectory: projectDirectory,
    installedReleasesOverride: installedReleases,
    sdkLauncher: sdkLauncher,
    wrenExecutable: wrenExecutable,
    stdinStream: stdinStream,
    traceStartedAt: traceStartedAt,
    traceElapsed: traceElapsed,
  );
  final runner = WrenCommandRunner(context)
    ..addCommand(_ReleasesCommand(context))
    ..addCommand(_InstallCommand(context))
    ..addCommand(_RemoveCommand(context))
    ..addCommand(_RepairCommand(context))
    ..addCommand(_CleanupCommand(context))
    ..addCommand(_ListCommand(context))
    ..addCommand(_SetCommand(context))
    ..addCommand(_SdkPathCommand(context))
    ..addCommand(_SetupCommand(context))
    ..addCommand(_FlutterCommand(context))
    ..addCommand(_DartCommand(context));
  return await runner.run(arguments);
}

bool _traceOptionPresentBeforeCommand(List<String> arguments) {
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--trace' || argument.startsWith('--trace=')) return true;
    if (argument == '--release') {
      if (index + 1 < arguments.length) index++;
    } else if (argument.startsWith('-')) {
      continue;
    } else {
      return false;
    }
  }
  return false;
}

class _RemoveCommand extends WrenCommand {
  new(super.context);

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove an installed Flutter release.';

  @override
  Future<int> run() async {
    final arguments = argResults!.rest;
    if (arguments.length != 1) {
      failUsage('remove requires exactly one Flutter release version.');
    }
    final targetHost = context.host;
    if (targetHost == null) {
      throw const InstallException(
        'this host is unsupported. Wren supports Linux x86_64 and macOS arm64.',
      );
    }
    final version = arguments.single;
    final fallback = await context.globalFallback;
    await context.traceOperation('release.remove', () async {
      await context.installer.remove(
        version,
        host: targetHost,
        confirmExternalUse: context.confirm,
        confirmSharedRepository: context.confirm,
        onUnavailable: () async {
          if (fallback == version) await context._clearGlobalFallback(version);
        },
      );
    });
    final installed = await context.traceOperation(
      'release.list_installed',
      context.installer.listInstalled,
    );
    final active = await context.selectProjectRelease(targetHost, installed);
    if (active == null || active.isEmpty) {
      writeOut('Removed Flutter $version. No release is active.');
    } else {
      writeOut('Removed Flutter $version. Active release: Flutter $active.');
    }
    return 0;
  }
}

class _CleanupCommand extends WrenCommand {
  new(super.context) {
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: 'Show orphaned storage that would be reclaimed.',
    );
  }

  @override
  String get name => 'cleanup';

  @override
  String get description => 'Reclaim orphaned stages and shared sources.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      failUsage('cleanup does not accept positional arguments.');
    }
    final result = await context.traceOperation(
      'cleanup.reclaim_orphans',
      () => context.installer.cleanup(dryRun: argResults!.flag('dry-run')),
    );
    final dryRun = argResults!.flag('dry-run');
    if (result.stages.isEmpty && result.sources.isEmpty) {
      writeOut(
        dryRun ? 'No orphaned stages or sources found.' : 'Nothing to clean.',
      );
      return 0;
    }
    for (final stage in result.stages) {
      writeOut(
        '${dryRun ? 'Would reclaim' : 'Reclaimed'} orphaned stage: $stage',
      );
    }
    for (final source in result.sources) {
      writeOut(
        '${dryRun ? 'Would reclaim' : 'Reclaimed'} unreferenced shared '
        'source: $source',
      );
    }
    return 0;
  }
}

class _RepairCommand extends WrenCommand {
  new(super.context);

  @override
  String get name => 'repair';

  @override
  String get description =>
      'Validate or repair a retained source and release-private files.';

  @override
  Future<int> run() async {
    final arguments = argResults!.rest;
    if (arguments.length != 1) {
      failUsage('repair requires exactly one Flutter release version.');
    }
    final targetHost = context.host;
    if (targetHost == null) {
      throw const InstallException(
        'this host is unsupported. Wren supports Linux x86_64 and macOS arm64.',
      );
    }
    final version = arguments.single;
    final result = await context.installer.repair(
      version,
      host: targetHost,
      confirmExternalUse: context.confirm,
    );
    if (result.replaced) {
      writeOut('Repaired the shared engine source for Flutter $version.');
    }
    if (result.privateFilesRepaired) {
      writeOut('Repaired private files for Flutter $version.');
    }
    if (result.optionalArtifactsRepaired) {
      writeOut('Repaired optional target artifacts for Flutter $version.');
    }
    if (!result.replaced &&
        !result.privateFilesRepaired &&
        !result.optionalArtifactsRepaired) {
      writeOut('The shared engine source for Flutter $version is healthy.');
    }
    return 0;
  }
}

class _ReleasesCommand extends WrenCommand {
  new(super.context);

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
        'wren: this host is unsupported. Wren supports Linux x86_64 and '
        'macOS arm64.',
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
  new(super.context);

  @override
  String get name => 'install';

  @override
  String get description =>
      'Install an eligible stable or beta Flutter release.';

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
        'wren: this host is unsupported. Wren supports Linux x86_64 and '
        'macOS arm64.',
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
    final result = await context.traceOperation(
      'release.install',
      () => context.installer.install(release, host: targetHost),
    );
    writeOut(result.message);
    return 0;
  }
}

class _ListCommand extends WrenCommand {
  new(super.context);

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
    final releases = await context.traceOperation(
      'release.list_installed',
      context.installer.listInstalled,
    );
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
        '${release.version}  ${release.channel}  ${release.host}  '
        '$readiness$reason',
      );
    }
    return 0;
  }
}

class _SetCommand extends WrenCommand {
  new(super.context) {
    argParser.addFlag(
      'global',
      abbr: 'g',
      negatable: false,
      help: 'Also set the global fallback.',
    );
  }

  @override
  String get name => 'set';

  @override
  List<String> get aliases => const ['use'];

  @override
  String get description =>
      'Set project Flutter and Dart constraints and optionally the fallback.';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      failUsage(
        argResults!.rest.isEmpty
            ? '`set` requires a Flutter release version.'
            : 'unexpected argument "${argResults!.rest[1]}".',
      );
    }

    final targetHost = context.host;
    if (targetHost == null) {
      writeError(
        'wren: this host is unsupported. Wren supports Linux x86_64 and '
        'macOS arm64.',
      );
      return 4;
    }
    final releaseVersion = argResults!.rest.single;
    final installed =
        context.installedReleasesOverride ??
        await context.installer.listInstalled();
    InstalledRelease? selected;
    for (final release in installed) {
      if (release.version == releaseVersion &&
          release.host == targetHost.catalogOs &&
          !release.needsRepair &&
          release.dartVersion != null) {
        selected = release;
        break;
      }
    }
    if (selected == null) {
      writeError(
        'wren: Flutter $releaseVersion is not an installed, ready release. '
        'Run `wren install $releaseVersion` or `wren repair $releaseVersion`.',
      );
      return 4;
    }

    final projectDirectory = context.projectDirectory ?? io.Directory.current;
    final pubspec = io.File('${projectDirectory.path}/pubspec.yaml');
    final setGlobal = argResults!.flag('global');
    if (!pubspec.existsSync() && !setGlobal) {
      writeError('wren: no pubspec.yaml exists in the current directory.');
      return 4;
    }

    var content = pubspec.existsSync()
        ? await context.traceOperation(
            'pubspec.read',
            () async => pubspec.readAsStringSync(),
          )
        : null;
    var edits = <String, (String, String)>{};
    var existingKeys = <String>{};
    if (content != null) {
      try {
        final rewrite = _rewriteProjectConstraints(content, selected);
        content = rewrite.content;
        edits = rewrite.edits;
        existingKeys = rewrite.existingKeys;
      } on FormatException catch (error) {
        writeError('wren: cannot update pubspec.yaml: ${error.message}');
        return 4;
      }
    }

    final sdkEdit = edits['sdk'];
    if (sdkEdit != null &&
        _changesDartLanguageVersion(sdkEdit.$1, selected.dartVersion!)) {
      final confirmation = await context.confirm(
        'Changing the Dart SDK lower bound from ${sdkEdit.$1} to ${sdkEdit.$2} '
        'changes the Dart language version.',
      );
      if (confirmation != true) {
        writeError(
          confirmation == null
              ? 'wren: confirmation is unavailable; no changes were made.'
              : 'wren: cancelled; no changes were made.',
        );
        return 6;
      }
    }

    final fallbackUpdate = setGlobal
        ? context._prepareGlobalFallback(selected.version)
        : null;
    final currentContent = content == null
        ? null
        : await context.traceOperation(
            'pubspec.read_before_write',
            () async => pubspec.readAsStringSync(),
          );
    if (content != null && content != currentContent) {
      await context.traceOperation('pubspec.write', () async {
        _replaceFileAtomically(pubspec, content!, temporarySuffix: '.wren.tmp');
      });
    }
    if (fallbackUpdate != null) {
      await context._setGlobalFallback(fallbackUpdate);
    }

    for (final entry in edits.entries) {
      writeOut(
        'Updated environment.${entry.key}: ${entry.value.$1} '
        '→ ${entry.value.$2}',
      );
    }
    if (edits.isEmpty && pubspec.existsSync()) {
      writeOut(
        existingKeys.isEmpty
            ? 'No existing environment.flutter or environment.sdk keys '
                  'to update.'
            : 'Existing Flutter and Dart constraints already match '
                  'this release.',
      );
    }
    if (setGlobal) {
      writeOut('Global fallback set to Flutter ${selected.version}.');
    }

    final activeRelease = await context.selectProjectRelease(
      targetHost,
      installed,
    );
    writeOut(
      activeRelease == null
          ? 'No Flutter release is active under normal selection.'
          : 'Active Flutter release under normal selection: $activeRelease.',
    );
    return 0;
  }
}

class _PreparedGlobalFallback {
  const new({
    required this.config,
    required this.release,
    required this.contents,
  });

  final io.File config;
  final String release;
  final String contents;
}

void _replaceFileAtomically(
  io.File destination,
  String contents, {
  required String temporarySuffix,
}) {
  io.File('${destination.path}$temporarySuffix')
    ..writeAsStringSync(contents)
    ..renameSync(destination.path);
}

({
  String content,
  Map<String, (String, String)> edits,
  Set<String> existingKeys,
})
_rewriteProjectConstraints(String content, InstalledRelease release) {
  final editor = YamlEditor(content);
  final root = editor.parseAt(const []);
  if (root is! YamlMap) {
    throw const FormatException('the document root must be a mapping');
  }
  final environment = root.nodes['environment'];
  if (environment is! YamlMap) {
    return (content: content, edits: {}, existingKeys: <String>{});
  }

  final versions = <String, String>{
    'flutter': release.version,
    'sdk': release.dartVersion!,
  };
  final edits = <String, (String, String)>{};
  final existingKeys = <String>{};
  for (final entry in versions.entries) {
    final node = environment.nodes[entry.key];
    if (node == null) continue;
    existingKeys.add(entry.key);
    final oldValue = node.value.toString();
    final newValue = '^${entry.value}';
    if (oldValue == newValue) continue;
    editor.update(['environment', entry.key], newValue);
    edits[entry.key] = (oldValue, newValue);
  }
  return (content: editor.toString(), edits: edits, existingKeys: existingKeys);
}

bool _changesDartLanguageVersion(String oldConstraint, String newVersion) {
  final next = Version.parse(newVersion);
  try {
    final constraint = VersionConstraint.parse(oldConstraint);
    final lowerBound = constraint is VersionRange ? constraint.min : null;
    return lowerBound == null ||
        lowerBound.major != next.major ||
        lowerBound.minor != next.minor;
  } on FormatException {
    // An invalid existing lower bound cannot prove that the language version
    // will remain stable, so require confirmation before replacing it.
    return true;
  }
}

class _FlutterCommand extends _SdkCommand {
  new(WrenContext context) : super(context, 'flutter');
}

class _DartCommand extends _SdkCommand {
  new(WrenContext context) : super(context, 'dart');
}

class _SdkPathCommand extends WrenCommand {
  new(super.context);

  @override
  String get name => 'sdk-path';

  @override
  String get description =>
      'Print the fixed SDK root for an installed release.';

  @override
  Future<int> run() async {
    if (argResults!.rest.length > 1) {
      failUsage('sdk-path accepts at most one Flutter release.');
    }
    final targetHost = context.host;
    if (targetHost == null) {
      throw const SdkLaunchException(
        status: 3,
        message:
            'this host is unsupported. Wren supports Linux x86_64 and '
            'macOS arm64.',
      );
    }

    final installed =
        context.installedReleasesOverride ??
        await context.installer.listInstalled();
    final requestedRelease = argResults!.rest.isEmpty
        ? null
        : argResults!.rest.single;
    final environmentRelease =
        context.flutterReleaseOverride ??
        io.Platform.environment['WREN_FLUTTER_RELEASE'];
    final exactRelease =
        requestedRelease ??
        (environmentRelease?.trim().isNotEmpty ?? false
            ? environmentRelease!.trim()
            : null);
    final release =
        exactRelease ??
        await context.selectProjectRelease(targetHost, installed);
    if (release == null || release.isEmpty) {
      throw const SdkLaunchException(
        status: 3,
        message:
            'No installed Flutter release matches this project and no global '
            'fallback is configured. Run `wren set <release>` or '
            '`wren install <release>`.',
      );
    }
    final path = await context.traceOperation(
      'sdk_path.record_external_use',
      () => context.installer.sdkPath(release, host: targetHost),
    );
    writeOut(path);
    return 0;
  }
}

class _SetupCommand extends WrenCommand {
  new(super.context);

  @override
  String get name => 'setup';

  @override
  String get description =>
      'Install optional Flutter and Dart PATH shims and show editor setup.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      failUsage('setup does not accept arguments.');
    }
    final binDirectory = io.Directory(
      '${context.installEnvironment.dataDirectory.absolute.path}/bin',
    );
    await context.traceOperation('setup.write_shims', () async {
      await binDirectory.create(recursive: true);
      final executable =
          context.wrenExecutable ?? io.Platform.resolvedExecutable;
      for (final command in ['flutter', 'dart']) {
        await _writeShim(
          io.File('${binDirectory.path}/$command'),
          executable: executable,
          command: command,
        );
      }
    });

    final binPath = binDirectory.absolute.path;
    writeOut('Installed Flutter and Dart shims in $binPath.');
    writeOut('Add this directory to PATH in your shell:');
    writeOut('  export PATH=${_shellQuote(binPath)}:"\$PATH"');
    writeOut('Open a new terminal or run that export in the current shell.');
    writeOut('');
    writeOut('VS Code Dart extension (user or workspace settings):');
    writeOut(
      '''  "dart.getFlutterSdkCommand": {"executable": "wren", "args": ["sdk-path"]}''',
    );
    writeOut(
      'The command resolves the workspace selection when VS Code discovers '
      'the project. Reload the window after changing the active release.',
    );
    writeOut('');
    writeOut(
      'JetBrains Flutter SDK path: run wren sdk-path <release> and '
      'copy the printed SDK root into the IDE.',
    );
    writeOut(
      'JetBrains keeps that fixed path on the selected release; update it '
      'manually after switching releases.',
    );
    return 0;
  }

  Future<void> _writeShim(
    io.File destination, {
    required String executable,
    required String command,
  }) async {
    final temporary = io.File('${destination.path}.tmp');
    await temporary.writeAsString(
      '#!/bin/sh\nexec ${_shellQuote(executable)} $command "\$@"\n',
      flush: true,
    );
    final chmod = await io.Process.run('chmod', [
      'u=rwx,go=rx',
      temporary.path,
    ]);
    if (chmod.exitCode != 0) {
      await temporary.delete();
      throw InstallException(
        'could not make the $command shim executable: ${chmod.stderr}',
      );
    }
    await temporary.rename(destination.path);
  }
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

abstract class _SdkCommand extends WrenCommand {
  new(super.context, this.name) : super(sdkCommand: true);

  @override
  final String name;

  @override
  String get description => 'Run the selected Flutter SDK $name executable.';

  @override
  Future<int> run() async {
    final targetHost = context.host;
    if (targetHost == null) {
      throw const SdkLaunchException(
        status: 3,
        message:
            'this host is unsupported. Wren supports Linux x86_64 and '
            'macOS arm64.',
      );
    }
    final cliRelease = globalResults?.option('release');
    final environmentRelease =
        context.flutterReleaseOverride ??
        io.Platform.environment['WREN_FLUTTER_RELEASE'];
    final release = cliRelease != null
        ? cliRelease.trim()
        : environmentRelease?.trim();
    final hasExactOverride =
        cliRelease != null || (environmentRelease?.trim().isNotEmpty ?? false);
    final selectedRelease = !hasExactOverride
        ? await context.selectProjectRelease(
            targetHost,
            context.installedReleasesOverride ??
                await context.installer.listInstalled(),
          )
        : release;
    if (selectedRelease == null || selectedRelease.isEmpty) {
      throw const SdkLaunchException(
        status: 3,
        message:
            'No installed Flutter release matches this project and no global '
            'fallback is configured. Run `wren set <release>` or '
            '`wren install <release>`.',
      );
    }
    return await context.launchSdk(
      selectedRelease,
      host: targetHost,
      executable: name,
      arguments: context._sdkArguments,
    );
  }
}

/// A supported host and its release catalog identifiers.
enum HostPlatform {
  /// Linux on x86_64.
  linuxX64(
    label: 'Linux x86_64',
    catalogUrl: _linuxCatalog,
    catalogOs: 'linux',
    catalogArchitecture: 'x64',
  ),

  /// macOS on Apple Silicon.
  macosArm64(
    label: 'macOS arm64',
    catalogUrl: _macosCatalog,
    catalogOs: 'macos',
    catalogArchitecture: 'arm64',
  );

  /// Creates a host platform from catalog identifiers.
  new({
    required this.label,
    required this.catalogUrl,
    required this.catalogOs,
    required this.catalogArchitecture,
  });

  /// User-facing host name.
  final String label;

  /// Release catalog URL for this host.
  final String catalogUrl;

  /// Operating system identifier used by the catalog.
  final String catalogOs;

  /// Architecture identifier used by the catalog.
  final String catalogArchitecture;

  /// Detects the current supported host.
  static HostPlatform? get current {
    final abi = Abi.current();
    if (io.Platform.isLinux && abi == Abi.linuxX64) return linuxX64;
    if (io.Platform.isMacOS && abi == Abi.macosArm64) return macosArm64;
    return null;
  }

  /// Catalog URL as a URI.
  Uri get catalogUri => Uri.parse(catalogUrl);
}

/// A Flutter release and its catalog identities.
class FlutterRelease {
  /// Creates a Flutter release record.
  const new({
    required this.version,
    required this.channel,
    required this.frameworkRevision,
    required this.dartVersion,
    required this.dartSemVersion,
    required this.archive,
    required this.archiveSha256,
  });

  /// Flutter version.
  final String version;

  /// Release channel.
  final String channel;

  /// Framework commit.
  final String frameworkRevision;

  /// Canonical bundled Dart version.
  final String dartVersion;

  /// Parsed bundled Dart version.
  final Version dartSemVersion;

  /// Host-specific release archive path.
  final String archive;

  /// SHA-256 digest of the release archive.
  final String archiveSha256;
}

/// Eligible releases and reasons known releases were excluded.
class ReleaseCatalog {
  /// Creates a catalog containing [releases].
  const new(this.releases, [this._eligibilityByVersion = const {}]);

  /// Parses a catalog and records eligibility for every known version.
  factory parse(String json, {required HostPlatform host}) {
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

  /// Eligible releases in catalog order.
  final List<FlutterRelease> releases;
  final Map<String, ReleaseEligibility> _eligibilityByVersion;

  /// Resolves an explicitly requested Flutter version, including a reason if
  /// the catalog knows the release but Wren cannot install it on this host.
  ReleaseEligibility eligibilityForVersion(String version) =>
      _eligibilityByVersion[version] ??
      ReleaseEligibility.ineligible(
        'Flutter release $version is not present in the host catalog.',
      );

  /// Fetches and parses a release catalog from [uri].
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
          'could not read the Flutter release catalog (HTTP '
          '${response.statusCode}).',
        );
      }
      final body = await utf8.decoder.bind(response).join();
      return ReleaseCatalog.parse(body, host: host);
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

  /// Checks one catalog [entry] for eligibility on [host].
  static ReleaseEligibility eligibilityFor(
    Map<String, Object?> entry, {
    required HostPlatform host,
  }) => _eligibility(entry, host);
}

/// The eligible release or exclusion reason for a catalog entry.
class ReleaseEligibility {
  /// Creates an eligible result for [release].
  const new eligible(this.release) : reason = null;

  /// Creates an ineligible result with [reason].
  const new ineligible(this.reason) : release = null;

  /// The release when eligible.
  final FlutterRelease? release;

  /// Explanation when the entry is ineligible.
  final String? reason;

  /// Whether the entry can be installed.
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
  final channelName = channel! as String;
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
  final normalized = archive.toLowerCase().replaceAll(r'\', '/');
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

/// An error while fetching or parsing a Flutter release catalog.
class ReleaseCatalogException implements Exception {
  /// Creates a catalog exception with [message].
  const new(this.message);

  /// Explanation of the catalog failure.
  final String message;
}
