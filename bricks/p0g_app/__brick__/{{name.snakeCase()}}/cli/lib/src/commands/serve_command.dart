import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:squadron/squadron.dart';
import 'package:squadron_process/io.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

/// The services this CLI can host for the process place, by name.
final Map<String, Worker Function()> services = {
  'hello': HelloServiceWorker.new,
  // p0g:services (bricks insert services above this line)
};

/// Hosts one of the app's Squadron services for the process place.
///
/// On WebUI the page starts
/// `{{name.snakeCase()}} serve <service> --session-file ...` as root
/// through flutter-webui's root channel; on a desktop, `IoProcessLauncher`
/// starts it. The host prints its endpoint as the first stdout line, and exits once its last page link has been gone
/// for the grace window: hidden keeps running, closed stops.
class ServeCommand extends Command<int> {
  @override
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  String get name => 'serve';

  @override
  String get description =>
      'Host a service for the process place: serve <service> '
      '[--session-file F] [--port N] [--grace-ms N] [--first-link-grace-ms N]. '
      'Services: ${services.keys.join(', ')}.';

  @override
  Future<int> run() async {
    final args = argResults!.rest;
    final create = args.isEmpty ? null : services[args.first];
    if (create == null) {
      usageException('serve needs one of: ${services.keys.join(', ')}');
    }
    Logger('cli.serve').info('serving ${args.first}');
    return serve(create(), args.skip(1).toList(), facts: checkFacts);
  }
}
