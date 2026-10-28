import 'dart:io';

import 'package:wren/wren.dart' show runWren;

Future<void> main(List<String> arguments) async {
  exit(await runWren(arguments));
}
