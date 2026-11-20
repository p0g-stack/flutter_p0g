import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:flutter_p0g/src/frb/frb.dart';
import 'package:package_config/package_config.dart';
import 'package:test/test.dart';

PackageConfig configWithFrbAt(String root) => PackageConfig([
  Package('flutter_rust_bridge', Uri.directory(root), packageUriRoot: Uri.directory('$root/lib')),
]);

void main() {
  test('the repo carries the frb series in order', () {
    final root = const LocalFileSystem().directory(io.Directory.current.path);
    final names = frbPatches(root).map((f) => f.basename).toList();
    expect(names, isNotEmpty);
    expect(names.first, startsWith('0001-'));
    expect(names, orderedEquals([...names]..sort()));
  });

  test('stamp changes with the commit and with any patch byte', () {
    final a = frbStamp(kFrbCommit, [
      [1, 2],
    ]);
    expect(a, startsWith('$kFrbCommit '));
    expect(
      frbStamp(kFrbCommit, [
        [1, 2],
      ]),
      a,
    );
    expect(
      frbStamp(kFrbCommit, [
        [1, 3],
      ]),
      isNot(a),
    );
    expect(
      frbStamp('0' * 40, [
        [1, 2],
      ]),
      isNot(a),
    );
  });

  group('checkPatchedDartSide', () {
    const patched = '/cache/flutter_p0g/frb/src/frb_dart';

    test('accepts the patched copy', () {
      expect(checkPatchedDartSide(configWithFrbAt(patched), patched), isNull);
    });

    test('rejects pub.dev frb with the override to add', () {
      final why = checkPatchedDartSide(
        configWithFrbAt('/home/u/.pub-cache/hosted/pub.dev/flutter_rust_bridge-2.11.1'),
        patched,
      );
      expect(why, contains('dependency_overrides'));
      expect(why, contains(patched));
    });

    test('says so when the app does not use frb', () {
      expect(checkPatchedDartSide(PackageConfig([]), patched), contains('does not depend'));
    });
  });

  test('the bindings package is the nearest pubspec above dart_output', () {
    final tmp = io.Directory.systemTemp.createTempSync('frb_root');
    addTearDown(() => tmp.deleteSync(recursive: true));
    io.Directory('${tmp.path}/core/lib/src/rust').createSync(recursive: true);
    io.File('${tmp.path}/core/pubspec.yaml').writeAsStringSync('name: core');
    final root = const LocalFileSystem().directory(tmp.path);
    expect(frbDartRoot(root, 'dart_output: core/lib/src/rust').path, '${tmp.path}/core');
    expect(frbDartRoot(root, 'rust_root: rust/').path, tmp.path);
  });

  test('the pass-through wasm-opt copies its input to -o', () async {
    final tmp = io.Directory.systemTemp.createTempSync('wasm_opt');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final shim = io.File('${tmp.path}/wasm-opt')..writeAsStringSync(kWasmOptPassthrough);
    io.File('${tmp.path}/in.wasm').writeAsBytesSync([0, 97, 115, 109]);
    final r = await io.Process.run('sh', [
      shim.path,
      '${tmp.path}/in.wasm',
      '-o',
      '${tmp.path}/out.wasm',
      '-O',
      '--enable-reference-types',
    ]);
    expect(r.exitCode, 0);
    expect(io.File('${tmp.path}/out.wasm').readAsBytesSync(), [0, 97, 115, 109]);
  });
}
