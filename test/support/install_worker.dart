import 'dart:convert';
import 'dart:io';

import 'package:wren/wren.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) exit(2);
  final [dataPath, repositoryPath, version, revision] = arguments;
  final status = await runWren(
    ['install', version],
    catalogJson: jsonEncode({
      'releases': [
        {
          'channel': 'stable',
          'version': version,
          'hash': revision,
          'dart_sdk_version': '3.13.7',
          'dart_sdk_arch': 'x64',
          'archive': 'stable/linux/flutter_linux_$version-stable.tar.xz',
          'sha256': List<String>.filled(64, 'a').join(),
        },
      ],
    }),
    host: HostPlatform.linuxX64,
    installEnvironment: InstallEnvironment(
      dataDirectory: Directory(dataPath),
      flutterRepository: Uri.file(repositoryPath),
    ),
  );
  exit(status);
}
