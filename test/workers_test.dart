import 'package:file/memory.dart';
import 'package:flutter_p0g/src/webui/workers.dart';
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
