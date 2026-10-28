import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wren/wren.dart';

const _version = '3.47.8';
const _dartVersion = '3.13.7';
final _engineRevision = List<String>.filled(40, 'e').join();
final _archiveDigest = List<String>.filled(64, 'a').join();

void main() {
  group('wren install', () {
    late Directory temp;
    late Directory repositoryWorktree;
    late Directory dataDirectory;
    late String frameworkRevision;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('wren-install-test-');
      repositoryWorktree = Directory(p.join(temp.path, 'flutter-source'));
      dataDirectory = Directory(p.join(temp.path, 'wren-data'));
      await repositoryWorktree.create();
      await _writeFixtureSdk(repositoryWorktree);
      await _git(repositoryWorktree.path, ['init']);
      await _git(repositoryWorktree.path, [
        'config',
        'user.email',
        'wren-test@example.invalid',
      ]);
      await _git(repositoryWorktree.path, ['config', 'user.name', 'Wren Test']);
      await _git(repositoryWorktree.path, ['add', '.']);
      await _git(repositoryWorktree.path, ['commit', '-m', 'fixture Flutter']);
      await _git(repositoryWorktree.path, ['tag', '-f', _version]);
      frameworkRevision = await _git(repositoryWorktree.path, [
        'rev-parse',
        'HEAD',
      ]);
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    test('stages, validates, and publishes a private SDK atomically', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      final status = await runWren(
        ['install', _version],
        catalogJson: _catalog(frameworkRevision),
        host: HostPlatform.linuxX64,
        installEnvironment: InstallEnvironment(
          dataDirectory: dataDirectory,
          flutterRepository: Uri.file(repositoryWorktree.path),
        ),
        stdoutSink: stdout,
        stderrSink: stderr,
      );

      expect(status, 0, reason: stderr.toString());
      expect(stdout.toString(), contains('Installed Flutter $_version'));
      final installed = Directory(
        p.join(dataDirectory.path, 'releases', 'stable-$_version-linux-x64'),
      );
      final manifest = jsonDecode(
        await File(p.join(installed.path, '.wren-release.json')).readAsString(),
      ) as Map<String, Object?>;
      expect(manifest['state'], 'ready');
      expect(manifest['frameworkRevision'], frameworkRevision);
      expect(manifest['engineRevision'], _engineRevision);
      expect(manifest['canonicalDartVersion'], _dartVersion);

      final source = Directory(
        p.join(dataDirectory.path, 'sources', manifest['sourceKey']! as String),
      );
      expect(
        File(p.join(source.path, '.wren-source.json')).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(source.path, 'bin/cache/dart-sdk')).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(installed.path, 'bin/cache/dart-sdk')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(installed.path, 'bin/cache/flutter_tools.snapshot'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(source.path, 'bin/cache/flutter_tools.snapshot'))
            .existsSync(),
        isFalse,
      );
      expect(
        await File(p.join(source.path, 'bin/cache/dart-sdk/bin/dart'))
            .readAsString(),
        await File(p.join(installed.path, 'bin/cache/dart-sdk/bin/dart'))
            .readAsString(),
      );
      expect(_hasLinkTo(installed, source.path), isFalse);
      expect(
        Directory(p.join(dataDirectory.path, 'staging')).listSync(),
        isEmpty,
      );

      final secondRun = await runWren(
        ['install', _version],
        catalogJson: _catalog(frameworkRevision),
        host: HostPlatform.linuxX64,
        installEnvironment: InstallEnvironment(
          dataDirectory: dataDirectory,
          flutterRepository: Uri.file(repositoryWorktree.path),
        ),
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      );
      expect(secondRun, 0);
    });

    test(
      'launches the exact release with transparent child behavior',
      () async {
        final environment = InstallEnvironment(
          dataDirectory: dataDirectory,
          flutterRepository: Uri.file(repositoryWorktree.path),
        );
        final installStatus = await runWren(
          ['install', _version],
          catalogJson: _catalog(frameworkRevision),
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdoutSink: StringBuffer(),
          stderrSink: StringBuffer(),
        );
        expect(installStatus, 0);

        final installed = Directory(
          p.join(dataDirectory.path, 'releases', 'stable-$_version-linux-x64'),
        );
        final flutter = File(p.join(installed.path, 'bin/flutter'));
        final argsFile = File(p.join(temp.path, 'child-args.txt'));
        final startedFile = File(p.join(temp.path, 'child-started'));
        final proceedFile = File(p.join(temp.path, 'child-proceed'));
        await flutter.writeAsString('''
#!/bin/sh
printf '%s\\n' "\$@" > '${argsFile.path}'
touch '${startedFile.path}'
while [ ! -e '${proceedFile.path}' ]; do sleep 0.01; done
cat
printf 'child stdout\\n'
printf 'child stderr\\n' >&2
exit 23
''');
        await Process.run('chmod', ['+x', flutter.path]);

        final stdout = StringBuffer();
        final stderr = StringBuffer();
        final running = runWren(
          ['--release', _version, 'flutter', '--verbose', '--', 'a b'],
          flutterReleaseOverride: '3.47.7',
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdinStream: Stream.value(utf8.encode('child input')),
          stdoutSink: stdout,
          stderrSink: stderr,
        );
        for (
          var attempt = 0;
          attempt < 300 && !startedFile.existsSync();
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(startedFile.existsSync(), isTrue);
        final leases = Directory(
          p.join(dataDirectory.path, 'leases', 'stable-$_version-linux-x64'),
        );
        expect(leases.listSync(), hasLength(1));
        await proceedFile.create();

        expect(await running, 23);
        expect(await argsFile.readAsLines(), ['--verbose', '--', 'a b']);
        expect(stdout.toString(), contains('child input'));
        expect(stdout.toString(), contains('child stdout'));
        expect(stderr.toString(), contains('child stderr'));
        expect(leases.existsSync(), isFalse);

        final dartError = StringBuffer();
        final dartStatus = await runWren(
          ['dart', '--version'],
          flutterReleaseOverride: _version,
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdinStream: const Stream.empty(),
          stdoutSink: StringBuffer(),
          stderrSink: dartError,
        );
        expect(dartStatus, 0);
        expect(
          dartError.toString(),
          contains('Dart SDK version: $_dartVersion'),
        );

        await flutter.writeAsString(
          r'''
#!/bin/sh
kill -TERM $$
'''
              .trimLeft(),
        );
        final signaledStatus = await runWren(
          ['flutter'],
          flutterReleaseOverride: _version,
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdoutSink: StringBuffer(),
          stderrSink: StringBuffer(),
        );
        expect(signaledStatus, 143);

        final binaryStdout = File(p.join(temp.path, 'binary-stdout'));
        final binaryStderr = File(p.join(temp.path, 'binary-stderr'));
        final binaryStdoutSink = binaryStdout.openWrite();
        final binaryStderrSink = binaryStderr.openWrite();
        await flutter.writeAsString(
          r'''
#!/bin/sh
printf '\377\000\n'
printf '\376\000\n' >&2
'''
              .trimLeft(),
        );
        final binaryStatus = await runWren(
          ['flutter'],
          flutterReleaseOverride: _version,
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdinStream: const Stream.empty(),
          stdoutSink: binaryStdoutSink,
          stderrSink: binaryStderrSink,
        );
        expect(binaryStatus, 0);
        await binaryStdoutSink.close();
        await binaryStderrSink.close();
        expect(await binaryStdout.readAsBytes(), [0xff, 0x00, 0x0a]);
        expect(await binaryStderr.readAsBytes(), [0xfe, 0x00, 0x0a]);

        await flutter.writeAsString(
          '#!/no/such/interpreter${String.fromCharCode(10)}',
        );
        final startError = StringBuffer();
        final failedStart = await runWren(
          ['flutter', '--version'],
          flutterReleaseOverride: _version,
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdoutSink: StringBuffer(),
          stderrSink: startError,
        );
        expect(failedStart, 5);
        expect(startError.toString(), contains('could not start Flutter'));
        expect(leases.existsSync(), isFalse);

        final releaseMarker = File(
          p.join(installed.path, '.wren-release.json'),
        );
        final releaseData = jsonDecode(
          await releaseMarker.readAsString(),
        ) as Map<String, Object?>;
        await releaseMarker.writeAsString(
          jsonEncode({...releaseData, 'channel': 'beta'}),
        );
        final identityError = StringBuffer();
        final identityStatus = await runWren(
          ['flutter'],
          flutterReleaseOverride: _version,
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdoutSink: StringBuffer(),
          stderrSink: identityError,
        );
        expect(identityStatus, 3);
        expect(identityError.toString(), contains('needs repair'));
        await releaseMarker.writeAsString(jsonEncode(releaseData));

        await File(p.join(installed.path, 'bin/cache/dart-sdk/bin/dart'))
            .delete();
        final damagedError = StringBuffer();
        final damagedStatus = await runWren(
          ['flutter', '--version'],
          flutterReleaseOverride: _version,
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdoutSink: StringBuffer(),
          stderrSink: damagedError,
        );
        expect(damagedStatus, 3);
        expect(damagedError.toString(), contains('needs repair'));
      },
    );

    test('list and ls show readiness and hide incomplete stages', () async {
      final environment = InstallEnvironment(
        dataDirectory: dataDirectory,
        flutterRepository: Uri.file(repositoryWorktree.path),
      );
      final installStatus = await runWren(
        ['install', _version],
        catalogJson: _catalog(frameworkRevision),
        host: HostPlatform.linuxX64,
        installEnvironment: environment,
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      );
      expect(installStatus, 0);

      final installed = Directory(
        p.join(dataDirectory.path, 'releases', 'stable-$_version-linux-x64'),
      );
      await Directory(p.join(dataDirectory.path, 'staging', 'interrupted'))
          .create(recursive: true);
      final listOutput = StringBuffer();
      final listStatus = await runWren(
        ['list'],
        host: HostPlatform.linuxX64,
        installEnvironment: environment,
        stdoutSink: listOutput,
        stderrSink: StringBuffer(),
      );
      final aliasOutput = StringBuffer();
      final aliasStatus = await runWren(
        ['ls'],
        host: HostPlatform.linuxX64,
        installEnvironment: environment,
        stdoutSink: aliasOutput,
        stderrSink: StringBuffer(),
      );

      expect(listStatus, 0);
      expect(aliasStatus, 0);
      expect(aliasOutput.toString(), listOutput.toString());
      expect(
        listOutput.toString(),
        contains('$_version  stable  linux  ready'),
      );
      expect(listOutput.toString(), isNot(contains('interrupted')));

      await File(p.join(installed.path, 'bin/cache/linux-sdk.stamp')).delete();
      final damagedOutput = StringBuffer();
      expect(
        await runWren(
          ['list'],
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdoutSink: damagedOutput,
          stderrSink: StringBuffer(),
        ),
        0,
      );
      expect(damagedOutput.toString(), contains('needs repair'));
      final releaseMarker = jsonDecode(
        await File(p.join(installed.path, '.wren-release.json')).readAsString(),
      ) as Map<String, Object?>;
      expect(releaseMarker['readiness'], 'needs-repair');

      await File(p.join(installed.path, 'bin/cache/linux-sdk.stamp'))
          .writeAsString('$_engineRevision\n');
      final actualSourceDart = File(
        p.join(
          dataDirectory.path,
          'sources',
          '$_engineRevision-linux-x64',
          'bin/cache/dart-sdk/bin/dart',
        ),
      );
      expect(actualSourceDart.existsSync(), isTrue);
      final chmod = await Process.run('chmod', ['-x', actualSourceDart.path]);
      expect(chmod.exitCode, 0);
      final sourceDamageOutput = StringBuffer();
      expect(
        await runWren(
          ['list'],
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdoutSink: sourceDamageOutput,
          stderrSink: StringBuffer(),
        ),
        0,
      );
      expect(sourceDamageOutput.toString(), contains('needs repair'));
      expect(
        sourceDamageOutput.toString(),
        contains('shared artifact source executable is not runnable'),
      );
    });

    test('seeds a second release from the retained engine source', () async {
      final environment = InstallEnvironment(
        dataDirectory: dataDirectory,
        flutterRepository: Uri.file(repositoryWorktree.path),
      );
      expect(
        await runWren(
          ['install', _version],
          catalogJson: _catalog(frameworkRevision),
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdoutSink: StringBuffer(),
          stderrSink: StringBuffer(),
        ),
        0,
      );

      const secondVersion = '3.47.9';
      await _writeFixtureSdk(repositoryWorktree, version: secondVersion);
      await File(p.join(repositoryWorktree.path, 'README.md'))
          .writeAsString('second framework revision\n');
      await _git(repositoryWorktree.path, ['add', '.']);
      await _git(repositoryWorktree.path, ['commit', '-m', 'second fixture']);
      await _git(repositoryWorktree.path, ['tag', '-f', secondVersion]);
      final secondRevision = await _git(repositoryWorktree.path, [
        'rev-parse',
        'HEAD',
      ]);

      final secondStderr = StringBuffer();
      final secondInstall = await runWren(
        ['install', secondVersion],
        catalogJson: _catalog(secondRevision, releaseVersion: secondVersion),
        host: HostPlatform.linuxX64,
        installEnvironment: environment,
        stdoutSink: StringBuffer(),
        stderrSink: secondStderr,
      );

      expect(secondInstall, 0, reason: secondStderr.toString());
      expect(
        File(p.join(dataDirectory.path, 'source-seeded')).existsSync(),
        isTrue,
      );
    });

    test(
      'installs a native macOS arm64 release from its host artifacts',
      () async {
        await _writeFixtureSdk(
          repositoryWorktree,
          host: HostPlatform.macosArm64,
        );
        await _git(repositoryWorktree.path, ['add', '.']);
        await _git(repositoryWorktree.path, ['commit', '-m', 'macOS fixture']);
        await _git(repositoryWorktree.path, ['tag', '-f', _version]);
        frameworkRevision = await _git(repositoryWorktree.path, [
          'rev-parse',
          'HEAD',
        ]);
        final stdout = StringBuffer();
        final stderr = StringBuffer();

        final status = await runWren(
          ['install', _version],
          catalogJson: _catalog(
            frameworkRevision,
            host: HostPlatform.macosArm64,
          ),
          host: HostPlatform.macosArm64,
          installEnvironment: InstallEnvironment(
            dataDirectory: dataDirectory,
            flutterRepository: Uri.file(repositoryWorktree.path),
          ),
          stdoutSink: stdout,
          stderrSink: stderr,
        );

        expect(status, 0, reason: stderr.toString());
        expect(stdout.toString(), contains('Installed Flutter $_version'));
        final installed = Directory(
          p.join(
            dataDirectory.path,
            'releases',
            'stable-$_version-darwin-arm64',
          ),
        );
        final source = Directory(
          p.join(dataDirectory.path, 'sources', '$_engineRevision-macos-arm64'),
        );
        final installedFrameworkInfo = File(
          p.join(
            installed.path,
            'bin/cache/artifacts/engine/darwin-arm64/FlutterMacOS.xcframework/Info.plist',
          ),
        );
        final sourceFrameworkInfo = File(
          p.join(
            source.path,
            'bin/cache/artifacts/engine/darwin-arm64/FlutterMacOS.xcframework/Info.plist',
          ),
        );
        expect(
          Directory(
            p.join(
              installed.path,
              'bin/cache/artifacts/engine/darwin-arm64-profile/FlutterMacOS.xcframework',
            ),
          ).existsSync(),
          isTrue,
        );
        expect(_hasLinkTo(installed, source.path), isFalse);
        await installedFrameworkInfo.writeAsString('private framework');
        expect(
          (await sourceFrameworkInfo.readAsString()).trim(),
          'fixture framework',
        );
        expect(
          Directory(
            p.join(source.path, 'bin/cache/artifacts/engine/darwin-arm64'),
          ).existsSync(),
          isTrue,
        );
        expect(
          Directory(p.join(dataDirectory.path, 'staging')).listSync(),
          isEmpty,
        );
      },
    );

    test(
      'failed macOS artifact validation publishes no installed release',
      () async {
        await _writeFixtureSdk(
          repositoryWorktree,
          host: HostPlatform.macosArm64,
          omitMacReleaseArtifact: true,
        );
        await _git(repositoryWorktree.path, ['add', '.']);
        await _git(repositoryWorktree.path, [
          'commit',
          '-m',
          'incomplete macOS fixture',
        ]);
        await _git(repositoryWorktree.path, ['tag', '-f', _version]);
        frameworkRevision = await _git(repositoryWorktree.path, [
          'rev-parse',
          'HEAD',
        ]);
        final stderr = StringBuffer();

        final status = await runWren(
          ['install', _version],
          catalogJson: _catalog(
            frameworkRevision,
            host: HostPlatform.macosArm64,
          ),
          host: HostPlatform.macosArm64,
          installEnvironment: InstallEnvironment(
            dataDirectory: dataDirectory,
            flutterRepository: Uri.file(repositoryWorktree.path),
          ),
          stderrSink: stderr,
        );

        expect(status, 4);
        expect(
          stderr.toString(),
          contains('required Flutter artifact is missing'),
        );
        expect(
          Directory(
            p.join(
              dataDirectory.path,
              'releases',
              'stable-$_version-darwin-arm64',
            ),
          ).existsSync(),
          isFalse,
        );
        expect(
          Directory(p.join(dataDirectory.path, 'staging')).listSync(),
          isEmpty,
        );
      },
    );

    test('rejects an Intel Dart runtime for a macOS arm64 release', () async {
      await _writeFixtureSdk(
        repositoryWorktree,
        host: HostPlatform.macosArm64,
        runtimeArchitecture: 'macos_x64',
      );
      await _git(repositoryWorktree.path, ['add', '.']);
      await _git(repositoryWorktree.path, [
        'commit',
        '-m',
        'Intel Dart fixture',
      ]);
      await _git(repositoryWorktree.path, ['tag', '-f', _version]);
      frameworkRevision = await _git(repositoryWorktree.path, [
        'rev-parse',
        'HEAD',
      ]);
      final stderr = StringBuffer();

      final status = await runWren(
        ['install', _version],
        catalogJson: _catalog(frameworkRevision, host: HostPlatform.macosArm64),
        host: HostPlatform.macosArm64,
        installEnvironment: InstallEnvironment(
          dataDirectory: dataDirectory,
          flutterRepository: Uri.file(repositoryWorktree.path),
        ),
        stderrSink: stderr,
      );

      expect(status, 4);
      expect(stderr.toString(), contains('requires native macos_arm64'));
      expect(
        Directory(
          p.join(
            dataDirectory.path,
            'releases',
            'stable-$_version-darwin-arm64',
          ),
        ).existsSync(),
        isFalse,
      );
    });

    test(
      'failed artifact staging leaves no ready install and can be retried',
      () async {
        await dataDirectory.create(recursive: true);
        await File(p.join(dataDirectory.path, 'fail-precache'))
            .writeAsString('1');
        final stderr = StringBuffer();
        final environment = InstallEnvironment(
          dataDirectory: dataDirectory,
          flutterRepository: Uri.file(repositoryWorktree.path),
        );

        final failed = await runWren(
          ['install', _version],
          catalogJson: _catalog(frameworkRevision),
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stderrSink: stderr,
        );

        expect(failed, 4);
        expect(stderr.toString(), contains('failed to download or extract'));
        expect(
          File(
            p.join(
              dataDirectory.path,
              'releases',
              'stable-$_version-linux-x64',
              '.wren-release.json',
            ),
          ).existsSync(),
          isFalse,
        );
        expect(
          Directory(p.join(dataDirectory.path, 'staging')).listSync(),
          isEmpty,
        );

        final retried = await runWren(
          ['install', _version],
          catalogJson: _catalog(frameworkRevision),
          host: HostPlatform.linuxX64,
          installEnvironment: environment,
          stdoutSink: StringBuffer(),
          stderrSink: StringBuffer(),
        );
        expect(retried, 0);
      },
    );

    test(
      'rejects a catalog Dart mismatch before publishing readiness',
      () async {
        await _writeFixtureSdk(
          repositoryWorktree,
          reportedDartVersion: '3.12.9',
        );
        await _git(repositoryWorktree.path, ['add', '.']);
        await _git(repositoryWorktree.path, [
          'commit',
          '-m',
          'wrong Dart version',
        ]);
        await _git(repositoryWorktree.path, ['tag', '-f', _version]);
        frameworkRevision = await _git(repositoryWorktree.path, [
          'rev-parse',
          'HEAD',
        ]);
        final stderr = StringBuffer();

        final status = await runWren(
          ['install', _version],
          catalogJson: _catalog(frameworkRevision),
          host: HostPlatform.linuxX64,
          installEnvironment: InstallEnvironment(
            dataDirectory: dataDirectory,
            flutterRepository: Uri.file(repositoryWorktree.path),
          ),
          stderrSink: stderr,
        );

        expect(status, 4);
        expect(stderr.toString(), contains('catalog specifies $_dartVersion'));
        expect(
          Directory(p.join(dataDirectory.path, 'releases')).listSync(),
          isEmpty,
        );
      },
    );

    test(
      'rejects a mismatched Dart executable even when Flutter metadata agrees',
      () async {
        await _writeFixtureSdk(
          repositoryWorktree,
          runtimeDartVersion: '3.12.9',
        );
        await _git(repositoryWorktree.path, ['add', '.']);
        await _git(repositoryWorktree.path, [
          'commit',
          '-m',
          'wrong Dart runtime',
        ]);
        await _git(repositoryWorktree.path, ['tag', '-f', _version]);
        frameworkRevision = await _git(repositoryWorktree.path, [
          'rev-parse',
          'HEAD',
        ]);
        final stderr = StringBuffer();

        final status = await runWren(
          ['install', _version],
          catalogJson: _catalog(frameworkRevision),
          host: HostPlatform.linuxX64,
          installEnvironment: InstallEnvironment(
            dataDirectory: dataDirectory,
            flutterRepository: Uri.file(repositoryWorktree.path),
          ),
          stderrSink: stderr,
        );

        expect(status, 4);
        expect(stderr.toString(), contains('bundled Dart reports 3.12.9'));
        expect(
          Directory(p.join(dataDirectory.path, 'releases')).listSync(),
          isEmpty,
        );
      },
    );

    test('rejects an ineligible release before creating storage', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      final status = await runWren(
        ['install', '3.47.7'],
        catalogJson: _catalog(frameworkRevision, dartVersion: null),
        host: HostPlatform.linuxX64,
        installEnvironment: InstallEnvironment(
          dataDirectory: dataDirectory,
          flutterRepository: Uri.file(repositoryWorktree.path),
        ),
        stdoutSink: stdout,
        stderrSink: stderr,
      );

      expect(status, 4);
      expect(stderr.toString(), contains('bundled Dart version is missing'));
      expect(await dataDirectory.exists(), isFalse);
    });
  });
}

