import 'dart:io';

import 'package:mason/mason.dart';

import 'workspace.dart';

void run(HookContext context) {
  final app = appName();
  if (app == null) {
    context.logger.err(
      'No p0g_app workspace here (core/pubspec.yaml named <app>_core). '
      'Run mason make in the workspace root.',
    );
    exit(1);
  }
  final name = context.vars['name'] as String;
  final strategies = [
    for (final s in context.vars['strategies'] as List) '$s'.trim(),
  ].where((s) => s.isNotEmpty).toList();
  if (strategies.isEmpty) {
    context.logger.err('Name at least one strategy.');
    exit(1);
  }
  context.vars = {
    ...context.vars,
    'app': app,
    // Precomputed, because inside {{#write}} the template's {{.}} is `write`.
    'items': [
      for (final s in strategies)
        {'id': s.snakeCase, 'type': '$name $s'.pascalCase, 'label': s},
    ],
  };
}
