// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../directory_picker.dart';

/// The picker as a plain DOM overlay above the Flutter view, the way
/// `file_selector_web` uses a DOM `<input>`: a plugin has no widget tree to
/// push a route on. It follows the page's colour scheme and safe-area insets.
final class DomDirectoryDialog implements DirectoryDialog {
  const DomDirectoryDialog();

  static const String _css = '''
.fsw-scrim{position:fixed;inset:0;z-index:2147483647;display:flex;align-items:stretch;justify-content:center;
  background:rgba(0,0,0,.4);font:16px/1.4 system-ui,sans-serif;color-scheme:light dark;
  padding:env(safe-area-inset-top,var(--safe-area-inset-top,0)) 0 env(safe-area-inset-bottom,var(--safe-area-inset-bottom,0))}
.fsw-panel{display:flex;flex-direction:column;width:100%;max-width:640px;background:Canvas;color:CanvasText}
.fsw-head{display:flex;gap:8px;align-items:center;padding:12px 16px;border-bottom:1px solid GrayText}
.fsw-path{flex:1;overflow-wrap:anywhere;font-weight:600}
.fsw-list{flex:1;overflow:auto;margin:0;padding:0;list-style:none}
.fsw-list li{padding:12px 16px;border-bottom:1px solid color-mix(in srgb,GrayText 30%,transparent)}
.fsw-list li.dir{cursor:pointer}
.fsw-list li.file{color:GrayText}
.fsw-error{padding:12px 16px;color:#c62828}
.fsw-foot{display:flex;gap:8px;align-items:center;padding:12px 16px;border-top:1px solid GrayText}
.fsw-foot input{flex:1;min-width:0;font:inherit;padding:8px}
.fsw-foot button,.fsw-head button{font:inherit;padding:8px 14px}
''';

  @override
  Future<String?> show(PickerState state) {
    final done = Completer<String?>();
    final doc = web.document;

    web.HTMLElement el(String tag, [String? cls, String? text]) {
      final e = doc.createElement(tag) as web.HTMLElement;
      if (cls != null) e.className = cls;
      if (text != null) e.textContent = text;
      return e;
    }

    final style = el('style')..textContent = _css;
    final scrim = el('div', 'fsw-scrim');
    final panel = el('div', 'fsw-panel');
    final head = el('div', 'fsw-head');
    final up = el('button', null, 'Up') as web.HTMLButtonElement;
    final path = el('div', 'fsw-path');
    final error = el('div', 'fsw-error');
    final list = el('ul', 'fsw-list');
    final foot = el('div', 'fsw-foot');
    final save = state.request.mode == PickMode.save;
    final name = (doc.createElement('input') as web.HTMLInputElement)
      ..type = 'text'
      ..value = state.request.suggestedName ?? ''
      ..placeholder = 'File name';
    final cancel = el('button', null, 'Cancel') as web.HTMLButtonElement;
    final confirm = el(
      'button',
      null,
      state.request.confirmButtonText ?? (save ? 'Save' : 'Select'),
    ) as web.HTMLButtonElement;

    void finish(String? value) {
      if (done.isCompleted) return;
      scrim.remove();
      style.remove();
      done.complete(value);
    }

    late final void Function() render;

    Future<void> go(Future<void> step) async {
      try {
        await step;
      } on Object catch (e) {
        error.textContent = '$e';
        error.style.display = '';
        return;
      }
      render();
    }

    render = () {
      path.textContent = state.directory;
      up.disabled = !state.canGoUp;
      error.textContent = state.error ?? '';
      error.style.display = state.error == null ? 'none' : '';
      confirm.disabled = save && !PickerState.validName(name.value);
      list.replaceChildren(<web.Node>[].toJS);
      for (final entry in state.entries) {
        final item = el(
          'li',
          entry.isDirectory ? 'dir' : 'file',
          entry.isDirectory ? '${entry.name}/' : entry.name,
        );
        if (entry.isDirectory) {
          item.onclick = ((web.Event _) {
            unawaited(go(state.enter(entry.name)));
          }).toJS;
        } else if (save) {
          item.onclick = ((web.Event _) {
            name.value = entry.name;
            render();
          }).toJS;
        }
        list.append(item);
      }
    };

    up.onclick = ((web.Event _) {
      unawaited(go(state.up()));
    }).toJS;
    cancel.onclick = ((web.Event _) => finish(null)).toJS;
    confirm.onclick = ((web.Event _) => finish(state.result(name.value))).toJS;
    name.oninput = ((web.Event _) => render()).toJS;
    scrim.onkeydown = ((web.KeyboardEvent e) {
      if (e.key == 'Escape') finish(null);
      e.stopPropagation();
    }).toJS;

    head
      ..append(up)
      ..append(path);
    if (save) foot.append(name);
    foot
      ..append(cancel)
      ..append(confirm);
    panel
      ..append(head)
      ..append(error)
      ..append(list)
      ..append(foot);
    scrim.append(panel);
    doc.head!.append(style);
    doc.body!.append(scrim);
    render();
    return done.future;
  }
}
