import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:wren/src/installer.dart';

/// The result level for one Wren setup check.
enum DoctorCheckSeverity {
  /// The component is usable.
  ok,

  /// The component is optional or outside Wren's control.
  informational,

  /// Wren-owned configuration is confirmed broken or required Git is absent.
  critical,

  /// The component could not be inspected or a check timed out.
  incomplete,
}

/// One setup check shown by `wren doctor`.
class DoctorSetupCheck {
  /// Creates a setup check result.
  const new({
    required this.component,
    required this.severity,
    required this.summary,
    this.nextStep,
  });

  /// Component inspected by this check.
  final String component;

  /// Whether the result is usable, informational, critical, or incomplete.
  final DoctorCheckSeverity severity;

  /// Human-readable outcome of the check.
  final String summary;

  /// Optional actionable instruction.
  final String? nextStep;
}

/// Results for Wren-owned setup and host dependency checks.
class DoctorSetupReport {
  /// Creates a setup report.
  new(List<DoctorSetupCheck> checks) : checks = List.unmodifiable(checks);

  /// All completed and partial setup checks.
  final List<DoctorSetupCheck> checks;

  /// Whether a confirmed critical setup problem was found.
  bool get hasCritical =>
      checks.any((check) => check.severity == DoctorCheckSeverity.critical);

  /// Whether one or more setup checks could not complete.
  bool get isIncomplete =>
      checks.any((check) => check.severity == DoctorCheckSeverity.incomplete);
}

/// Inspects setup components without changing shell, editor, or SDK files.
class DoctorSetupInspector {
  /// Creates an inspector for one Wren invocation.
  const new({
    required this.dataDirectory,
    required this.executablePath,
    required this.processEnvironment,
    required this.processEnvironmentOverride,
    required this.globalFallbackOverride,
    this.checkTimeout = const Duration(seconds: 1),
  });

  /// Wren's local data directory.
  final io.Directory dataDirectory;

  /// Executable running this Wren invocation.
  final String executablePath;

  /// Environment visible to this invocation.
  final Map<String, String> processEnvironment;

  /// Whether the environment should be passed without inheriting parent vars.
  final Map<String, String>? processEnvironmentOverride;

  /// Optional test override for the configured global fallback.
  final String? globalFallbackOverride;

  /// Upper bound for an individual quick setup check.
  final Duration checkTimeout;

  /// Runs each independent setup check concurrently and retains partial data.
  Future<DoctorSetupReport> inspect({
    required List<InstalledRelease> installedReleases,
    Object? releaseEnumerationError,
  }) async {
    final checks = await Future.wait([
      _bounded('Executable', _inspectExecutable),
      _bounded('Storage', _inspectStorage),
      _bounded('Release registry', _inspectRegistry),
      _bounded(
        'Global fallback',
        () => _inspectGlobalFallback(installedReleases),
      ),
      _bounded('PATH shims', _inspectShims),
      _bounded('Current process PATH', _inspectCurrentPath),
      _inspectGit(),
    ]);
    final registryCheckFailed = checks.any(
      (check) =>
          check.component == 'Release registry' &&
          check.severity == DoctorCheckSeverity.incomplete,
    );
    return DoctorSetupReport([
      ...checks,
      if (releaseEnumerationError != null && !registryCheckFailed)
        _incomplete(
          'Installed releases',
          'release readiness could not be inspected: $releaseEnumerationError.',
          nextStep: 'Check access to Wren storage and run `wren doctor` again.',
        ),
    ]);
  }

  Future<DoctorSetupCheck> _bounded(
    String component,
    Future<DoctorSetupCheck> Function() inspect, {
    void Function()? onTimeout,
  }) async {
    try {
      return await inspect().timeout(
        checkTimeout,
        onTimeout: () {
          onTimeout?.call();
          return _incomplete(
            component,
            'the quick check timed out; this component could not be verified.',
            nextStep: 'Run `wren doctor` again when the system is responsive.',
          );
        },
      );
    } on Object catch (error) {
      return _incomplete(
        component,
        'could not inspect this component: $error.',
        nextStep: 'Check access to this component and run `wren doctor` again.',
      );
    }
  }

  Future<DoctorSetupCheck> _inspectExecutable() async {
    final file = io.File(executablePath);
    if (io.FileSystemEntity.typeSync(executablePath) !=
        io.FileSystemEntityType.file) {
      return _critical(
        'Executable',
        'Wren executable is missing or is not a regular file: $executablePath.',
        nextStep: 'Install Wren again and run the installed executable.',
      );
    }
    if ((file.statSync().mode & 0x49) == 0) {
      return _critical(
        'Executable',
        'Wren executable is not runnable: $executablePath.',
        nextStep: 'Restore executable permission on the Wren binary.',
      );
    }
    return _ok('Executable', 'Wren is running from $executablePath.');
  }

