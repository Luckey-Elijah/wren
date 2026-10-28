import 'dart:convert';

import 'package:test/test.dart';
import 'package:wren/wren.dart';

void main() {
  group('wren releases', () {
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
            dartArchitecture: 'x64',
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