String _catalog(
  String frameworkRevision, {
  String? dartVersion = _dartVersion,
  String releaseVersion = _version,
  HostPlatform host = HostPlatform.linuxX64,
}) => jsonEncode({
  'releases': [
    {
      'channel': 'stable',
      'version': dartVersion == null ? '3.47.7' : releaseVersion,
      'hash': frameworkRevision,
      'dart_sdk_version': ?dartVersion,
      'dart_sdk_arch': host.catalogArchitecture,
      'archive': host == HostPlatform.linuxX64
          ? 'stable/linux/flutter_linux_$releaseVersion-stable.tar.xz'
          : 'stable/macos/flutter_macos_arm64_$releaseVersion-stable.zip',
      'sha256': _archiveDigest,
    },
  ],
});

Future<void> _writeFixtureSdk(
  Directory root, {
  String version = _version,
  String reportedDartVersion = _dartVersion,
  String runtimeDartVersion = _dartVersion,
  String? runtimeArchitecture,
  HostPlatform host = HostPlatform.linuxX64,
  bool omitMacReleaseArtifact = false,
}) async {
  final isLinux = host == HostPlatform.linuxX64;
  final hostArtifactRoot = isLinux ? 'linux-x64' : 'darwin-arm64';
  final hostProfileRoot = isLinux
      ? 'linux-x64-profile'
      : 'darwin-arm64-profile';
  final hostReleaseRoot = isLinux
      ? 'linux-x64-release'
      : 'darwin-arm64-release';
  final hostStamp = isLinux ? 'linux-sdk.stamp' : 'macos-sdk.stamp';
  final omitMacRelease = omitMacReleaseArtifact ? 'true' : 'false';
  final dartHost =
      runtimeArchitecture ?? (isLinux ? 'linux_x64' : 'macos_arm64');
  final precacheFlag = isLinux ? '--linux' : '--macos';
  final profileArtifact = isLinux
      ? 'bin/cache/artifacts/engine/$hostProfileRoot/flutter_linux/libflutter_linux_gtk.so'
      : 'bin/cache/artifacts/engine/$hostProfileRoot/FlutterMacOS.xcframework/Info.plist';
  final releaseArtifact = isLinux
      ? 'bin/cache/artifacts/engine/$hostReleaseRoot/flutter_linux/libflutter_linux_gtk.so'
      : 'bin/cache/artifacts/engine/$hostReleaseRoot/FlutterMacOS.xcframework/Info.plist';
  final frameworkArtifact = isLinux
      ? 'bin/cache/artifacts/engine/$hostArtifactRoot/libflutter_linux_gtk.so'
      : 'bin/cache/artifacts/engine/$hostArtifactRoot/FlutterMacOS.xcframework/Info.plist';
  if (await Directory(p.join(root.path, 'bin/cache')).exists()) {
    await Directory(p.join(root.path, 'bin/cache')).delete(recursive: true);
  }
  await Directory(p.join(root.path, 'bin/internal')).create(recursive: true);
  await File(p.join(root.path, 'bin/internal/engine.version'))
      .writeAsString('$_engineRevision\n');
  final flutter = File(p.join(root.path, 'bin/flutter'));
  await flutter.writeAsString('''#!/bin/sh
set -eu
if [ "\$1" = "precache" ]; then
  if [ "\$2" != "$precacheFlag" ] || [ "\$3" != "--web" ]; then
    echo "unexpected precache target: \$2 \$3" >&2
    exit 18
  fi
  if [ -f bin/cache/dart-sdk/bin/dart ]; then
    touch ../../../source-seeded
  fi
  if [ -f ../../../fail-precache ]; then
    rm -f ../../../fail-precache
    echo "fixture precache failure" >&2
    exit 17
  fi
  mkdir -p bin/cache/dart-sdk/bin
  mkdir -p bin/cache/artifacts/engine/common/flutter_patched_sdk
  mkdir -p bin/cache/artifacts/engine/common/flutter_patched_sdk_product
  mkdir -p bin/cache/artifacts/engine/$hostArtifactRoot
  mkdir -p bin/cache/artifacts/engine/$hostProfileRoot
  if [ '$omitMacRelease' = 'false' ] || [ '$isLinux' = 'true' ]; then mkdir -p bin/cache/artifacts/engine/$hostReleaseRoot; fi
  if [ '$isLinux' = 'true' ]; then
    mkdir -p bin/cache/artifacts/engine/$hostProfileRoot/flutter_linux
    mkdir -p bin/cache/artifacts/engine/$hostReleaseRoot/flutter_linux
  else
    mkdir -p bin/cache/artifacts/engine/$hostArtifactRoot/FlutterMacOS.xcframework
    mkdir -p bin/cache/artifacts/engine/$hostProfileRoot/FlutterMacOS.xcframework
    if [ '$omitMacRelease' = 'false' ]; then mkdir -p bin/cache/artifacts/engine/$hostReleaseRoot/FlutterMacOS.xcframework; fi
  fi
  mkdir -p bin/cache/flutter_web_sdk
  mkdir -p bin/cache/pkg/sky_engine
  mkdir -p bin/cache/pkg/flutter_gpu
  touch bin/cache/flutter_tools.snapshot
  touch bin/cache/flutter_tools.stamp
  printf '$_engineRevision\\n' > bin/cache/engine-dart-sdk.stamp
  printf '$_engineRevision\\n' > bin/cache/engine.stamp
  printf '$_engineRevision\\n' > bin/cache/flutter_sdk.stamp
  printf '$_engineRevision\\n' > bin/cache/$hostStamp
  printf '$_engineRevision\\n' > bin/cache/flutter_web_sdk.stamp
  printf 'main\\n' > bin/cache/engine.realm
  if [ '$isLinux' = 'true' ]; then touch $frameworkArtifact $profileArtifact; else printf 'fixture framework\\n' > $frameworkArtifact; printf 'fixture framework\\n' > $profileArtifact; fi
  if [ '$omitMacRelease' = 'false' ] || [ '$isLinux' = 'true' ]; then if [ '$isLinux' = 'true' ]; then touch $releaseArtifact; else printf 'fixture framework\\n' > $releaseArtifact; fi; fi
  touch bin/cache/artifacts/engine/$hostArtifactRoot/gen_snapshot
  if [ '$isLinux' = 'true' ]; then touch bin/cache/artifacts/engine/$hostArtifactRoot/flutter_tester; fi
  touch bin/cache/flutter_web_sdk/version.txt
  touch bin/cache/pkg/sky_engine/pubspec.yaml
  touch bin/cache/pkg/flutter_gpu/pubspec.yaml
  cat > bin/cache/dart-sdk/bin/dart <<'DART'
#!/bin/sh
printf 'Dart SDK version: $runtimeDartVersion (stable) on "%s"\\n' "$dartHost" >&2
DART
  chmod +x bin/cache/dart-sdk/bin/dart
  chmod +x bin/cache/artifacts/engine/$hostArtifactRoot/gen_snapshot
  if [ '$isLinux' = 'true' ]; then chmod +x bin/cache/artifacts/engine/$hostArtifactRoot/flutter_tester; fi
  exit 0
fi
if [ "\$1" = "--version" ]; then
  framework=\$(git rev-parse HEAD)
  engine=\$(cat bin/internal/engine.version)
  printf '{"channel":"[user-branch]","flutterVersion":"$version","frameworkRevision":"%s","engineRevision":"%s","dartSdkVersion":"$reportedDartVersion"}\\n' "\$framework" "\$engine"
  exit 0
fi
echo "unexpected fake Flutter arguments" >&2
exit 19
''');
  await Process.run('chmod', ['+x', flutter.path]);
}

Future<String> _git(String cwd, List<String> arguments) async {
  final result = await Process.run('git', arguments, workingDirectory: cwd);
  if (result.exitCode != 0) {
    throw StateError('${result.stderr}\n${result.stdout}');
  }
  return '${result.stdout}'.trim();
}

bool _hasLinkTo(Directory root, String targetRoot) {
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (FileSystemEntity.typeSync(entity.path, followLinks: false) ==
        FileSystemEntityType.link) {
      final target = Link(entity.path).targetSync();
      if (p.normalize(p.absolute(p.dirname(entity.path), target)) ==
              p.normalize(targetRoot) ||
          p.isWithin(
            targetRoot,
            p.normalize(p.absolute(p.dirname(entity.path), target)),
          )) {
        return true;
      }
    }
  }
  return false;
}
