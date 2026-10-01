// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

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
}
