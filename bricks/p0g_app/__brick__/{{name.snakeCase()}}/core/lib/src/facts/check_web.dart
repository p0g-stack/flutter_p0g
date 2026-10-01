import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

{{#rust}}import '../native/native.dart';
{{/rust}}import 'facts.dart';

/// Checks the facts of the current browser context (page or Web Worker).
///
/// A browser context never has root, block devices, OS-level USB or process
/// spawning; the remaining facts are feature checks made here.
Future<Map<String, Object?>> checkFacts() async {
  final nav = globalContext['navigator'] as JSObject?;
  return {
    Fact.root: false,
    Fact.blockDevices: false,
    Fact.usbNative: false,
    Fact.usbWeb: nav != null && nav.has('usb'),
    Fact.processSpawn: false,
    Fact.fsPersistent: await _persisted(nav),
    Fact.net: nav != null && (nav['onLine'] as JSBoolean?)?.toDart == true,
{{#rust}}    Fact.native: await loadNative(),
{{/rust}}  };
}

Future<bool> _persisted(JSObject? nav) async {
  try {
    if (nav == null || !nav.has('storage')) return false;
    final storage = nav['storage'] as web.StorageManager;
    return (await storage.persisted().toDart).toDart;
  } catch (_) {
    return false;
  }
}
