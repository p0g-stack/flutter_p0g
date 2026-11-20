import 'dart:io';

import 'package:{{name.snakeCase()}}_cli/{{name.snakeCase()}}_cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await AppRunner().run(args);
}
