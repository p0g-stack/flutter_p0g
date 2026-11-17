import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:web/web.dart' as web;

// Pages and workers resolve from their actual artifact, not the origin.
String get _prefix {
  if (globalContext.has('document')) {
    return Uri.parse(web.document.baseURI).resolve('pkg/').toString();
  }
  final location = globalContext.getProperty<JSObject>('location'.toJS);
  var href = location.getProperty<JSString>('href'.toJS).toDart;
  if (Uri.parse(href).scheme == 'blob') {
    final script = globalContext.getProperty<JSAny?>(
      'squadronWorkerScriptUrl'.toJS,
    );
    if (script == null ||
        !script.isA<JSString>() ||
        (script as JSString).toDart.isEmpty) {
      throw StateError('Blob worker has no squadronWorkerScriptUrl');
    }
    href = script.toDart;
  }
  return Uri.parse(href).resolve('../pkg/').toString();
}

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

/// Whether the wasm is there, without downloading or instantiating it. Asks
/// for the small JS glue built beside it, not the wasm: manager WebViews
/// answer a HEAD with the whole file. A GET, because `flutter run`'s dev
/// server answers HEAD with 404; the body is dropped unread.
Future<bool> nativeShipped(String stem) async {
  try {
    final r = await _fetch('$_prefix$stem.js', web.RequestInit()).toDart;
    await r.body?.cancel().toDart;
    return r.ok;
  } on Object {
    return false;
  }
}
