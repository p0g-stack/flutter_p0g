import 'dart:io' as io;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_p0g_tool/src/webui/workers.dart';
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:test/test.dart';

const generated = '''
EntryPoint \$getDemoServiceActivator(SquadronPlatformType platform) {
  if (platform.isJs) {
    return Squadron.uri('~/workers/demo_service.web.g.dart.js');
  } else if (platform.isWasm) {
    return Squadron.uri('~/workers/demo_service.web.g.dart.wasm');
  }
}
''';

void main() {
  for (final extension in ['js', 'wasm']) {
    test('$extension receives each resolved define unchanged and in order', () async {
      final fs = MemoryFileSystem.test();
      final process = _Processes();
      final oldRoot = Cache.flutterRoot;
      Cache.flutterRoot = '/flutter';
      addTearDown(() => Cache.flutterRoot = oldRoot);
      final source = fs.file('/app/lib/service.web.g.dart')..createSync(recursive: true);
      const defines = [
        'P0G_WORKER_VALUE=a=b with spaces',
        'FLAG=true',
        'UNICODE=日本語',
        'FLAG=false',
      ];
      await context.run<void>(
        overrides: <Type, Generator>{
          FileSystem: () => fs,
          Logger: () => BufferLogger.test(),
          ProcessUtils: () => process,
        },
        body: () => compileWorkers(
          [WorkerEntry(source, 'workers/service.$extension')],
          fs.directory('/out'),
          release: true,
          dartDefines: defines,
        ),
      );
      expect(process.command, [
        '/flutter/bin/dart',
        'compile',
        extension,
        if (extension == 'js') ...['-O2', '--no-source-maps'],
        for (final define in defines) '-D$define',
        '-o',
        '/out/workers/service.$extension',
        source.path,
      ]);
      expect(process.workingDirectory, source.parent.path);
    });
  }

  test('reads the URLs the activator loads', () {
    expect(workerOutputs(generated), [
      'workers/demo_service.web.g.dart.js',
      'workers/demo_service.web.g.dart.wasm',
    ]);
    expect(workerOutputs('class A {}'), isEmpty);
  });

  test('finds workers in workspace siblings; wasm only for --wasm', () {
    final fs = MemoryFileSystem.test();
    fs.directory('/w').createSync();
    fs.file('/w/pubspec.yaml').writeAsStringSync('workspace:\n  - core\n  - app\n');
    fs.file('/w/app/pubspec.yaml').createSync(recursive: true);
    fs.file('/w/core/pubspec.yaml').createSync(recursive: true);
    fs.file('/w/core/lib/src/s.web.g.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(generated);
    fs.file('/w/core/lib/src/s.vm.g.dart').writeAsStringSync(generated);

    final js = findWorkers(fs.directory('/w/app'), wasm: false);
    expect(js.map((w) => w.output), ['workers/demo_service.web.g.dart.js']);
    expect(js.single.source.path, '/w/core/lib/src/s.web.g.dart');
    expect(findWorkers(fs.directory('/w/app'), wasm: true), hasLength(2));
  });
}

class _Processes implements ProcessUtils {
  late List<String> command;
  late String workingDirectory;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #run) return super.noSuchMethod(invocation);
    command = invocation.positionalArguments.single as List<String>;
    workingDirectory = invocation.namedArguments[#workingDirectory] as String;
    return Future.value(RunResult(io.ProcessResult(1, 0, '', ''), command));
  }
}
