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
  context.vars = {...context.vars, 'app': app};
}
