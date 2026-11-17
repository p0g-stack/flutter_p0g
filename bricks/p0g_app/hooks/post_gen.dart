import 'dart:convert';
import 'dart:io';

import 'package:mason/mason.dart';

/// Writes `tool/p0g_app.json`: the vars this workspace was made with, the
/// config `tool/regen.sh` regenerates it from. Commit it as written.
void run(HookContext context) {
  final name = _string(context, 'name');
  final config = <String, Object>{
    'name': name,
    'description': _string(context, 'description'),
    'org': _string(context, 'org'),
    'rust': _bool(context, 'rust'),
    'sample': _bool(context, 'sample'),
  };
  // Mason runs the hook in the output directory, the workspace's parent.
  File('${name.snakeCase}/tool/p0g_app.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(config)}\n',
  );
}

String _string(HookContext context, String key) {
  final value = context.vars[key];
  if (value is String) return value;
  _fail(context, '$key must be a string, got ${jsonEncode(value)}');
}

bool _bool(HookContext context, String key) {
  final value = context.vars[key];
  if (value is bool) return value;
  _fail(context, '$key must be true or false, got ${jsonEncode(value)}');
}

Never _fail(HookContext context, String message) {
  context.logger.err('p0g_app: $message; tool/p0g_app.json not written.');
  exit(64);
}
