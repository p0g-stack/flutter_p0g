import 'package:mason/mason.dart';

import 'workspace.dart';

void run(HookContext context) {
  final log = context.logger;
  final app = context.vars['app'] as String;
  final name = context.vars['name'] as String;
  final snake = name.snakeCase;
  final pascal = name.pascalCase;

  final core = 'core/lib/${app}_core.dart';
  final runner = 'cli/lib/src/runner.dart';
  final serve = 'cli/lib/src/commands/serve_command.dart';
  final panels = 'app/lib/panels/panels.dart';

  insertAtMarker(log, core, 'exports', "export 'src/service/${snake}_service.dart';");
  insertAtMarker(log, runner, 'imports', "import 'commands/${snake}_command.dart';");
  insertAtMarker(log, runner, 'commands', 'addCommand(${pascal}Command());');
  insertAtMarker(log, serve, 'services', "'$snake': ${pascal}ServiceWorker(),");
  insertAtMarker(log, panels, 'imports', "import '${snake}_panel.dart';");
  insertAtMarker(log, panels, 'panels', '${pascal}Panel.inPlace,');
  format(log, [
    core,
    runner,
    serve,
    panels,
    'core/lib/src/service/${snake}_service.dart',
    'core/test/${snake}_service_test.dart',
    'cli/lib/src/commands/${snake}_command.dart',
    'app/lib/panels/${snake}_panel.dart',
  ]);

  log.info(
    'Added the $snake service. Generate its worker: '
    '(cd core && dart run build_runner build) && bash tool/build_workers.sh',
  );
}
