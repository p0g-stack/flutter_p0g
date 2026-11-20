import 'package:mason/mason.dart';

import 'workspace.dart';

void run(HookContext context) {
  final log = context.logger;
  final app = context.vars['app'] as String;
  final snake = (context.vars['name'] as String).snakeCase;
  final core = 'core/lib/${app}_core.dart';

  insertAtMarker(log, core, 'exports', "export 'src/strategy/$snake.dart';");
  format(log, [
    core,
    'core/lib/src/strategy/$snake.dart',
    'core/test/${snake}_test.dart',
  ]);
  log.info(
    'Added the $snake objective. Give each strategy its requires and its '
    'work, then run it from a service: '
    '$snake.run(input, await PlaceInfo.current()).',
  );
}