  Future<DoctorSetupCheck> _inspectStorage() async {
    final path = dataDirectory.absolute.path;
    final type = io.FileSystemEntity.typeSync(path);
    if (type == io.FileSystemEntityType.notFound) {
      return _informational(
        'Storage',
        'Wren storage has not been created yet: $path.',
        nextStep: 'Run `wren install <release>` to create Wren storage.',
      );
    }
    if (type != io.FileSystemEntityType.directory) {
      return _critical(
        'Storage',
        'Wren storage path is not a directory: $path.',
        nextStep: 'Move the conflicting file and retry Wren.',
      );
    }

    // Opening the listing checks that Wren can inspect the storage directory
    // without creating a probe file or otherwise changing user data.
    await dataDirectory.list(followLinks: false).take(1).toList();
    final permissionBits = dataDirectory.statSync().mode;
    if ((permissionBits & 0x92) == 0) {
      return _critical(
        'Storage',
        'Wren storage has no write permission bits: $path.',
        nextStep: 'Restore write permission for Wren storage.',
      );
    }
    return _ok(
      'Storage',
      'Wren storage is readable and its permission bits allow writes at $path.',
    );
  }

  Future<DoctorSetupCheck> _inspectRegistry() async {
    final path = p.join(dataDirectory.absolute.path, 'releases');
    final type = io.FileSystemEntity.typeSync(path);
    if (type == io.FileSystemEntityType.notFound) {
      return _informational(
        'Release registry',
        'No installed releases are registered yet.',
      );
    }
    if (type != io.FileSystemEntityType.directory) {
      return _critical(
        'Release registry',
        'Wren release registry is not a directory: $path.',
        nextStep: 'Move the conflicting file and retry Wren.',
      );
    }

    final releases = await io.Directory(path).list(followLinks: false).toList();
    for (final entry in releases) {
      if (entry is io.Link) {
        return _critical(
          'Release registry',
          'Release registry contains a symbolic-link entry: '
              '${p.basename(entry.path)}.',
          nextStep:
              'Inspect or remove that entry from the Wren releases directory.',
        );
      }
      if (entry is! io.Directory) continue;
      final markerPath = p.join(entry.path, '.wren-release.json');
      if (io.FileSystemEntity.typeSync(markerPath, followLinks: false) !=
          io.FileSystemEntityType.file) {
        return _critical(
          'Release registry',
          'Registered release ${p.basename(entry.path)} has no regular '
              '.wren-release.json record.',
          nextStep: 'Inspect the release and run `wren repair <release>`.',
        );
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(await io.File(markerPath).readAsString());
      } on FormatException {
        return _critical(
          'Release registry',
          'Release record for ${p.basename(entry.path)} is not valid JSON.',
          nextStep: 'Run `wren repair ${p.basename(entry.path)}`.',
        );
      }
      if (!_isValidReleaseRecord(decoded, entry.path)) {
        return _critical(
          'Release registry',
          'Release record for ${p.basename(entry.path)} has an invalid '
              'identity or state.',
          nextStep: 'Run `wren repair ${p.basename(entry.path)}`.',
        );
      }
    }
    return _ok(
      'Release registry',
      '${releases.length} release '
          '${releases.length == 1 ? 'is' : 'entries are'} registered.',
    );
  }

  bool _isValidReleaseRecord(Object? decoded, String directoryPath) {
    if (decoded is! Map<String, Object?>) return false;
    final channel = decoded['channel'];
    final version = decoded['version'];
    final host = decoded['host'];
    final architecture = decoded['architecture'];
    final state = decoded['state'];
    final frameworkRevision = decoded['frameworkRevision'];
    final engineRevision = decoded['engineRevision'];
    final sourceKey = decoded['sourceKey'];
    final canonicalDartVersion = decoded['canonicalDartVersion'];
    if (channel is! String || !{'stable', 'beta'}.contains(channel)) {
      return false;
    }
    if (version is! String || host is! String || architecture is! String) {
      return false;
    }
    try {
      Version.parse(version);
    } on FormatException {
      return false;
    }
    final variant = switch ((host, architecture)) {
      ('linux', 'x64') => 'linux-x64',
      ('macos', 'arm64') => 'macos-arm64',
      _ => null,
    };
    if (variant == null ||
        p.basename(directoryPath) != '$channel-$version-$variant' ||
        state != 'ready' ||
        frameworkRevision is! String ||
        !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(frameworkRevision) ||
        engineRevision is! String ||
        !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(engineRevision) ||
        sourceKey != '$engineRevision-$host-$architecture' ||
        canonicalDartVersion is! String) {
      return false;
    }
    try {
      Version.parse(canonicalDartVersion);
    } on FormatException {
      return false;
    }
    return true;
  }

