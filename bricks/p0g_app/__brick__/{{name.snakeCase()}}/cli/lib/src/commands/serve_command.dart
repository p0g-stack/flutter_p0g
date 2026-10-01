import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:squadron/squadron.dart';
import 'package:squadron_process/io.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

/// The services this CLI hosts for the process place, by the name a client
/// binds with. Each worker runs in its own isolate of this process.
Map<String, Invoker> services() => {
  'hello': HelloServiceWorker(),
  // p0g:services (bricks insert services above this line)
};

/// Hosts the app's Squadron services for the process place.
///
/// On WebUI the page starts `{{name.snakeCase()}} serve --session-file ...`
/// as root through flutter-webui's root channel; on a desktop,
/// `IoProcessLauncher` starts it. The host prints its endpoint as the first
/// stdout line, and exits once its last client link has been gone for the
/// grace window: hidden keeps running, closed stops.
class ServeCommand extends Command<int> {
  @override
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  String get name => 'serve';

  @override
  String get description =>
      'Host the services for the process place: serve [--session-file F] '
      '[--port N] [--launch-id ID] [--grace-ms N] [--first-link-grace-ms N].';

  @override
  Future<int> run() async {
    final hosted = services();
    Logger('cli.serve').info('serving ${hosted.keys.join(', ')}');
    return serve(hosted, argResults!.rest, facts: checkFacts);
  }
}
