/// The `.aerap` package, as flutter-aera's `spec/aerap.md` defines it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// One member of the runtime stream.
class RuntimeMember {
  RuntimeMember(this.name, this.bytes, {this.executable = false});

  /// Path relative to `AERA_PLUGIN_ROOT`, posix.
  final String name;
  final List<int> bytes;
  final bool executable;
}

const kMaxMembers = 4096;
const kMaxMemberSize = 100 * 1024 * 1024;

/// AERA's runtime stream: `AERAWEB1`, u32 count, then per member u16 name
/// length, u16 mode, u64 size, the name, padding to 4 bytes, the bytes. All
/// little-endian. Members are sorted by name so equal inputs give equal bytes.
Uint8List runtimeStream(List<RuntimeMember> members) {
  if (members.length > kMaxMembers) {
    throw ArgumentError('${members.length} members; AERA takes at most $kMaxMembers');
  }
  final sorted = [...members]..sort((a, b) => a.name.compareTo(b.name));
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode('AERAWEB1'))
    ..add(_u32(sorted.length));
  final seen = <String>{};
  for (final m in sorted) {
    if (!seen.add(m.name)) throw ArgumentError('duplicate member ${m.name}');
    if (m.name.isEmpty || m.name.startsWith('/') || m.name.split('/').contains('..')) {
      throw ArgumentError('bad member name ${m.name}');
    }
    if (m.bytes.length > kMaxMemberSize) throw ArgumentError('${m.name} is over 100 MiB');
    final name = utf8.encode(m.name);
    final header = ByteData(12)
      ..setUint16(0, name.length, Endian.little)
      ..setUint16(2, m.executable ? 0x1ed : 0x1a4, Endian.little) // 0755 : 0644
      ..setUint64(4, m.bytes.length, Endian.little);
    out
      ..add(header.buffer.asUint8List())
      ..add(name)
      ..add(Uint8List((4 - name.length % 4) % 4))
      ..add(m.bytes);
  }
  return out.takeBytes();
}

Uint8List _u32(int v) => (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

/// `id`: lowercase letters, digits, `-` and `.`, 1–64, no leading or
/// trailing `.`, never `browser`.
String? checkPluginId(String id) {
  if (!RegExp(r'^[a-z0-9.-]{1,64}$').hasMatch(id)) {
    return 'id "$id" must be 1-64 of a-z, 0-9, "-" and "."';
  }
  if (id.startsWith('.') || id.endsWith('.')) return 'id "$id" must not start or end with "."';
  if (id == 'browser') return 'id "browser" is reserved';
  return null;
}

/// The fixed four; the app may add `network` or `audio-output`.
const kBasePermissions = ['display', 'touch-input', 'pixel-surface', 'gpu-acceleration'];
const kAppPermissions = {'network', 'audio-output'};

/// Builds `plugin.json`: the app's fields, the packer's fixed fields, and
/// the payload facts computed from [stream] and [xz].
Map<String, Object?> pluginManifest({
  required Map<String, Object?> app,
  required Uint8List stream,
  required Uint8List xz,
  required int memberCount,
  required String payloadUrl,
}) {
  String field(String key, int max, {bool required = true}) {
    final value = app[key];
    if (value == null && !required) return '';
    if (value is! String || (required && value.isEmpty)) {
      throw FormatException('aera/plugin.json: "$key" must be a string');
    }
    if (value.length > max) throw FormatException('aera/plugin.json: "$key" is over $max chars');
    return value;
  }

  final id = field('id', 64);
  final idProblem = checkPluginId(id);
  if (idProblem != null) throw FormatException('aera/plugin.json: $idProblem');
  final extra = <String>[];
  for (final p in (app['permissions'] as List?) ?? const []) {
    if (!kAppPermissions.contains(p)) {
      throw FormatException('aera/plugin.json: permission "$p" is not one an app may add');
    }
    if (!extra.contains(p)) extra.add(p as String);
  }
  final icon = field('icon', 24, required: false);
  return {
    'schema': 1,
    'id': id,
    'name': field('name', 80),
    'version': field('version', 32),
    'description': field('description', 320, required: false),
    if (icon.isNotEmpty) 'icon': icon,
    'type': 'ui-runtime',
    'entry': 'main',
    'executable': 'usr/bin/aera-plugin',
    'min_host_api': 3,
    'protocol_version': 3,
    'payload': 'runtime.xz',
    'payload_url': payloadUrl,
    'payload_size': xz.length,
    'payload_sha256': sha256.convert(xz).toString(),
    'expanded_size': stream.length,
    'expanded_sha256': sha256.convert(stream).toString(),
    'member_count': memberCount,
    'permissions': [...kBasePermissions, ...extra],
  };
}

/// The `.aerap`: a stored (not deflated) zip of exactly `plugin.json` and
/// `runtime.xz`.
Uint8List aerapZip(String pluginJson, Uint8List runtimeXz) {
  final archive = Archive();
  final manifest = utf8.encode(pluginJson);
  archive.addFile(ArchiveFile('plugin.json', manifest.length, manifest)..compress = false);
  archive.addFile(ArchiveFile('runtime.xz', runtimeXz.length, runtimeXz)..compress = false);
  return Uint8List.fromList(ZipEncoder().encode(archive, level: Deflate.NO_COMPRESSION)!);
}

String encodeManifest(Map<String, Object?> manifest) =>
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
