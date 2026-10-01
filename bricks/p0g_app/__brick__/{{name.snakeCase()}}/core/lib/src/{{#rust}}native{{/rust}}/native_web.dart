import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:web/web.dart' as web;

/// The path resolves against the script: the page sits at the base, a
/// Squadron Web Worker in `workers/`.
String get _prefix => globalContext.has('document') ? 'pkg/' : '../pkg/';

/// Web: frb's own loader fetches `pkg/<stem>.js` and its wasm, which
/// `flutter_p0g build webui` builds single-threaded (no COOP/COEP needed).
Future<ExternalLibrary?> openNativeLibrary(String stem) async =>
    loadExternalLibrary(
      ExternalLibraryLoaderConfig(
        stem: stem,
        ioDirectory: null,
        webPrefix: _prefix,
      ),
    );

@JS('fetch')
external JSPromise<web.Response> _fetch(String url, web.RequestInit init);

/// Whether the wasm is there, without downloading or instantiating it.
Future<bool> nativeShipped(String stem) async {
  try {
    final r = await _fetch(
      '$_prefix${stem}_bg.wasm',
      web.RequestInit(method: 'HEAD'),
    ).toDart;
    return r.ok;
  } on Object {
    return false;
  }
}
