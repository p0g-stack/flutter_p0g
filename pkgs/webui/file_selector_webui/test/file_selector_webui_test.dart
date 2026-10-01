// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:file_selector_webui/src/directory_picker.dart';
import 'package:file_selector_webui/src/file_selector_webui_impl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webui_app_plane/testing.dart';

/// A root filesystem for the fake channel: directory -> entries (dirs end
/// in `/`). Answers `ls -1ApL -- <dir>` like toybox.
FakeRootChannel fakeFs(Map<String, List<String>> fs) => FakeRootChannel(
  handler: (run) {
    if (run.argv.first != '/system/bin/ls') {
      return const FakeProcessResult(exitCode: 127);
    }
    final dir = run.argv.last;
    final entries = fs[dir];
    return entries == null
        ? FakeProcessResult(
            exitCode: 1,
            stderr: "ls: $dir: No such file or directory",
          )
        : FakeProcessResult(stdout: entries.map((e) => '$e\n').join());
  },
);

const Map<String, List<String>> fs = {
  '/': ['data/', 'storage/', 'init'],
  '/storage': ['emulated/', 'self/'],
  '/storage/emulated': ['0/'],
  '/storage/emulated/0': ['Download/', 'Documents/', 'notes.txt', 'Alarms/'],
  '/storage/emulated/0/Download': ['a.zip'],
  '/storage/emulated/0/Documents': [],
};

/// Plays the user: runs [steps] against the state, then returns [answer].
class ScriptedDialog implements DirectoryDialog {
  ScriptedDialog(this.steps);

  final Future<String?> Function(PickerState state) steps;
  PickerState? seen;

  @override
  Future<String?> show(PickerState state) {
    seen = state;
    return steps(state);
  }
}

class StockSelector extends FileSelectorPlatform {
  final List<String> calls = [];

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    calls.add('openFile(${acceptedTypeGroups?.first.extensions})');
    return XFile.fromData(Uint8List(0), path: 'picked.txt');
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    calls.add('openFiles');
    return [];
  }

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    calls.add('getDirectoryPath');
    return null;
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    calls.add('getSaveLocation');
    return const FileSaveLocation('');
  }
}

