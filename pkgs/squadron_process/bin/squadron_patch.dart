// Materializes the patched Squadron that squadron_process needs and points
// the consuming package (or pub workspace) at it.
//
//   dart run squadron_process:squadron_patch [<root>]
//
// <root> is the package or workspace root that owns pubspec_overrides.yaml
// (default: the current directory). The patched tree goes to
// <root>/.dart_tool/squadron_process/squadron-<commit>; the override is added
// to <root>/pubspec_overrides.yaml unless one for squadron is already there.
// Run `dart pub get` afterwards. Needs git.
import 'dart:io';
import 'dart:isolate';

Future<void> main(List<String> args) async {
  final root = args.isEmpty
      ? Directory.current
      : Directory(args.first).absolute;
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:squadron_process/squadron_process.dart'),
  );
  if (lib == null) _fail('squadron_process is not a dependency here');
  final pkg = File.fromUri(lib).parent.parent;
  final third = Directory('${pkg.path}/third_party/squadron');

  final pin = <String, String>{};
  for (final l in await File('${third.path}/PIN').readAsLines()) {
    final i = l.indexOf('=');
    if (!l.startsWith('#') && i > 0) {
      pin[l.substring(0, i)] = l.substring(i + 1);
    }
  }
  final repo = pin['repo']!, commit = pin['commit']!, tag = pin['tag']!;
  final patches =
      (await Directory('${third.path}/patches').list().toList())
          .whereType<File>()
          .where((f) => f.path.endsWith('.patch'))
          .map((f) => f.path)
          .toList()
        ..sort();

  final rel = '.dart_tool/squadron_process/squadron-${commit.substring(0, 12)}';
  final src = Directory('${root.path}/$rel');
  if (!await Directory('${src.path}/.git').exists()) {
    await src.create(recursive: true);
    await _git(['init', '-q'], src);
    await _git(['remote', 'add', 'origin', repo], src);
  }
  await _git(['fetch', '-q', '--depth', '1', 'origin', commit], src);
  await _git(['checkout', '-q', '--force', '--detach', commit], src);
  await _git(['clean', '-q', '-fdx'], src);
  for (final p in patches) {
    await _git(['apply', '--whitespace=nowarn', p], src);
  }
  stdout.writeln(
    'squadron $tag ($commit) + ${patches.length} patch(es) at '
    '${src.path}',
  );

  final overrides = File('${root.path}/pubspec_overrides.yaml');
  final entry = '  squadron:\n    path: $rel\n';
  if (!await overrides.exists()) {
    await overrides.writeAsString(
      '# squadron_process needs a patched Squadron '
      '(dart run squadron_process:squadron_patch).\n'
      'dependency_overrides:\n$entry',
    );
  } else {
    final text = await overrides.readAsString();
    if (RegExp(r'^\s+squadron:\s*$', multiLine: true).hasMatch(text)) {
      stdout.writeln(
        '${overrides.path} already overrides squadron; '
        'make sure it points at $rel',
      );
      return;
    }
    final at = RegExp(
      r'^dependency_overrides:\s*$',
      multiLine: true,
    ).firstMatch(text);
    await overrides.writeAsString(
      at == null
          ? '$text${text.endsWith('\n') ? '' : '\n'}dependency_overrides:\n$entry'
          : '${text.substring(0, at.end)}\n$entry${text.substring(at.end + 1)}',
    );
  }
  stdout.writeln('updated ${overrides.path}; run dart pub get');
}

Future<void> _git(List<String> args, Directory dir) async {
  final r = await Process.run('git', ['-C', dir.path, ...args]);
  if (r.exitCode != 0) _fail('git ${args.join(' ')}: ${r.stderr}');
}

Never _fail(String message) {
  stderr.writeln('squadron_patch: $message');
  exit(1);
}
