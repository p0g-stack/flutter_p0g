import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_p0g/src/aera/aerap.dart';
import 'package:flutter_p0g/src/aera/kit.dart';
import 'package:flutter_p0g/src/templates.dart';
import 'package:test/test.dart';

/// Reads AERA's runtime stream back (spec/aerap.md).
List<(String, int, List<int>)> readStream(Uint8List s) {
  final d = ByteData.sublistView(s);
  expect(ascii.decode(s.sublist(0, 8)), 'AERAWEB1');
  final count = d.getUint32(8, Endian.little);
  var o = 12;
  final out = <(String, int, List<int>)>[];
  for (var i = 0; i < count; i++) {
    final nameLen = d.getUint16(o, Endian.little);
    final mode = d.getUint16(o + 2, Endian.little);
    final size = d.getUint64(o + 4, Endian.little);
    o += 12;
    final name = utf8.decode(s.sublist(o, o + nameLen));
    o += nameLen + (4 - nameLen % 4) % 4;
    out.add((name, mode, s.sublist(o, o + size)));
    o += size;
  }
  expect(o, s.length);
  return out;
}

void main() {
  test('runtime stream: sorted members, modes, padding', () {
    final s = runtimeStream([
      RuntimeMember('usr/share/flutter/icudtl.dat', [1, 2, 3]),
      RuntimeMember('usr/bin/aera-plugin', [9], executable: true),
      RuntimeMember('abc', const []),
    ]);
    final members = readStream(s);
    expect(members.map((m) => m.$1), [
      'abc',
      'usr/bin/aera-plugin',
      'usr/share/flutter/icudtl.dat',
    ]);
    expect(members[1].$2, 0x1ed);
    expect(members[2].$2, 0x1a4);
    expect(members[2].$3, [1, 2, 3]);
  });

  test('runtime stream rejects duplicates and escaping names', () {
    expect(
      () => runtimeStream([RuntimeMember('a', []), RuntimeMember('a', [])]),
      throwsArgumentError,
    );
    expect(() => runtimeStream([RuntimeMember('../x', [])]), throwsArgumentError);
    expect(() => runtimeStream([RuntimeMember('/x', [])]), throwsArgumentError);
  });

  test('plugin ids', () {
    expect(checkPluginId('org.example.counter'), isNull);
    expect(checkPluginId('counter_app'), isNotNull);
    expect(checkPluginId('.x'), isNotNull);
    expect(checkPluginId('browser'), isNotNull);
    expect(aeraIdFor('Counter_App'), 'counter-app');
  });

  group('pluginManifest', () {
    final stream = Uint8List.fromList([1, 2, 3, 4]);
    final xz = Uint8List.fromList([5, 6]);
    Map<String, Object?> build(Map<String, Object?> app) => pluginManifest(
      app: app,
      stream: stream,
      xz: xz,
      memberCount: 7,
      payloadUrl: 'https://localhost/runtime.xz',
    );
    const app = {'id': 'counter', 'name': 'Counter', 'version': '1.0.0', 'description': 'd'};

    test('fixed and computed fields', () {
      final m = build({
        ...app,
        'permissions': ['network', 'network'],
      });
      expect(m['type'], 'ui-runtime');
      expect(m['executable'], 'usr/bin/aera-plugin');
      expect(m['min_host_api'], 3);
      expect(m['payload_size'], 2);
      expect(m['payload_sha256'], sha256.convert(xz).toString());
      expect(m['expanded_size'], 4);
      expect(m['expanded_sha256'], sha256.convert(stream).toString());
      expect(m['member_count'], 7);
      expect(m['permissions'], [...kBasePermissions, 'network']);
      expect(m.containsKey('icon'), isFalse);
    });

    test('rejects what AERA would', () {
      expect(() => build({...app, 'id': 'Bad_Id'}), throwsFormatException);
      expect(() => build({...app, 'name': 'x' * 81}), throwsFormatException);
      expect(
        () => build({
          ...app,
          'permissions': ['root'],
        }),
        throwsFormatException,
      );
    });
  });

  test('.aerap is a stored zip of exactly plugin.json and runtime.xz', () {
    final zip = aerapZip('{}', Uint8List.fromList([7, 7, 7]));
    final archive = ZipDecoder().decodeBytes(zip);
    expect(archive.files.map((f) => f.name), ['plugin.json', 'runtime.xz']);
    // Compression method 0 (stored) in every local header.
    final d = ByteData.sublistView(zip);
    for (var i = 0; i + 4 < zip.length; i++) {
      if (d.getUint32(i, Endian.little) == 0x04034b50) expect(d.getUint16(i + 8, Endian.little), 0);
    }
  });

  group('validateAeraKit', () {
    Archive kit(Map<String, String> files) {
      final a = Archive();
      files.forEach((n, c) => a.addFile(ArchiveFile(n, c.length, utf8.encode(c))));
      return a;
    }

    const base = {
      'VERSION': 'abc',
      'TARGET': 'linux-arm64',
      'MODE': 'debug',
      'payload/usr/bin/aera-plugin': 'x',
    };

    test(
      'accepts a debug kit for this engine',
      () => expect(validateAeraKit(kit(base), 'abc'), isNull),
    );
    test(
      'rejects another engine',
      () => expect(validateAeraKit(kit(base), 'def'), contains('engine')),
    );
    test('release needs the host gen_snapshot', () {
      expect(validateAeraKit(kit({...base, 'MODE': 'release'}), 'abc'), contains('gen_snapshot'));
      expect(
        validateAeraKit(kit({...base, 'MODE': 'release', 'host/gen_snapshot': 'g'}), 'abc'),
        isNull,
      );
    });
  });
}
