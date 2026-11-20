import 'dart:io';

import 'package:mason/mason.dart';

import 'workspace.dart';

/// Runs before Mason writes any template: every file and marker post_gen
/// needs must be there, or nothing is written.
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
  final panel = context.vars['panel'] as bool? ?? true;
  final problems = {
    for (final insertion in insertions(app, name, panel: panel))
      if (problem(insertion) case final p?) p,
  };
  if (problems.isNotEmpty) {
    context.logger.err(
      'Not a p0g_app workspace this brick can extend; nothing was written:\n'
      '${problems.map((p) => '  $p').join('\n')}',
    );
    exit(1);
  }
  context.vars = {...context.vars, 'app': app};
}
