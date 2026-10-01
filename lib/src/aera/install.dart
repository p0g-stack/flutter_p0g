/// Installing an `.aerap` into a running AERA recovery over adb, the way
/// AERA's own Plugin Manager installs a local package (`InstallLocal()` in
/// `aeraui/features/plugins/plugin_manager.cpp`): the manifest, its
/// signature if any and `runtime.xz`, verified, read-only, published by
/// rename into the plugin store under the plugin id.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../adb.dart';

/// AERA's persistent plugin store (internal storage, needs data decrypted).
const kAeraStorageRoot = '/sdcard/AERA/plugins';

/// AERA's RAM plugin store, gone on reboot.
const kAeraMemoryRoot = '/tmp/aera/plugins';

/// AERA's RPC channel (`orscmd/orscmd.h`): a JSON request written to the
/// input FIFO, newline-delimited JSON events read from the output FIFO.
const kAeraRpcIn = '/system/bin/aerain';
const kAeraRpcOut = '/system/bin/aeraout';

/// An `.aerap`'s files, checked as AERA's `OpenLocalBundle()` checks them.
class AerapPackage {
  AerapPackage._(this.manifest, this.signature, this.runtimeXz, this.id, this.payloadSha256);

  factory AerapPackage.decode(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const FormatException('not a valid .aerap package');
    }
    final names = [for (final f in archive.files) f.name];
    const allowed = {'plugin.json', 'plugin.json.sig', 'runtime.xz'};
    if (names.length < 2 ||
        names.length > 3 ||
        !names.every(allowed.contains) ||
        names.toSet().length != names.length) {
      throw FormatException('unsupported .aerap members: ${names.join(', ')}');
    }
    Uint8List? member(String name) {
      final f = archive.findFile(name);
      return f == null ? null : Uint8List.fromList(f.content as List<int>);
    }

    final manifest = member('plugin.json');
    final runtime = member('runtime.xz');
    if (manifest == null || runtime == null) {
      throw const FormatException('.aerap lacks plugin.json or runtime.xz');
    }
    final json = jsonDecode(utf8.decode(manifest));
    if (json is! Map ||
        json['id'] is! String ||
        json['payload_sha256'] is! String ||
        json['payload_size'] != runtime.length) {
      throw const FormatException('plugin.json does not describe runtime.xz');
    }
    final id = json['id'] as String;
    if (!safeAeraId(id)) throw FormatException('bad plugin id "$id"');
    return AerapPackage._(
      manifest,
      member('plugin.json.sig'),
      runtime,
      id,
      (json['payload_sha256'] as String).toLowerCase(),
    );
  }

  final Uint8List manifest;
  final Uint8List? signature;
  final Uint8List runtimeXz;
  final String id;
  final String payloadSha256;
}

/// AERA's `SafeId()`.
bool safeAeraId(String id) =>
    id.isNotEmpty &&
    id.length <= 64 &&
    !id.startsWith('.') &&
    !id.endsWith('.') &&
    RegExp(r'^[a-z0-9.-]+$').hasMatch(id);

/// Publishes the files pushed to [pushed] (`plugin.json`, `runtime.xz`,
/// `plugin.json.sig` when [signed]) as plugin [id] under [root], as
/// `InstallLocal()` does: staging dir, payload hash check, 0444 files,
/// previous install kept until the rename succeeds.
String aeraInstallScript({
  required String pushed,
  required String root,
  required String id,
  required String sha256,
  required bool signed,
}) {
  final r = shellQuote(root);
  final src = shellQuote(pushed);
  final stage = shellQuote('$root/.install-$id-flutter_p0g');
  final dest = shellQuote('$root/$id');
  final prev = shellQuote('$root/$id.previous');
  final files = ['plugin.json', 'runtime.xz', if (signed) 'plugin.json.sig'];
  return [
    'set -e',
    'mkdir -p $r',
    'rm -rf $stage $prev',
    'mkdir -m 0700 $stage',
    for (final f in files) 'cp $src/$f $stage/$f',
    // `sha256sum` prints "<hash>  <file>".
    'h=\$(sha256sum $stage/runtime.xz)',
    'if [ "\${h%% *}" != ${shellQuote(sha256)} ]; then rm -rf $stage; '
        'echo "runtime.xz does not match payload_sha256" >&2; exit 4; fi',
    'chmod 0444 ${[for (final f in files) '$stage/$f'].join(' ')}',
    'if [ -e $dest ]; then mv $dest $prev; fi',
    'if ! mv $stage $dest; then [ -e $prev ] && mv $prev $dest; rm -rf $stage; exit 5; fi',
    'rm -rf $prev $src',
  ].join('\n');
}

/// One AERA RPC request (`aera_rpc/aera_protocol.cpp`: `v` 1, `op`, `args`).
String aeraRpcRequest(String op, Map<String, Object?> args, {String id = 'flutter_p0g'}) =>
    jsonEncode({'v': 1, 'id': id, 'op': op, 'args': args});

/// Exit code of [aeraRpcScript] when AERA's input FIFO is not there.
const kAeraNotRunningExit = 66;

/// Sends [request] and prints AERA's events until it closes the output.
/// The input FIFO takes the request on EOF; AERA opens the output once it
/// dispatches. Without the FIFO (AERA not running) nothing is written: a
/// redirect would leave a plain file where AERA makes its pipe.
String aeraRpcScript(String request) =>
    '[ -p $kAeraRpcIn ] || exit $kAeraNotRunningExit; '
    'printf %s ${shellQuote(request)} > $kAeraRpcIn && cat $kAeraRpcOut';

/// The `result` code in AERA's RPC output, or null without one.
({int? code, List<String> errors, List<String> logs}) parseAeraRpcEvents(String out) {
  int? code;
  final errors = <String>[];
  final logs = <String>[];
  for (final line in const LineSplitter().convert(out)) {
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (event is! Map) continue;
    switch (event['event']) {
      case 'result':
        code = (event['code'] as num?)?.toInt();
      case 'error':
        errors.add('${event['code']}: ${event['message']}');
      case 'log':
        logs.add('${event['text']}'.trimRight());
    }
  }
  return (code: code, errors: errors, logs: logs);
}
