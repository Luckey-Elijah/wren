import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wren/wren.dart';

void main() {
  group('release selection', () {
    late Directory temporaryDirectory;
    late Directory projectDirectory;
    late Directory dataDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'wren-select-',
      );
      projectDirectory = Directory('${temporaryDirectory.path}/project')
        ..createSync();
      dataDirectory = Directory('${temporaryDirectory.path}/data')
        ..createSync();
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    Future<(int, String?)> runFlutter({
      required List<InstalledRelease> installed,
      String? fallback,
    }) async {
      String? selected;
      final status = await runWren(
        ['flutter'],
        host: HostPlatform.linuxX64,
        installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
        projectDirectory: projectDirectory,
        installedReleases: installed,
        globalFallback: fallback,
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
        sdkLauncher:
            ({
              required release,
              required executable,
              required arguments,
            }) async {
              selected = release;
              return 0;
            },
      );
      return (status, selected);
    }

    test('chooses newest stable release satisfying both constraints', () async {
      await File('${projectDirectory.path}/pubspec.yaml').writeAsString('''
environment:
  flutter: ">=3.45.0 <3.50.0"
  sdk: ">=3.12.0 <3.14.0"
''');

      final (status, selected) = await runFlutter(
        installed: [
          _installed('3.47.8'),
          _installed('3.49.0', dartVersion: '3.14.0'),
          _installed('3.46.0', dartVersion: '3.12.0'),
        ],
      );

      expect(status, 0);
      expect(selected, '3.47.8');
    });

    test('beta needs prerelease constraints for Flutter and Dart', () async {
      await File('${projectDirectory.path}/pubspec.yaml').writeAsString('''
environment:
  flutter: "^3.50.0-0.2.pre"
  sdk: "^3.14.0-315.3.beta"
''');

      final (betaStatus, selected) = await runFlutter(
        installed: [
          _installed(
            '3.50.0-0.2.pre',
            channel: 'beta',
            dartVersion: '3.14.0-315.3.beta',
          ),
        ],
      );
      expect(betaStatus, 0);
      expect(selected, '3.50.0-0.2.pre');

      await File('${projectDirectory.path}/pubspec.yaml').writeAsString('''
environment:
  flutter: ">=3.50.0"
  sdk: ">=3.14.0"
''');
      final (stableStatus, stableSelected) = await runFlutter(
        fallback: '3.47.8',
        installed: [
          _installed(
            '3.50.0-0.2.pre',
            channel: 'beta',
            dartVersion: '3.14.0-315.3.beta',
          ),
        ],
      );
      expect(stableStatus, 0);
      expect(stableSelected, '3.47.8');
    });

    test('missing or malformed constraints use the global fallback', () async {
      final installed = [_installed('3.47.8')];
      expect(
        (await runFlutter(fallback: '3.46.0', installed: installed)).$2,
        '3.46.0',
      );

      await File('${projectDirectory.path}/pubspec.yaml').writeAsString('''
environment: [malformed
''');
      expect(
        (await runFlutter(fallback: '3.46.0', installed: installed)).$2,
        '3.46.0',
      );

      await File('${projectDirectory.path}/pubspec.yaml').writeAsString('''
environment:
  flutter: ">=3.0.0"
''');
      expect(
        (await runFlutter(fallback: '3.46.0', installed: installed)).$2,
        '3.46.0',
      );
    });

    test(
      'reads the persisted global fallback after project mismatch',
      () async {
        await File('${projectDirectory.path}/pubspec.yaml').writeAsString('''
environment:
  flutter: "^3.50.0"
  sdk: "^3.14.0"
''');
        await File('${dataDirectory.path}/config.json')
            .writeAsString(jsonEncode({'globalFallback': '3.47.8'}));

        final (status, selected) = await runFlutter(
          installed: [_installed('3.47.8')],
        );
        expect(status, 0);
        expect(selected, '3.47.8');
      },
    );

    test('does not discover a parent directory pubspec', () async {
      final parent = projectDirectory.parent;
      await File('${parent.path}/pubspec.yaml').writeAsString('''
environment:
  flutter: "^3.47.0"
  sdk: "^3.13.0"
''');

      final (status, selected) = await runFlutter(
        fallback: '3.46.0',
        installed: [_installed('3.47.8')],
      );
      expect(status, 0);
      expect(selected, '3.46.0');
    });
  });

  group('set and use', () {
    late Directory temporaryDirectory;
    late Directory projectDirectory;
    late Directory dataDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('wren-set-');
      projectDirectory = Directory('${temporaryDirectory.path}/project')
        ..createSync();
      dataDirectory = Directory('${temporaryDirectory.path}/data')
        ..createSync();
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    Future<int> runSet(
      List<String> arguments, {
      StringSink? stdout,
      StringSink? stderr,
      List<InstalledRelease>? installed,
      WrenConfirmation? confirmation,
      String? fallback,
    }) => runWren(
      arguments,
      host: HostPlatform.linuxX64,
      installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
      projectDirectory: projectDirectory,
      installedReleases: installed ?? [_installed('3.47.8')],
      confirmation: confirmation,
      globalFallback: fallback,
      stdoutSink: stdout ?? StringBuffer(),
      stderrSink: stderr ?? StringBuffer(),
    );

    test(
      'rewrites existing keys, preserves other YAML and reports active pick',
      () async {
        final pubspec = File('${projectDirectory.path}/pubspec.yaml');
        await pubspec.writeAsString('''
name: example
environment:
  flutter: ">=3.0.0 <4.0.0" # old Flutter range
  sdk: ">=3.13.0 <4.0.0"
dependencies:
  path: ^1.9.0
''');
        final output = StringBuffer();

        final status = await runSet(
          ['set', '3.47.8'],
          stdout: output,
          installed: [
            _installed('3.47.8'),
            _installed('3.48.0', dartVersion: '3.13.8'),
          ],
        );

        expect(status, 0);
        final updated = await pubspec.readAsString();
        expect(updated, contains('flutter: ^3.47.8 # old Flutter range'));
        expect(updated, contains('sdk: ^3.13.7'));
        expect(updated, contains('dependencies:\n  path: ^1.9.0'));
        expect(output.toString(), contains('>=3.0.0 <4.0.0 → ^3.47.8'));
        expect(
          output.toString(),
          contains('Active Flutter release under normal selection: 3.48.0.'),
        );
        expect(File('${dataDirectory.path}/config.json').existsSync(), isFalse);
      },
    );

    test(
      'use alias updates only present keys and normalizes prerelease Dart',
      () async {
        final pubspec = File('${projectDirectory.path}/pubspec.yaml');
        await pubspec.writeAsString('''
environment:
  sdk: ">=3.14.0 <4.0.0"
''');
        final output = StringBuffer();

        final status = await runSet(
          ['use', '3.50.0-0.2.pre'],
          stdout: output,
          installed: [
            _installed(
              '3.50.0-0.2.pre',
              channel: 'beta',
              dartVersion: '3.14.0-315.3.beta',
            ),
          ],
        );

        expect(status, 0);
        final updated = await pubspec.readAsString();
        expect(updated, isNot(contains('flutter:')));
        expect(updated, contains('sdk: ^3.14.0-315.3.beta'));
        expect(output.toString(), contains('Updated environment.sdk'));
      },
    );

    test(
      'declining a Dart language change leaves pubspec and fallback alone',
      () async {
        final pubspec = File('${projectDirectory.path}/pubspec.yaml')
          ..writeAsStringSync('''
environment:
  flutter: ^3.0.0
  sdk: ^2.19.0
''');
        final original = pubspec.readAsStringSync();
        final stderr = StringBuffer();

        final status = await runSet(
          ['set', '-g', '3.47.8'],
          stderr: stderr,
          confirmation: (_) async => false,
        );

        expect(status, 6);
        expect(pubspec.readAsStringSync(), original);
        expect(File('${dataDirectory.path}/config.json').existsSync(), isFalse);
        expect(stderr.toString(), contains('cancelled; no changes were made'));
      },
    );

    test('unavailable confirmation leaves both scopes unchanged', () async {
      final pubspec = File('${projectDirectory.path}/pubspec.yaml')
        ..writeAsStringSync('environment:\n  sdk: ^2.19.0\n');
      final original = pubspec.readAsStringSync();
      final stderr = StringBuffer();

      final status = await runSet(
        ['set', '-g', '3.47.8'],
        stderr: stderr,
        confirmation: (_) async => null,
      );

      expect(status, 6);
      expect(pubspec.readAsStringSync(), original);
      expect(File('${dataDirectory.path}/config.json').existsSync(), isFalse);
      expect(stderr.toString(), contains('confirmation is unavailable'));
    });

    test('confirmed global set changes both pubspec and fallback', () async {
      final pubspec = File('${projectDirectory.path}/pubspec.yaml')
        ..writeAsStringSync('environment:\n  sdk: ^2.19.0\n');
      File('${dataDirectory.path}/config.json')
          .writeAsStringSync('{"someOtherPreference":true}');

      final status = await runSet([
        'set',
        '-g',
        '3.47.8',
      ], confirmation: (_) async => true);

      expect(status, 0);
      expect(pubspec.readAsStringSync(), contains('sdk: ^3.13.7'));
      expect(
        jsonDecode(
          File('${dataDirectory.path}/config.json').readAsStringSync(),
        ),
        {'someOtherPreference': true, 'globalFallback': '3.47.8'},
      );
    });

    test('invalid global config leaves the pubspec unchanged', () async {
      final pubspec = File('${projectDirectory.path}/pubspec.yaml')
        ..writeAsStringSync('environment:\n  sdk: ^2.19.0\n');
      final originalPubspec = pubspec.readAsStringSync();
      final config = File('${dataDirectory.path}/config.json')
        ..writeAsStringSync('{invalid json');
      final stderr = StringBuffer();

      final status = await runSet(
        ['set', '-g', '3.47.8'],
        confirmation: (_) async => true,
        stderr: stderr,
      );

      expect(status, 4);
      expect(pubspec.readAsStringSync(), originalPubspec);
      expect(config.readAsStringSync(), '{invalid json');
      expect(stderr.toString(), contains('command failed'));
    });

    test('global fallback can be set without a pubspec', () async {
      final status = await runSet(['use', '-g', '3.47.8']);

      expect(status, 0);
      expect(
        jsonDecode(
          File('${dataDirectory.path}/config.json').readAsStringSync(),
        ),
        {'globalFallback': '3.47.8'},
      );
    });

    test('ordinary set requires a current-directory pubspec', () async {
      final stderr = StringBuffer();

      final status = await runSet(['set', '3.47.8'], stderr: stderr);

      expect(status, 4);
      expect(stderr.toString(), contains('no pubspec.yaml'));
      expect(File('${dataDirectory.path}/config.json').existsSync(), isFalse);
    });
  });

  group('wren releases', () {
    test(
      'SDK commands suggest set or install when no release is selected',
      () async {
        final stderr = StringBuffer();

        final status = await runWren(
          ['flutter', '--version'],
          host: HostPlatform.linuxX64,
          stdoutSink: StringBuffer(),
          stderrSink: stderr,
        );

        expect(status, 3);
        expect(
          stderr.toString(),
          contains('No installed Flutter release matches this project'),
        );
        expect(stderr.toString(), contains('wren set <release>'));
        expect(stderr.toString(), contains('wren install'));
      },
    );

    test(
      'missing exact CLI selection does not fall back to environment',
      () async {
        final stderr = StringBuffer();

        final status = await runWren(
          ['--release', '9.9.9', 'flutter', '--version'],
          flutterReleaseOverride: '3.47.8',
          host: HostPlatform.linuxX64,
          stdoutSink: StringBuffer(),
          stderrSink: stderr,
        );

        expect(status, 3);
        expect(stderr.toString(), contains('Flutter 9.9.9 is not installed'));
      },
    );

    test(
      'lists eligible stable and beta releases from the host catalog',
      () async {
        final stdout = StringBuffer();
        final stderr = StringBuffer();

        final status = await runWren(
          ['releases'],
          catalogJson: jsonEncode({'releases': _fixtureReleases()}),
          host: HostPlatform.linuxX64,
          stdoutSink: stdout,
          stderrSink: stderr,
        );

        expect(status, 0);
        expect(stderr.toString(), isEmpty);
        expect(stdout.toString(), contains('3.47.8  stable  Dart 3.13.7'));
        expect(
          stdout.toString(),
          contains('3.50.0-0.2.pre  beta  Dart 3.14.0-315.3.beta'),
        );
        expect(stdout.toString(), isNot(contains('3.47.7')));
        expect(stdout.toString(), isNot(contains('3.48.0-0.1.pre')));
        expect(stdout.toString(), isNot(contains('3.46.0')));
      },
    );

    test('--verbose is accepted without changing regular output', () async {
      final normalOutput = StringBuffer();
      final verboseOutput = StringBuffer();
      final normalError = StringBuffer();
      final verboseError = StringBuffer();

      final normalStatus = await runWren(
        ['releases'],
        catalogJson: jsonEncode({
          'releases': [_release()],
        }),
        host: HostPlatform.linuxX64,
        stdoutSink: normalOutput,
        stderrSink: normalError,
      );
      final verboseStatus = await runWren(
        ['--verbose', 'releases'],
        catalogJson: jsonEncode({
          'releases': [_release()],
        }),
        host: HostPlatform.linuxX64,
        stdoutSink: verboseOutput,
        stderrSink: verboseError,
      );

      expect(normalStatus, 0);
      expect(verboseStatus, 0);
      expect(verboseOutput.toString(), normalOutput.toString());
      expect(verboseError.toString(), normalError.toString());
    });

    test('--verbose is accepted after a Wren command', () async {
      final plain = StringBuffer();
      final placedAfter = StringBuffer();

      final plainStatus = await runWren(
        ['releases'],
        catalogJson: jsonEncode({
          'releases': [_release()],
        }),
        host: HostPlatform.linuxX64,
        stdoutSink: plain,
        stderrSink: StringBuffer(),
      );
      final verboseStatus = await runWren(
        ['releases', '--verbose'],
        catalogJson: jsonEncode({
          'releases': [_release()],
        }),
        host: HostPlatform.linuxX64,
        stdoutSink: placedAfter,
        stderrSink: StringBuffer(),
      );

      expect(plainStatus, 0);
      expect(verboseStatus, 0);
      expect(placedAfter.toString(), plain.toString());
    });

    test('help uses the registered command tree', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      final status = await runWren(
        ['--help'],
        stdoutSink: stdout,
        stderrSink: stderr,
      );

      expect(status, 0);
      expect(stderr.toString(), isEmpty);
      expect(stdout.toString(), contains('releases'));
      expect(stdout.toString(), contains('install'));
      expect(stdout.toString(), contains('--verbose'));
    });

    test('missing command is a usage error', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      final status = await runWren([], stdoutSink: stdout, stderrSink: stderr);

      expect(status, 2);
      expect(stdout.toString(), isEmpty);
      expect(stderr.toString(), contains('a command is required'));
      expect(stderr.toString(), contains('Usage: wren'));

      final verboseOnlyStatus = await runWren(
        ['--verbose'],
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      );
      expect(verboseOnlyStatus, 2);
    });

    test(
      'checks an explicitly requested ineligible release with its reason',
      () async {
        final stderr = StringBuffer();

        final status = await runWren(
          ['releases', '3.47.7'],
          catalogJson: jsonEncode({'releases': _fixtureReleases()}),
          host: HostPlatform.linuxX64,
          stderrSink: stderr,
        );

        expect(status, 4);
        expect(
          stderr.toString(),
          contains('Flutter 3.47.7 is not eligible for Linux x86_64'),
        );
        expect(stderr.toString(), contains('bundled Dart version is missing'));
      },
    );

    test('lists a native macOS arm64 release', () async {
      final stdout = StringBuffer();

      final status = await runWren(
        ['releases'],
        catalogJson: jsonEncode({
          'releases': [
            _release(
              archive: 'stable/macos/flutter_macos_arm64_3.47.8-stable.zip',
              dartArchitecture: 'arm64',
            ),
          ],
        }),
        host: HostPlatform.macosArm64,
        stdoutSink: stdout,
      );

      expect(status, 0);
      expect(stdout.toString(), contains('3.47.8  stable  Dart 3.13.7'));
    });

    test('usage errors return status 2 without reading the catalog', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      final status = await runWren(
        ['releases', 'one', 'extra'],
        catalogJson: '',
        host: HostPlatform.linuxX64,
        stdoutSink: stdout,
        stderrSink: stderr,
      );

      expect(status, 2);
      expect(stdout.toString(), isEmpty);
      expect(stderr.toString(), contains('unexpected argument "extra"'));
      expect(stderr.toString(), contains('Usage: wren'));
    });

    test('catalog failures are actionable operation errors', () async {
      final stderr = StringBuffer();

      final status = await runWren(
        ['releases'],
        catalogJson: 'not valid json',
        host: HostPlatform.linuxX64,
        stderrSink: stderr,
      );

      expect(status, 4);
      expect(stderr.toString(), contains('not valid JSON'));
    });

    test('keeps an exclusion reason for an explicitly requested release', () {
      final catalog = ReleaseCatalog.parse(
        jsonEncode({'releases': _fixtureReleases()}),
        host: HostPlatform.linuxX64,
      );

      final unavailable = catalog.eligibilityForVersion('3.47.7');
      expect(unavailable.isEligible, isFalse);
      expect(
        unavailable.reason,
        contains('bundled Dart version is missing or unknown'),
      );
      expect(
        catalog.eligibilityForVersion('3.47.8').release!.version,
        '3.47.8',
      );
    });
  });

  group('release eligibility', () {
    test('uses full prerelease Dart version from build metadata', () {
      final result = ReleaseCatalog.eligibilityFor(
        _release(
          channel: 'beta',
          version: '3.50.0-0.2.pre',
          dartVersion: '3.14.0 (build 3.14.0-315.3.beta)',
          archive: 'beta/linux/flutter_linux_3.50.0-0.2.pre-beta.tar.xz',
        ),
        host: HostPlatform.linuxX64,
      );

      expect(result.isEligible, isTrue);
      expect(result.release!.dartVersion, '3.14.0-315.3.beta');
    });

    test('rejects a prerelease below 2.19.0 using full SemVer ordering', () {
      final result = ReleaseCatalog.eligibilityFor(
        _release(dartVersion: '2.19.0 (build 2.19.0-1.beta)'),
        host: HostPlatform.linuxX64,
      );

      expect(result.isEligible, isFalse);
      expect(result.reason, contains('below the minimum 2.19.0'));
    });

    test('rejects entries without known Dart metadata', () {
      final entry = _release()..remove('dart_sdk_version');

      final result = ReleaseCatalog.eligibilityFor(
        entry,
        host: HostPlatform.linuxX64,
      );

      expect(result.isEligible, isFalse);
      expect(
        result.reason,
        contains('bundled Dart version is missing or unknown'),
      );
    });

    test(
      'rejects an unsupported host architecture instead of using Rosetta',
      () {
        final result = ReleaseCatalog.eligibilityFor(
          _release(
            archive: 'stable/macos/flutter_macos_arm64_3.47.8-stable.zip',
          ),
          host: HostPlatform.macosArm64,
        );

        expect(result.isEligible, isFalse);
        expect(result.reason, contains('not native arm64'));
      },
    );

    test('rejects an artifact for another operating system', () {
      final result = ReleaseCatalog.eligibilityFor(
        _release(
          archive: 'stable/macos/flutter_macos_arm64_3.47.8-stable.zip',
          dartArchitecture: 'arm64',
        ),
        host: HostPlatform.linuxX64,
      );

      expect(result.isEligible, isFalse);
      expect(result.reason, contains('no native Linux x86_64 artifact'));
    });
  });
  group('wren setup', () {
    late Directory temporaryDirectory;
    late Directory dataDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('wren-setup-');
      dataDirectory = Directory('${temporaryDirectory.path}/data')
        ..createSync();
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    test(
      'installs executable forwarding shims and prints editor guidance',
      () async {
        final childArguments = File(
          '${temporaryDirectory.path}/child-args.txt',
        );
        final child = File('${temporaryDirectory.path}/sdk-child');
        await child.writeAsString('''
#!/bin/sh
printf '%s\\n' "\$@" > '${childArguments.path}'
printf 'sdk stdout\n'
printf 'sdk stderr\n' >&2
exit 23
''');
        expect((await Process.run('chmod', ['+x', child.path])).exitCode, 0);

        final wrenExecutable = File('${temporaryDirectory.path}/wren-fixture');
        final selectedRelease = File(
          '${temporaryDirectory.path}/selected-release.txt',
        );
        await wrenExecutable.writeAsString('''
#!/bin/sh
if [ "\$1" != flutter ] && [ "\$1" != dart ]; then exit 90; fi
selected="\$WREN_FLUTTER_RELEASE"
if [ -z "\$selected" ]; then selected=active; fi
printf '%s\\n' "\$selected" > '${selectedRelease.path}'
shift
exec '${child.path}' "\$@"
''');
        expect(
          (await Process.run('chmod', ['+x', wrenExecutable.path])).exitCode,
          0,
        );

        final vscodeDirectory = Directory(
          '${temporaryDirectory.path}/project/.vscode',
        )..createSync(recursive: true);
        final settings = File('${vscodeDirectory.path}/settings.json')
          ..writeAsStringSync(r'{"existing": true}\n');
        final output = StringBuffer();
        final status = await runWren(
          ['setup'],
          installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
          wrenExecutable: wrenExecutable.path,
          stdoutSink: output,
          stderrSink: StringBuffer(),
        );

        expect(status, 0);
        final flutterShim = File('${dataDirectory.path}/bin/flutter');
        final dartShim = File('${dataDirectory.path}/bin/dart');
        expect(flutterShim.existsSync(), isTrue);
        expect(dartShim.existsSync(), isTrue);
        expect(
          await flutterShim.readAsString(),
          contains("'${wrenExecutable.path}' flutter"),
        );
        expect(
          await dartShim.readAsString(),
          contains("'${wrenExecutable.path}' dart"),
        );
        expect(
          (await Process.run('test', ['-x', flutterShim.path])).exitCode,
          0,
        );
        expect(output.toString(), contains('PATH'));
        expect(output.toString(), contains('dart.getFlutterSdkCommand'));
        expect(output.toString(), contains('"executable": "wren"'));
        expect(output.toString(), contains('"args": ["sdk-path"]'));
        expect(output.toString(), contains('wren sdk-path <release>'));
        expect(output.toString(), contains('Reload'));
        expect(await settings.readAsString(), r'{"existing": true}\n');

        final result = await Process.run(flutterShim.path, [
          '--version',
          'argument with spaces',
        ]);
        expect(result.exitCode, 23);
        expect(result.stdout, 'sdk stdout\n');
        expect(result.stderr, 'sdk stderr\n');
        expect(await childArguments.readAsLines(), [
          '--version',
          'argument with spaces',
        ]);
        expect(await selectedRelease.readAsString(), 'active\n');

        final exactResult = await Process.run(
          dartShim.path,
          ['--version'],
          environment: {'WREN_FLUTTER_RELEASE': '3.47.8'},
        );
        expect(exactResult.exitCode, 23);
        expect(await selectedRelease.readAsString(), '3.47.8\n');
      },
    );
  });

  group('remove', () {
    late Directory temporaryDirectory;
    late Directory dataDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'wren-remove-',
      );
      dataDirectory = Directory('${temporaryDirectory.path}/data')
        ..createSync();
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    Future<Directory> addRelease({bool externalUse = false}) async {
      final directory = Directory(
        '${dataDirectory.path}/releases/stable-3.47.8-linux-x64',
      )..createSync(recursive: true);
      await File('${directory.path}/.wren-release.json').writeAsString(
        jsonEncode({
          'channel': 'stable',
          'version': '3.47.8',
          'host': 'linux',
          'architecture': 'x64',
          'state': 'ready',
          'externalUse': externalUse,
        }),
      );
      return directory;
    }

    test('removes an active fallback and leaves pubspec unchanged', () async {
      final release = await addRelease();
      const sourceKey = 'unused-engine-linux-x64';
      final releaseMarker = File('${release.path}/.wren-release.json');
      final releaseData =
          jsonDecode(releaseMarker.readAsStringSync()) as Map<String, Object?>;
      releaseData['sourceKey'] = sourceKey;
      await releaseMarker.writeAsString(jsonEncode(releaseData));
      final source = Directory('${dataDirectory.path}/sources/$sourceKey')
        ..createSync(recursive: true);
      final project = Directory('${temporaryDirectory.path}/project')
        ..createSync();
      final pubspec = File('${project.path}/pubspec.yaml')
        ..writeAsStringSync('environment:\n  flutter: ^3.47.8\n');
      final originalPubspec = pubspec.readAsStringSync();
      final config = File('${dataDirectory.path}/config.json')
        ..writeAsStringSync('{"globalFallback":"3.47.8"}');
      final output = StringBuffer();
      final status = await runWren(
        ['remove', '3.47.8'],
        host: HostPlatform.linuxX64,
        installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
        projectDirectory: project,
        stdoutSink: output,
        stderrSink: StringBuffer(),
      );

      expect(status, 0);
      expect(release.existsSync(), isFalse);
      expect(source.existsSync(), isFalse);
      expect(pubspec.readAsStringSync(), originalPubspec);
      expect(config.existsSync(), isFalse);
      expect(output.toString(), contains('No release is active'));
    });

    test(
      'external-use cancellation returns 6 without changing files',
      () async {
        final release = await addRelease(externalUse: true);
        var prompted = false;
        final status = await runWren(
          ['remove', '3.47.8'],
          host: HostPlatform.linuxX64,
          installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
          confirmation: (message) async {
            prompted = message.contains('Close editors');
            return false;
          },
          stdoutSink: StringBuffer(),
          stderrSink: StringBuffer(),
        );

        expect(status, 6);
        expect(prompted, isTrue);
        expect(release.existsSync(), isTrue);
        final manifest = jsonDecode(
          File('${release.path}/.wren-release.json').readAsStringSync(),
        ) as Map<String, Object?>;
        expect(manifest['state'], 'ready');
      },
    );

    test(
      'waits for a Wren-launched SDK lease before deleting the release',
      () async {
        final release = await addRelease();
        final leaseDirectory = Directory(
          '${dataDirectory.path}/leases/stable-3.47.8-linux-x64',
        )..createSync(recursive: true);
        final lease = File('${leaseDirectory.path}/active')
          ..writeAsStringSync('$pid\n');
        final output = StringBuffer();
        final errors = StringBuffer();
        final removal = runWren(
          ['remove', '3.47.8'],
          host: HostPlatform.linuxX64,
          installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
          stdoutSink: output,
          stderrSink: errors,
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(release.existsSync(), isTrue);
        await lease.delete();
        expect(await removal, 0);
        expect(release.existsSync(), isFalse);
        expect(errors.toString(), contains('finish running'));
      },
    );

    test(
      'keeps a source still referenced by another installed release',
      () async {
        final release = await addRelease();
        final other = Directory(
          '${dataDirectory.path}/releases/stable-3.46.0-linux-x64',
        )..createSync(recursive: true);
        await File('${other.path}/.wren-release.json').writeAsString(
          jsonEncode({
            'channel': 'stable',
            'version': '3.46.0',
            'host': 'linux',
            'architecture': 'x64',
            'state': 'ready',
            'sourceKey': 'shared-engine-linux-x64',
          }),
        );
        const sourceKey = 'shared-engine-linux-x64';
        for (final installation in [release, other]) {
          final marker = File('${installation.path}/.wren-release.json');
          final manifest =
              jsonDecode(marker.readAsStringSync()) as Map<String, Object?>;
          manifest['sourceKey'] = sourceKey;
          await marker.writeAsString(jsonEncode(manifest));
        }
        final source = Directory('${dataDirectory.path}/sources/$sourceKey')
          ..createSync(recursive: true);
        final status = await runWren(
          ['remove', '3.47.8'],
          host: HostPlatform.linuxX64,
          installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
          stdoutSink: StringBuffer(),
          stderrSink: StringBuffer(),
        );

        expect(status, 0);
        expect(release.existsSync(), isFalse);
        expect(other.existsSync(), isTrue);
        expect(source.existsSync(), isTrue);
      },
    );

    test('retries cleanup from an unavailable removal record', () async {
      const releaseKey = 'stable-3.47.8-linux-x64';
      const sourceKey = 'orphaned-engine-linux-x64';
      final source = Directory('${dataDirectory.path}/sources/$sourceKey')
        ..createSync(recursive: true);
      final journal = File('${dataDirectory.path}/removals/$releaseKey.json')
        ..createSync(recursive: true);
      await journal.writeAsString(
        jsonEncode({
          'channel': 'stable',
          'version': '3.47.8',
          'host': 'linux',
          'architecture': 'x64',
          'state': 'removing',
          'sourceKey': sourceKey,
          'releaseKey': releaseKey,
        }),
      );

      final status = await runWren(
        ['remove', '3.47.8'],
        host: HostPlatform.linuxX64,
        installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      );

      expect(status, 0);
      expect(source.existsSync(), isFalse);
      expect(journal.existsSync(), isFalse);
    });

    test(
      'declining final shared repository deletion keeps the repository',
      () async {
        await addRelease();
        final repository = Directory('${dataDirectory.path}/flutter.git')
          ..createSync();
        var prompted = false;
        final status = await runWren(
          ['remove', '3.47.8'],
          host: HostPlatform.linuxX64,
          installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
          confirmation: (message) async {
            prompted = message.contains('final installed');
            return false;
          },
          stdoutSink: StringBuffer(),
          stderrSink: StringBuffer(),
        );

        expect(status, 0);
        expect(prompted, isTrue);
        expect(repository.existsSync(), isTrue);
      },
    );

    test('requires one release argument', () async {
      expect(
        await runWren(
          ['remove'],
          stdoutSink: StringBuffer(),
          stderrSink: StringBuffer(),
        ),
        2,
      );
    });
  });

  group('cleanup', () {
    late Directory temporaryDirectory;
    late Directory dataDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'wren-cleanup-',
      );
      dataDirectory = Directory('${temporaryDirectory.path}/data')
        ..createSync();
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    test('dry-run previews only orphaned stages and sources', () async {
      const stageName = 'install-stable-3.47.8-linux-x64';
      final sourceRepairStageName =
          'repair-stable-3.47.8-linux-x64-'
          '${List.filled(32, 'a').join()}';
      final privateRepairStageName =
          'repair-private-stable-3.47.8-linux-x64-'
          '${List.filled(32, 'b').join()}';
      const unknownStageName = 'repair-stable-3.47.8-linux-x64-incomplete';
      final stage = Directory('${dataDirectory.path}/staging/$stageName')
        ..createSync(recursive: true);
      final sourceRepairStage = Directory(
        '${dataDirectory.path}/staging/$sourceRepairStageName',
      )..createSync(recursive: true);
      final privateRepairStage = Directory(
        '${dataDirectory.path}/staging/$privateRepairStageName',
      )..createSync(recursive: true);
      final unknownStage = Directory(
        '${dataDirectory.path}/staging/$unknownStageName',
      )..createSync(recursive: true);
      final source = Directory('${dataDirectory.path}/sources/orphan-engine')
        ..createSync(recursive: true);
      final retained = Directory(
        '${dataDirectory.path}/sources/retained-engine',
      )..createSync(recursive: true);
      final release = Directory(
        '${dataDirectory.path}/releases/stable-3.47.8-linux-x64',
      )..createSync(recursive: true);
      await File('${release.path}/.wren-release.json').writeAsString(
        jsonEncode({'state': 'needsRepair', 'sourceKey': 'retained-engine'}),
      );
      final repository = Directory('${dataDirectory.path}/flutter.git')
        ..createSync();
      final rollback = File('${dataDirectory.path}/wren.previous')
        ..writeAsStringSync('rollback');
      final output = StringBuffer();
      final status = await runWren(
        ['cleanup', '--dry-run'],
        installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
        stdoutSink: output,
        stderrSink: StringBuffer(),
      );

      expect(status, 0);
      expect(stage.existsSync(), isTrue);
      expect(sourceRepairStage.existsSync(), isTrue);
      expect(privateRepairStage.existsSync(), isTrue);
      expect(unknownStage.existsSync(), isTrue);
      expect(source.existsSync(), isTrue);
      expect(retained.existsSync(), isTrue);
      expect(repository.existsSync(), isTrue);
      expect(rollback.readAsStringSync(), 'rollback');
      expect(
        output.toString(),
        contains('Would reclaim orphaned stage: $stageName'),
      );
      expect(
        output.toString(),
        contains('Would reclaim orphaned stage: $sourceRepairStageName'),
      );
      expect(
        output.toString(),
        contains('Would reclaim orphaned stage: $privateRepairStageName'),
      );
      expect(output.toString(), isNot(contains(unknownStageName)));
      expect(
        output.toString(),
        contains('Would reclaim unreferenced shared source: orphan-engine'),
      );
      expect(output.toString(), isNot(contains('retained-engine')));
    });

    test(
      'reclaims crash orphans and preserves referenced recovery data',
      () async {
        const stageName = 'install-stable-3.47.8-linux-x64';
        const repairStageName =
            'repair-stable-3.47.8-linux-x64-cccccccccccccccccccccccccccccccc';
        final stage = Directory('${dataDirectory.path}/staging/$stageName')
          ..createSync(recursive: true);
        final repairStage = Directory(
          '${dataDirectory.path}/staging/$repairStageName',
        )..createSync(recursive: true);
        final source = Directory('${dataDirectory.path}/sources/orphan-engine')
          ..createSync(recursive: true);
        final retained = Directory(
          '${dataDirectory.path}/sources/recovery-engine',
        )..createSync(recursive: true);
        final journal = File('${dataDirectory.path}/removals/release.json')
          ..createSync(recursive: true);
        await journal.writeAsString(
          jsonEncode({'sourceKey': 'recovery-engine'}),
        );
        final repository = Directory('${dataDirectory.path}/flutter.git')
          ..createSync();
        final rollback = File('${dataDirectory.path}/wren.previous')
          ..writeAsStringSync('rollback');
        final output = StringBuffer();
        final status = await runWren(
          ['cleanup'],
          installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
          stdoutSink: output,
          stderrSink: StringBuffer(),
        );

        expect(status, 0);
        expect(stage.existsSync(), isFalse);
        expect(repairStage.existsSync(), isFalse);
        expect(source.existsSync(), isFalse);
        expect(retained.existsSync(), isTrue);
        expect(repository.existsSync(), isTrue);
        expect(rollback.readAsStringSync(), 'rollback');
        expect(
          output.toString(),
          contains('Reclaimed orphaned stage: $stageName'),
        );
        expect(
          output.toString(),
          contains('Reclaimed orphaned stage: $repairStageName'),
        );
        expect(
          output.toString(),
          contains('Reclaimed unreferenced shared source: orphan-engine'),
        );
      },
    );

    test(
      'cancelling a required wait returns 6 and leaves the stage intact',
      () async {
        const stageName = 'install-stable-3.47.8-linux-x64';
        final stage = Directory('${dataDirectory.path}/staging/$stageName')
          ..createSync(recursive: true);
        final releaseKey = stageName.substring('install-'.length);
        final lock = Directory(
          '${dataDirectory.path}/locks/install-$releaseKey',
        )..createSync(recursive: true);
        File('${lock.path}/owner').writeAsStringSync('$pid\n');
        final cancellation = StreamController<void>();
        final errors = StringBuffer();
        final cleanup = runWren(
          ['cleanup'],
          installEnvironment: InstallEnvironment(
            dataDirectory: dataDirectory,
            waitCancellation: cancellation.stream,
          ),
          stdoutSink: StringBuffer(),
          stderrSink: errors,
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        cancellation.add(null);

        expect(await cleanup, 6);
        expect(stage.existsSync(), isTrue);
        expect(errors.toString(), contains('cancelled while waiting'));
        await cancellation.close();
      },
    );

    test('waits for active source and private repair stages', () async {
      const releaseKey = 'stable-3.47.8-linux-x64';
      final stageNames = [
        'repair-$releaseKey-${List.filled(32, 'd').join()}',
        'repair-private-$releaseKey-${List.filled(32, 'e').join()}',
      ];

      for (final stageName in stageNames) {
        final stage = Directory('${dataDirectory.path}/staging/$stageName')
          ..createSync(recursive: true);
        final lock = Directory(
          '${dataDirectory.path}/locks/install-$releaseKey',
        )..createSync(recursive: true);
        File('${lock.path}/owner').writeAsStringSync('$pid\n');
        final cancellation = StreamController<void>();
        final errors = StringBuffer();
        final cleanup = runWren(
          ['cleanup'],
          installEnvironment: InstallEnvironment(
            dataDirectory: dataDirectory,
            waitCancellation: cancellation.stream,
          ),
          stdoutSink: StringBuffer(),
          stderrSink: errors,
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        cancellation.add(null);

        expect(await cleanup, 6);
        expect(stage.existsSync(), isTrue);
        expect(
          errors.toString(),
          contains('Waiting for active work on stage $stageName'),
        );
        await cancellation.close();
        await lock.delete(recursive: true);
        await stage.delete(recursive: true);
      }
    });

    test('waits for an active source operation before reclaiming it', () async {
      const sourceKey = 'active-engine';
      final source = Directory('${dataDirectory.path}/sources/$sourceKey')
        ..createSync(recursive: true);
      final lock = Directory('${dataDirectory.path}/locks/source-$sourceKey')
        ..createSync(recursive: true);
      File('${lock.path}/owner').writeAsStringSync('$pid\n');
      final cancellation = StreamController<void>();
      final errors = StringBuffer();
      final cleanup = runWren(
        ['cleanup'],
        installEnvironment: InstallEnvironment(
          dataDirectory: dataDirectory,
          waitCancellation: cancellation.stream,
        ),
        stdoutSink: StringBuffer(),
        stderrSink: errors,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      cancellation.add(null);

      expect(await cleanup, 6);
      expect(source.existsSync(), isTrue);
      expect(
        errors.toString(),
        contains('Waiting for shared source $sourceKey'),
      );
      await cancellation.close();
    });

    test('rejects positional arguments', () async {
      expect(
        await runWren(
          ['cleanup', 'extra'],
          stdoutSink: StringBuffer(),
          stderrSink: StringBuffer(),
        ),
        2,
      );
    });
  });

  group('performance tracing', () {
    late Directory temporaryDirectory;
    late Directory dataDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('wren-trace-');
      dataDirectory = Directory('${temporaryDirectory.path}/data')
        ..createSync();
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    Future<List<Map<String, Object?>>> readRecords(File file) async =>
        (await file.readAsLines())
            .where((line) => line.isNotEmpty)
            .map((line) => jsonDecode(line) as Map<String, Object?>)
            .toList();

    test('tracing is disabled unless explicitly requested', () async {
      final status = await runWren(
        ['list'],
        host: HostPlatform.linuxX64,
        installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
        installedReleases: const [],
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      );

      expect(status, 0);
      expect(Directory('${dataDirectory.path}/traces').existsSync(), isFalse);
    });

    test('default path is unique and contains a UTC timestamp', () async {
      for (var index = 0; index < 2; index++) {
        expect(
          await runWren(
            ['--trace', 'list'],
            host: HostPlatform.linuxX64,
            installEnvironment: InstallEnvironment(
              dataDirectory: dataDirectory,
            ),
            installedReleases: const [],
            stdoutSink: StringBuffer(),
            stderrSink: StringBuffer(),
          ),
          0,
        );
      }

      final files = Directory('${dataDirectory.path}/traces')
          .listSync()
          .whereType<File>()
          .toList();
      expect(files, hasLength(2));
      expect(
        files.map((file) => p.basename(file.path)),
        everyElement(
          matches(RegExp(r'^wren-\d{8}T\d{9}Z-[0-9a-f]{16}\.jsonl$')),
        ),
      );
      for (final file in files) {
        final records = await readRecords(file);
        expect(records.map((record) => record['recordType']), [
          'span',
          'span',
          'span',
          'run',
        ]);
        expect(records.map((record) => record['runId']).toSet(), hasLength(1));
        expect(records.last['command'], 'list');
        expect(records.last['host'], 'Linux x86_64');
        expect(records.last['wrenVersion'], '1.0.0');
        expect(records.last['exitStatus'], 0);
        expect(records.last['startedAt'], isA<String>());
        expect(records.last['durationMicros'], greaterThanOrEqualTo(0));
        expect(records[0]['name'], 'cli.startup');
        expect(records[1]['name'], 'release.list_installed');
        expect(records[2]['name'], 'cli.dispatch');
        expect(records[1]['parentSpanId'], records[2]['spanId']);
      }
      expect(files[0].path, isNot(files[1].path));
    });

    test('explicit relative path appends versioned JSONL runs', () async {
      final traceFile = File('${temporaryDirectory.path}/nested/custom.data');
      await traceFile.parent.create(recursive: true);
      await traceFile.writeAsString('{"previous":true}\n');
      final relativePath = p.relative(
        traceFile.path,
        from: Directory.current.path,
      );

      for (var index = 0; index < 2; index++) {
        expect(
          await runWren(
            ['--trace=$relativePath', 'list'],
            host: HostPlatform.linuxX64,
            installEnvironment: InstallEnvironment(
              dataDirectory: dataDirectory,
            ),
            installedReleases: const [],
            stdoutSink: StringBuffer(),
            stderrSink: StringBuffer(),
          ),
          0,
        );
      }

      final records = await readRecords(traceFile);
      expect(records.first, {'previous': true});
      expect(
        records.where((record) => record['recordType'] == 'run'),
        hasLength(2),
      );
      expect(
        records
            .where((record) => record['recordType'] == 'run')
            .map((record) => record['runId'])
            .toSet(),
        hasLength(2),
      );
    });

    test(
      'child process timing and status are recorded without arguments',
      () async {
        final traceFile = File('${temporaryDirectory.path}/child.jsonl');
        List<String>? childArguments;
        final status = await runWren(
          ['--trace=${traceFile.path}', 'flutter', '--password=sensitive'],
          host: HostPlatform.linuxX64,
          installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
          flutterReleaseOverride: '3.47.8',
          installedReleases: [_installed('3.47.8')],
          stdoutSink: StringBuffer(),
          stderrSink: StringBuffer(),
          sdkLauncher:
              ({
                required release,
                required executable,
                required arguments,
              }) async {
                childArguments = arguments;
                await Future<void>.delayed(const Duration(milliseconds: 20));
                return 13;
              },
        );

        expect(status, 13);
        expect(childArguments, ['--password=sensitive']);
        final contents = await traceFile.readAsString();
        expect(contents, isNot(contains('sensitive')));
        final records = await readRecords(traceFile);
        final childSpan = records.singleWhere(
          (record) => record['name'] == 'sdk.child_process',
        );
        expect(childSpan['durationMicros'], greaterThan(0));
        expect(childSpan['result'], 'failure');
        expect(records.last['exitStatus'], 13);
        expect(records.last.keys, isNot(contains('arguments')));
      },
    );

    test(
      'unopenable trace destination prevents the command from running',
      () async {
        final parentFile = File('${temporaryDirectory.path}/not-a-directory')
          ..writeAsStringSync('file');
        var launched = false;
        final errors = StringBuffer();
        final status = await runWren(
          ['--trace=${parentFile.path}/trace.jsonl', 'flutter'],
          host: HostPlatform.linuxX64,
          installEnvironment: InstallEnvironment(dataDirectory: dataDirectory),
          stdoutSink: StringBuffer(),
          stderrSink: errors,
          sdkLauncher:
              ({
                required release,
                required executable,
                required arguments,
              }) async {
                launched = true;
                return 0;
              },
        );

        expect(status, 4);
        expect(launched, isFalse);
        expect(errors.toString(), contains('could not open trace file'));
      },
    );
  });
}

List<Map<String, Object?>> _fixtureReleases() => [
  _release(),
  _release(
    channel: 'beta',
    version: '3.50.0-0.2.pre',
    dartVersion: '3.14.0 (build 3.14.0-315.3.beta)',
    archive: 'beta/linux/flutter_linux_3.50.0-0.2.pre-beta.tar.xz',
  ),
  _release(version: '3.47.7', dartVersion: 'unknown'),
  _release(
    channel: 'beta',
    version: '3.48.0-0.1.pre',
    dartVersion: '2.18.0 (build 2.18.0-12.beta)',
    archive: 'beta/linux/flutter_linux_3.48.0-0.1.pre-beta.tar.xz',
  ),
  _release(
    version: '3.46.0',
    archive: 'stable/linux/flutter_linux_arm64_3.46.0-stable.tar.xz',
    dartArchitecture: 'arm64',
  ),
];

InstalledRelease _installed(
  String version, {
  String channel = 'stable',
  String dartVersion = '3.13.7',
  String host = 'linux',
  bool needsRepair = false,
}) => InstalledRelease(
  channel: channel,
  version: version,
  host: host,
  dartVersion: dartVersion,
  needsRepair: needsRepair,
);

Map<String, Object?> _release({
  String channel = 'stable',
  String version = '3.47.8',
  String dartVersion = '3.13.7',
  String archive = 'stable/linux/flutter_linux_3.47.8-stable.tar.xz',
  String dartArchitecture = 'x64',
}) => {
  'channel': channel,
  'version': version,
  'dart_sdk_version': dartVersion,
  'dart_sdk_arch': dartArchitecture,
  'hash': '737ba8f885dc774b53b442759999a312c9461e4e',
  'archive': archive,
  'sha256': 'baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2',
};
