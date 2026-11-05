import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wren/wren.dart';

void main() {
  late Directory temp;
  late Directory data;
  late Directory project;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wren-targeted-doctor-');
    data = Directory(p.join(temp.path, 'data'))..createSync();
    project = Directory(p.join(temp.path, 'project'))..createSync();
  });
  tearDown(() => temp.delete(recursive: true));

  Future<(int, String, String)> diagnose(
    List<String> arguments, {
    List<InstalledRelease>? installed,
    Stream<void>? cancellation,
    String? override,
  }) async {
    final output = StringBuffer();
    final errors = StringBuffer();
    final status = await runWren(
      arguments,
      host: HostPlatform.macosArm64,
      installEnvironment: InstallEnvironment(
        dataDirectory: data,
        waitCancellation: cancellation,
      ),
      projectDirectory: project,
      installedReleases: installed,
      flutterReleaseOverride: override,
      stdoutSink: output,
      stderrSink: errors,
    );
    return (status, output.toString(), errors.toString());
  }

  test(
    'targeted quick JSON keeps normal selection outside its scope',
    () async {
      await File(p.join(project.path, 'pubspec.yaml')).writeAsString('''
environment:
  flutter: ^3.27.0
  sdk: ^3.6.0
''');
      final (status, output, errors) = await diagnose(
        ['doctor', '3.27.4', '--json', '--verbose'],
        installed: [_release('3.27.4'), _release('3.29.3')],
      );
      expect(status, 0, reason: errors);
      final report = jsonDecode(output) as Map<String, Object?>;
      expect(report['scope'], {
        'kind': 'release',
        'requested_release': '3.27.4',
      });
      expect(report['releases'], [containsPair('version', '3.27.4')]);
      expect(report['selection'], containsPair('release', '3.29.3'));
      expect(report['selection'], containsPair('integrity', isNull));
      expect(report['selection'], containsPair('is_installed', true));
      expect(errors, contains('Setup Storage:'));
    },
  );

  test('target stays fixed despite an environment override', () async {
    final (status, output, errors) = await diagnose(
      ['doctor', '3.27.4', '--json'],
      installed: [_release('3.27.4'), _release('3.29.3')],
      override: '3.29.3',
    );
    expect(status, 0, reason: errors);
    final report = jsonDecode(output) as Map<String, Object?>;
    expect(report['releases'], [containsPair('version', '3.27.4')]);
    expect(report['selection'], containsPair('source', 'environment_override'));
    expect(report['project'], containsPair('pubspec_present', false));
  });

  test(
    'canonical prerelease target and damaged target remain diagnosable',
    () async {
      const version = '3.30.0-0.1.pre';
      final (status, output, errors) = await diagnose(
        ['doctor', version, '--json'],
        installed: [_release(version, needsRepair: true, channel: 'beta')],
      );
      expect(status, 1, reason: errors);
      final report = jsonDecode(output) as Map<String, Object?>;
      expect(report['releases'], [containsPair('integrity', 'needs_repair')]);
      expect(report['selection'], containsPair('release', isNull));
    },
  );

  test(
    'rejects aliases, ranges, noncanonical versions and extra targets',
    () async {
      for (final arguments in [
        ['stable'],
        ['^3.27.4'],
        ['3.27'],
        ['03.27.4'],
        ['v3.27.4'],
        ['3.27.4', '3.29.3'],
      ]) {
        final (status, output, errors) = await diagnose([
          'doctor',
          ...arguments,
          '--json',
        ], installed: const []);
        expect(status, 2, reason: errors);
        expect(output, isEmpty);
      }
    },
  );

  test(
    'missing installed target is a usage error with installation guidance',
    () async {
      final (status, output, errors) = await diagnose([
        'doctor',
        '9.99.99',
        '--json',
      ]);
      expect(status, 2, reason: errors);
      expect(output, isEmpty);
      expect(errors, contains('wren list'));
      expect(errors, contains('wren install 9.99.99'));
    },
  );

  test(
    'uninspectable registry preserves requested scope and setup findings',
    () async {
      await File(p.join(data.path, 'releases'))
          .writeAsString('not a directory');
      for (final full in [false, true]) {
        final (status, output, errors) = await diagnose([
          'doctor',
          '3.27.4',
          if (full) '--full',
          '--json',
        ]);
        expect(status, 4, reason: errors);
        final report = jsonDecode(output) as Map<String, Object?>;
        expect(report['scope'], {
          'kind': 'release',
          'requested_release': '3.27.4',
        });
        expect(report['releases'], isEmpty);
        expect(report['completion'], 'incomplete');
        expect(report['setup'], containsPair('has_critical_findings', true));
      }
    },
  );

  test('targeted cancellation returns 6 without a JSON diagnosis', () async {
    final (status, output, _) = await diagnose([
      'doctor',
      '3.27.4',
      '--json',
    ], cancellation: Stream<void>.value(null));
    expect(status, 6);
    expect(output, isEmpty);
  });
}

InstalledRelease _release(
  String version, {
  bool needsRepair = false,
  String channel = 'stable',
}) => InstalledRelease(
  channel: channel,
  version: version,
  host: 'macos',
  dartVersion: '3.6.2',
  needsRepair: needsRepair,
  repairReason: needsRepair ? 'fixture damage' : null,
);
