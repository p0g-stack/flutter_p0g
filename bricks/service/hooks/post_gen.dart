import 'package:mason/mason.dart';

import 'workspace.dart';

/// Applies the insertions pre_gen checked, then formats what it touched.
void run(HookContext context) {
  final log = context.logger;
  final app = context.vars['app'] as String;
  final name = context.vars['name'] as String;
  final panel = context.vars['panel'] as bool? ?? true;
  final snake = name.snakeCase;

  final planned = insertions(app, name, panel: panel);
  planned.forEach(insertAtMarker);
  format(log, {
    for (final insertion in planned) insertion.path,
    'core/lib/src/service/${snake}_service.dart',
    'core/test/${snake}_service_test.dart',
    'cli/lib/src/commands/${snake}_command.dart',
    if (panel) 'app/lib/panels/${snake}_panel.dart',
  });

  log.info(
    'Added the $snake service${panel ? '' : ' without a panel'}. Generate '
    'its worker: (cd core && dart run build_runner build) && '
    'bash tool/build_workers.sh',
  );
}
