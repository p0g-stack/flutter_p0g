import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../facts/facts.dart';
import '../native/native.dart';
import 'objective.dart';
import 'strategy.dart';

/// SHA-256 of a text, as lowercase hex: through Rust (`rust/`, the `sha2`
/// crate) where this place loaded it, else in Dart.
///
/// An example of a Rust crate behind a strategy: the place's `native` fact
/// says whether the library loaded, so a Web Worker without the wasm, or a
/// CLI without its `.so`, still answers.
final digest = Objective<String, String>('digest', const [
  RustSha256(),
  DartSha256(),
]);

final class RustSha256 extends ReadStrategy<String, String> {
  const RustSha256();

  @override
  String get name => 'rust_sha2';

  @override
  Set<String> get requires => const {Fact.native};

  @override
  Future<String> run(String input, PlaceInfo place) async =>
      sha256Hex(data: utf8.encode(input));
}

final class DartSha256 extends ReadStrategy<String, String> {
  const DartSha256();

  @override
  String get name => 'dart_crypto';

  @override
  Future<String> run(String input, PlaceInfo place) async =>
      crypto.sha256.convert(utf8.encode(input)).toString();
}
