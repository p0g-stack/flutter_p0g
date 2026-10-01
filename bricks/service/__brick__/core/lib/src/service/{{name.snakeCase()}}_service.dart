import 'dart:async';

import 'package:logging/logging.dart';
import 'package:squadron/squadron.dart';

import '{{name.snakeCase()}}_service.activator.g.dart';

part '{{name.snakeCase()}}_service.worker.g.dart';

/// The {{name.snakeCase()}} service. The same class runs in every place: an
/// isolate, a Web Worker, or the CLI's `serve` in another process.
///
/// A call to the process place costs a few hundred microseconds and its link
/// moves about 110 MiB/s: give each method a whole job, and return progress
/// or bulk data as a `Stream` instead of making many small calls.
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