  Future<DoctorSetupCheck> _inspectGlobalFallback(
    List<InstalledRelease> installedReleases,
  ) async {
    if (globalFallbackOverride != null) {
      final fallback = globalFallbackOverride!.trim();
      return _fallbackSummary(
        fallback,
        installedReleases,
        source: 'invocation',
      );
    }

    final path = p.join(dataDirectory.absolute.path, 'config.json');
    final type = io.FileSystemEntity.typeSync(path);
    if (type == io.FileSystemEntityType.notFound) {
      return _informational('Global fallback', 'No global fallback is set.');
    }
    if (type != io.FileSystemEntityType.file) {
      return _critical(
        'Global fallback',
        'Wren config.json is not a regular file.',
        nextStep:
            'Move the invalid config path and run `wren set -g <release>`.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(await io.File(path).readAsString());
    } on FormatException {
      return _critical(
        'Global fallback',
        'Wren config.json is not valid JSON.',
        nextStep: 'Repair config.json or run `wren set -g <release>`.',
      );
    }
    if (decoded is! Map<String, Object?>) {
      return _critical(
        'Global fallback',
        'Wren config.json must contain a JSON object.',
        nextStep: 'Repair config.json or run `wren set -g <release>`.',
      );
    }
    if (!decoded.containsKey('globalFallback') ||
        decoded['globalFallback'] == null) {
      return _informational('Global fallback', 'No global fallback is set.');
    }
    final fallbackValue = decoded['globalFallback'];
    if (fallbackValue is! String) {
      return _critical(
        'Global fallback',
        'Wren config.json has a non-string globalFallback value.',
        nextStep: 'Repair config.json or run `wren set -g <release>`.',
      );
    }
    final fallback = fallbackValue.trim();
    if (fallback.isEmpty) {
      return _informational('Global fallback', 'No global fallback is set.');
    }
    try {
      Version.parse(fallback);
    } on FormatException {
      return _critical(
        'Global fallback',
        'Configured global fallback `$fallback` is not a Flutter release '
            'version.',
        nextStep: 'Run `wren set -g <release>` with an installed release.',
      );
    }
    return _fallbackSummary(fallback, installedReleases, source: 'config.json');
  }

  DoctorSetupCheck _fallbackSummary(
    String fallback,
    List<InstalledRelease> installedReleases, {
    required String source,
  }) {
    if (fallback.isEmpty) {
      return _informational('Global fallback', 'No global fallback is set.');
    }
    final installed = installedReleases.any(
      (release) => release.version == fallback,
    );
    final summary =
        'Flutter $fallback is configured from $source'
        '${installed ? ' and is installed.' : ' (not currently installed).'}';
    return installed
        ? _ok('Global fallback', summary)
        : _informational('Global fallback', summary);
  }

  Future<DoctorSetupCheck> _inspectShims() async {
    final binPath = p.join(dataDirectory.absolute.path, 'bin');
    final type = io.FileSystemEntity.typeSync(binPath);
    if (type == io.FileSystemEntityType.notFound) {
      return _informational(
        'PATH shims',
        'Optional Flutter and Dart shims are not installed.',
        nextStep: 'Run `wren setup` if you want shell shims.',
      );
    }
    if (type != io.FileSystemEntityType.directory) {
      return _critical(
        'PATH shims',
        'Wren shim path is not a directory: $binPath.',
        nextStep: 'Move the conflicting file and run `wren setup`.',
      );
    }

    final missing = <String>[];
    for (final command in ['flutter', 'dart']) {
      final shimPath = p.join(binPath, command);
      if (io.FileSystemEntity.typeSync(shimPath, followLinks: false) ==
          io.FileSystemEntityType.notFound) {
        missing.add(command);
        continue;
      }
      if (io.FileSystemEntity.typeSync(shimPath, followLinks: false) !=
          io.FileSystemEntityType.file) {
        return _critical(
          'PATH shims',
          'Wren $command shim is not a regular file: $shimPath.',
          nextStep: 'Run `wren setup` to replace the broken shim.',
        );
      }
      final shim = io.File(shimPath);
      if ((shim.statSync().mode & 0x49) == 0) {
        return _critical(
          'PATH shims',
          'Wren $command shim is not executable.',
          nextStep: 'Run `wren setup` to replace the broken shim.',
        );
      }
      final target = _shimTarget(await shim.readAsString(), command);
      if (target == null || target != executablePath) {
        return _critical(
          'PATH shims',
          'Wren $command shim does not target the current Wren executable.',
          nextStep: 'Run `wren setup` to refresh the shim.',
        );
      }
    }
    if (missing.isNotEmpty) {
      return _informational(
        'PATH shims',
        'Optional shims are missing: ${missing.join(', ')}.',
        nextStep: 'Run `wren setup` if you want both shell shims.',
      );
    }
    return _ok('PATH shims', 'Flutter and Dart Wren shims are installed.');
  }

  String? _shimTarget(String contents, String command) {
    final lines = contents.split('\n');
    if (lines.length != 3 || lines[0] != '#!/bin/sh' || lines[2].isNotEmpty) {
      return null;
    }
    const prefix = 'exec ';
    final suffix = ' $command "\$@"';
    final invocation = lines[1];
    if (!invocation.startsWith(prefix) || !invocation.endsWith(suffix)) {
      return null;
    }
    final quotedTarget = invocation.substring(
      prefix.length,
      invocation.length - suffix.length,
    );
    if (quotedTarget.length < 2 ||
        !quotedTarget.startsWith("'") ||
        !quotedTarget.endsWith("'")) {
      return null;
    }
    return quotedTarget
        .substring(1, quotedTarget.length - 1)
        .replaceAll("'\"'\"'", "'");
  }

  Future<DoctorSetupCheck> _inspectCurrentPath() async {
    final path = processEnvironment['PATH'] ?? '';
    final wanted = p.normalize(p.absolute(p.join(dataDirectory.path, 'bin')));
    final containsWrenShims = path
        .split(io.Platform.isWindows ? ';' : ':')
        .any((entry) => p.normalize(p.absolute(entry)) == wanted);
    if (containsWrenShims) {
      return _ok(
        'Current process PATH',
        'Current-process PATH includes the Wren shim directory.',
      );
    }
    return _informational(
      'Current process PATH',
      'Current-process PATH does not include the Wren shim directory.',
      nextStep:
          'Add ${p.join(dataDirectory.absolute.path, 'bin')} to PATH '
          'for this process.',
    );
  }

  Future<DoctorSetupCheck> _inspectGit() {
    io.Process? process;
    return _bounded('System Git', () async {
      try {
        process = await io.Process.start(
          'git',
          ['--version'],
          environment: processEnvironmentOverride,
          includeParentEnvironment: processEnvironmentOverride == null,
        );
      } on io.ProcessException {
        return _critical(
          'System Git',
          'System Git is not available on the current-process PATH.',
          nextStep: 'Install Git and ensure `git` is available on PATH.',
        );
      }
      final started = process!;
      final stdoutFuture = started.stdout.transform(utf8.decoder).join();
      final stderrFuture = started.stderr.transform(utf8.decoder).join();
      final exitCodeFuture = started.exitCode;
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      final exitCode = await exitCodeFuture;
      if (exitCode != 0) {
        return _critical(
          'System Git',
          'System Git failed `git --version` with exit code $exitCode'
              '${stderr.trim().isEmpty ? '.' : ': ${stderr.trim()}.'}',
          nextStep: 'Install a working Git executable and retry.',
        );
      }
      return _ok(
        'System Git',
        stdout.trim().isEmpty
            ? 'System Git is available.'
            : '${stdout.trim()} is available.',
      );
    }, onTimeout: () => process?.kill(io.ProcessSignal.sigkill));
  }

  DoctorSetupCheck _ok(String component, String summary) => DoctorSetupCheck(
    component: component,
    severity: DoctorCheckSeverity.ok,
    summary: summary,
  );

  DoctorSetupCheck _informational(
    String component,
    String summary, {
    String? nextStep,
  }) => DoctorSetupCheck(
    component: component,
    severity: DoctorCheckSeverity.informational,
    summary: summary,
    nextStep: nextStep,
  );

  DoctorSetupCheck _critical(
    String component,
    String summary, {
    String? nextStep,
  }) => DoctorSetupCheck(
    component: component,
    severity: DoctorCheckSeverity.critical,
    summary: summary,
    nextStep: nextStep,
  );

  DoctorSetupCheck _incomplete(
    String component,
    String summary, {
    String? nextStep,
  }) => DoctorSetupCheck(
    component: component,
    severity: DoctorCheckSeverity.incomplete,
    summary: summary,
    nextStep: nextStep,
  );
}
