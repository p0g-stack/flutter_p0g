import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

/// Web: frb's own loader fetches `pkg/<stem>.js` and its wasm, which
/// `flutter_p0g build webui` builds single-threaded (no COOP/COEP needed).
Future<ExternalLibrary?> openNativeLibrary(String stem) async =>
    loadExternalLibrary(
      ExternalLibraryLoaderConfig(
        stem: stem,
        ioDirectory: null,
        webPrefix: 'pkg/',
      ),
    );