void main() {
  late StockSelector stock;

  FileSelectorWebUiImpl selector(
    FakeRootChannel fake,
    DirectoryDialog dialog, {
    FakeBridge? bridge,
  }) => FileSelectorWebUiImpl(
    stock: stock,
    root: fake.root(bridge),
    dialog: dialog,
  );

  setUp(() => stock = StockSelector());

  test('opening files is the WebView chooser (stock web)', () async {
    final s = selector(fakeFs(fs), ScriptedDialog((_) async => null));
    final file = await s.openFile(
      acceptedTypeGroups: const [
        XTypeGroup(extensions: ['txt']),
      ],
    );
    await s.openFiles();
    expect(file!.name, 'picked.txt');
    expect(stock.calls, ['openFile([txt])', 'openFiles']);
  });

  test('getDirectoryPath walks a root listing to a real path', () async {
    final fake = fakeFs(fs);
    final dialog = ScriptedDialog((state) async {
      expect(state.directory, '/storage/emulated/0');
      expect(state.entries.map((e) => '$e'), [
        'Alarms/',
        'Documents/',
        'Download/',
        'notes.txt',
      ]);
      await state.enter('Download');
      expect(state.entries.map((e) => '$e'), ['a.zip']);
      await state.up();
      await state.up();
      await state.up();
      expect(state.directory, '/storage');
      await state.enter('emulated');
      await state.enter('0');
      await state.enter('Documents');
      return state.result();
    });
    final path = await selector(
      fake,
      dialog,
    ).getDirectoryPathWithOptions(const FileDialogOptions());
    expect(path, '/storage/emulated/0/Documents');
    expect(fake.runs.first.argv, [
      '/system/bin/ls',
      '-1ApL',
      '--',
      '/storage/emulated/0',
    ]);
    expect(stock.calls, isEmpty);
  });

  test('cancel returns null and an empty list', () async {
    final s = selector(fakeFs(fs), ScriptedDialog((_) async => null));
    expect(
      await s.getDirectoryPathWithOptions(const FileDialogOptions()),
      isNull,
    );
    expect(
      await s.getDirectoryPathsWithOptions(const FileDialogOptions()),
      isEmpty,
    );
  });

  test('an unreadable initial directory falls back to its parent', () async {
    final dialog = ScriptedDialog((state) async {
      expect(state.error, isNull);
      return state.result();
    });
    final path = await selector(fakeFs(fs), dialog).getDirectoryPathWithOptions(
      const FileDialogOptions(
        initialDirectory: '/storage/emulated/0/gone/deeper',
      ),
    );
    expect(path, '/storage/emulated/0');
  });

  test('a failed listing keeps the current directory and an error', () async {
    final dialog = ScriptedDialog((state) async {
      await state.enter('nope');
      expect(state.directory, '/storage/emulated/0');
      expect(state.error, contains('No such file'));
      return null;
    });
    await selector(
      fakeFs(fs),
      dialog,
    ).getDirectoryPathWithOptions(const FileDialogOptions());
  });

  test('getSaveLocation returns directory plus typed name', () async {
    final dialog = ScriptedDialog((state) async {
      expect(state.request.mode, PickMode.save);
      expect(state.request.suggestedName, 'report.pdf');
      await state.enter('Download');
      expect(PickerState.validName('../x'), isFalse);
      expect(PickerState.validName(' '), isFalse);
      return state.result(' report.pdf ');
    });
    final loc = await selector(fakeFs(fs), dialog).getSaveLocation(
      options: const SaveDialogOptions(suggestedName: 'report.pdf'),
    );
    expect(loc!.path, '/storage/emulated/0/Download/report.pdf');
  });

  test('a browser tab is stock web for everything', () async {
    final fake = fakeFs(fs);
    final s = selector(
      fake,
      ScriptedDialog((_) => fail('no dialog in a browser')),
      bridge: FakeBridge.browser(),
    );
    expect(
      await s.getDirectoryPathWithOptions(const FileDialogOptions()),
      isNull,
    );
    expect((await s.getSaveLocation())!.path, '');
    expect(stock.calls, ['getDirectoryPath', 'getSaveLocation']);
    expect(fake.runs, isEmpty);
  });

  test('an unreachable root channel is a PlatformException', () async {
    final fake = fakeFs(fs)..unavailable = true;
    await expectLater(
      selector(
        fake,
        ScriptedDialog((_) async => null),
      ).getDirectoryPathWithOptions(const FileDialogOptions()),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'webui-root-unavailable',
        ),
      ),
    );
  });

  test('WebUI X and APatch hosts use the root listing too', () async {
    for (final bridge in [FakeBridge.webuix(), FakeBridge.apatch()]) {
      final s = selector(
        fakeFs(fs),
        ScriptedDialog((state) async => state.result()),
        bridge: bridge,
      );
      expect(
        await s.getDirectoryPathWithOptions(const FileDialogOptions()),
        '/storage/emulated/0',
      );
    }
  });

  group('opening files through the app', () {
    /// A fake with the app installed; DocumentOpen answers [answer].
    FakeRootChannel withApp(String answer) => FakeRootChannel(
      handler: (run) {
        if (run.argv.contains('path')) {
          return const FakeProcessResult(stdout: 'package:/x.apk');
        }
        if (run.argv.contains('DocumentOpen')) {
          return FakeProcessResult(stdout: '$answer\n');
        }
        return const FakeProcessResult();
      },
    );

    FileSelectorWebUiImpl selector(FakeRootChannel fake) =>
        FileSelectorWebUiImpl(
          stock: StockSelector(),
          root: fake.root(),
          dialog: ScriptedDialog((_) async => null),
        );

    test('picks into a hand-off folder, moves to module temp', () async {
      final fake = withApp(
        '[{"name":"a b.png","mime":"image/png","size":3,'
        '"path":"/data/data/com.webui.api.demo/cache/handoff/x/a b.png"}]',
      );
      final file = await selector(fake).openFile(
        acceptedTypeGroups: [
          const XTypeGroup(mimeTypes: ['image/png', 'image/jpeg']),
        ],
      );
      final call = fake.runs.firstWhere((r) => r.argv.contains('DocumentOpen'));
      final dir = call.argv[call.argv.indexOf('dir') + 1];
      expect(dir, startsWith('/data/data/com.webui.api.demo/cache/handoff/'));
      expect(call.argv.sublist(4, 6), ['--wait', '1800']);
      expect(call.argv.sublist(call.argv.indexOf('DocumentOpen')), [
        'DocumentOpen',
        '--es',
        'dir',
        dir,
        '--esa',
        'mime',
        'image/png,image/jpeg',
      ]);
      final callId = dir.split('/').last;
      expect(file!.path, '/data/adb/demo/tmp/open-$callId/a b.png');
      expect(file.name, 'a b.png');
      expect(file.mimeType, 'image/png');
      // The hand-off folder goes after the move.
      expect(fake.runs.last.argv, ['/system/bin/rm', '-rf', dir]);
    });

    test('openFiles allows several; cancel gives none', () async {
      final fake = withApp('[]');
      expect(await selector(fake).openFiles(), isEmpty);
      final call = fake.runs.firstWhere((r) => r.argv.contains('DocumentOpen'));
      expect(call.argv.last, 'true');
      expect(call.argv, isNot(contains('mime')));
    });

    test('extension-only groups offer any file', () {
      expect(
        FileSelectorWebUiImpl.mimeTypes([
          const XTypeGroup(mimeTypes: ['text/plain']),
          const XTypeGroup(extensions: ['zip']),
        ]),
        isEmpty,
      );
    });

    test('a failed copy is a PlatformException', () async {
      final fake = withApp('{"error":"cannot open content://x"}');
      await expectLater(
        selector(fake).openFile(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.message,
            'message',
            contains('cannot open'),
          ),
        ),
      );
    });

    test('the move script works in a real sh', () async {
      final fake = withApp(
        '[{"name":"n.txt","mime":"text/plain","size":1,"path":"/p/n.txt"}]',
      );
      await selector(fake).openFile();
      final move = fake.runs.lastWhere(
        (r) => r.argv.length > 2 && r.argv[2].contains('mv '),
      );
      final tmp = await Directory.systemTemp.createTemp('open');
      addTearDown(() => tmp.delete(recursive: true));
      final src = Directory('${tmp.path}/handoff')..createSync();
      File('${src.path}/n.txt').writeAsStringSync('x');
      File('${src.path}/.hidden').writeAsStringSync('y');
      final script = move.argv[2].replaceFirst('chown -R 0:0 "\$t"', 'true');
      final r = await Process.run('sh', [
        '-c',
        script,
        'sh',
        src.path,
        '${tmp.path}/t',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File('${tmp.path}/t/n.txt').readAsStringSync(), 'x');
      expect(File('${tmp.path}/t/.hidden').existsSync(), isTrue);
    }, testOn: 'linux');
  });
}
