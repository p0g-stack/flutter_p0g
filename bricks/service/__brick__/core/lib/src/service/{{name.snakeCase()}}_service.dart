import 'dart:async';

import 'package:logging/logging.dart';
import 'package:squadron/squadron.dart';

import '{{name.snakeCase()}}_service.activator.g.dart';

part '{{name.snakeCase()}}_service.worker.g.dart';

/// The {{name.snakeCase()}} service. The same class runs in every place: an
/// isolate, a Web Worker, or the CLI's `serve {{name.snakeCase()}}` in
/// another process.
@SquadronService(
  baseUrl: '~/workers',
  targetPlatform: TargetPlatform.vm | TargetPlatform.web,
)
base class {{name.pascalCase()}}Service {
  static final _log = Logger('service.{{name.snakeCase()}}');

  /// An example method; replace it with the service's work. Decide how with
  /// an `Objective` (`mason make strategy`), never with the platform.
  @squadronMethod
  Future<String> echo(String input) async {
    _log.fine('echo $input');
    return input;
  }
}
