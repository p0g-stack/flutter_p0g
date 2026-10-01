import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_p0g/src/templates.dart';
import 'package:flutter_p0g/src/webui/module.dart';
import 'package:test/test.dart';

List<int> b(String s) => utf8.encode(s);

void main() {
  group('isPrunedWebFile', () {
    test('drops what no manager loads', () {
      for (final path in [
        'flutter_service_worker.js',
        '.last_build_id',
        'canvaskit/canvaskit.js.symbols',
        'canvaskit/chromium/canvaskit.js.symbols',
        'canvaskit/webparagraph/x.wasm',
        'canvaskit/wimp.wasm',
        'canvaskit/skwasm.wasm',
      ]) {
        expect(isPrunedWebFile(path), isTrue, reason: path);
      }
    });

    test('keeps the app and CanvasKit', () {
      for (final path in [
        'index.html',
        'main.dart.js',
        'canvaskit/canvaskit.wasm',
        'canvaskit/chromium/canvaskit.wasm',
        'assets/fonts/fallback/Roboto-Regular.ttf',
        'wimp.txt',
      ]) {
        expect(isPrunedWebFile(path), isFalse, reason: path);
      }
    });

    test('keeps Skwasm for --wasm builds', () {
      expect(isPrunedWebFile('canvaskit/skwasm.wasm', wasm: true), isFalse);
      expect(isPrunedWebFile('canvaskit/skwasm.js.symbols', wasm: true), isTrue);
    });
  });

  group('assembleModule', () {
    final webui = {
      'module.prop': b('id=c\nversion=v$kBuildNameVar\nversionCode=$kBuildNumberVar\n'),
      'customize.sh': b('true\n'),
      'webroot/config.json': b('{"v":"$kBuildNameVar"}'),
    };

    test('web build under webroot, webui overlays it, vars expanded', () {
      final files = assembleModule(
        webBuild: {
          'index.html': b('web'),
          'config.json': b('from build'),
          'flutter_service_worker.js': b(''),
        },
        webuiFolder: webui,
        buildName: '2.0.0',
        buildNumber: '5',
      );
      final byPath = {for (final f in files) f.path: utf8.decode(f.bytes)};
      expect(byPath['webroot/index.html'], 'web');
      expect(byPath['webroot/config.json'], '{"v":"2.0.0"}');
      expect(byPath['module.prop'], 'id=c\nversion=v2.0.0\nversionCode=5\n');
      expect(byPath.containsKey('webroot/flutter_service_worker.js'), isFalse);
      expect(byPath['META-INF/com/google/android/updater-script'], '#MAGISK\n');
      expect(byPath['customize.sh'], 'true\n');
    });

    test('extra files (the CLI) are executable in bin/', () {
      final files = assembleModule(
        webBuild: const {},
        webuiFolder: webui,
        extra: {
          'bin/app': [1, 2, 3],
        },
        buildName: '1',
        buildNumber: '1',
      );
      final exec = {for (final f in files) f.path: f.executable};
      expect(exec['bin/app'], isTrue);
      expect(exec['customize.sh'], isTrue);
      expect(exec['META-INF/com/google/android/update-binary'], isTrue);
      expect(exec['module.prop'], isFalse);
    });

    test('a missing module.prop is an error', () {
      expect(
        () => assembleModule(
          webBuild: const {},
          webuiFolder: const {},
          buildName: '1',
          buildNumber: '1',
        ),
        throwsStateError,
      );
    });
  });

  test('readProp', () {
    expect(readProp('id=counter\nname=C = D\n', 'id'), 'counter');
    expect(readProp('id=counter\nname=C = D\n', 'name'), 'C = D');
    expect(readProp('id=counter\n', 'author'), isNull);
  });

  test('zipModule: module.prop first, unix modes kept', () {
    final zip = zipModule([
      ModuleFile('bin/app', [0x7f], executable: true),
      ModuleFile('module.prop', b('id=c\n')),
      ModuleFile('webroot/index.html', b('<html>')),
    ]);
    final archive = ZipDecoder().decodeBytes(zip);
    expect(archive.files.first.name, 'module.prop');
    final modes = {for (final f in archive.files) f.name: f.mode & 0x1ff};
    expect(modes['bin/app'], 0x1ed); // 0755
    expect(modes['module.prop'], 0x1a4); // 0644
    expect(utf8.decode(archive.findFile('webroot/index.html')!.content as List<int>), '<html>');

    // Every central directory entry says "made by Unix", or unzip drops modes.
    final data = ByteData.sublistView(zip);
    var made = 0;
    for (var i = 0; i + 4 < zip.length; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014b50) {
        expect(zip[i + 5], 3);
        made++;
      }
    }
    expect(made, 3);
  });
}
