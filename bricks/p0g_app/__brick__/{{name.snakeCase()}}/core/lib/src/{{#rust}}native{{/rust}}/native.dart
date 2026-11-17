import 'dart:async';

import '../rust/frb_generated.dart';
import 'native_stub.dart'
    if (dart.library.io) 'native_io.dart'
    if (dart.library.js_interop) 'native_web.dart'
    as platform;

/// Whether this place has the app's Rust library, without loading it where
/// loading is expensive. The `native` fact. On the web it asks whether the
/// wasm was built (its JS glue is there) and leaves loading it to the first
/// call; natively it loads the library, which is cheap.
Future<bool> nativeShipped() => platform.nativeShipped(_stem);

const _stem = '{{name.snakeCase()}}_native';

/// Loads the app's Rust library (`rust/`, through flutter_rust_bridge) into
/// this isolate or Web Worker, once. True when its functions can be called.
///
/// Each place loads it for itself: a Squadron isolate, a Web Worker and the
/// CLI's `serve` process each have their own copy. Whether it loaded is the
/// `native` fact, so strategies that call Rust say `requires {Fact.native}`
/// and a place without the library picks another strategy. A strategy that
/// calls Rust awaits this first: on the web, that first call is when the
/// wasm is downloaded and instantiated.
Future<bool> loadNative() => _loaded ??= _load();

Future<bool>? _loaded;

NativeLoadFailure? _loadFailure;

/// The original library-init failure, including timeout failures.
NativeLoadFailure? get nativeLoadFailure => _loadFailure;

/// The library's error name, message and stack.
final class NativeLoadFailure {
  const NativeLoadFailure(this.name, this.message, this.stack);
  final String name;
  final String message;
  final String stack;
}

Future<bool> _load() async {
  try {
    final library = await platform.openNativeLibrary(_stem);
    await RustLib.init(externalLibrary: library)
        .timeout(const Duration(seconds: 5));
    _loadFailure = null;
    return true;
  } on Object catch (error, stack) {
    _loadFailure = NativeLoadFailure(
      error.runtimeType.toString(),
      '$error',
      '$stack',
    );
    return false;
  }
}
