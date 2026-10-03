import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_p0g/src/aera/aerap.dart';
import 'package:flutter_p0g/src/aera/kit.dart';
import 'package:flutter_p0g/src/templates.dart';
import 'package:test/test.dart';

/// Reads the runtime stream back with AERA's exact rule (`Extract()` in
/// aeraui/features/browser/runtime.cpp at abf3316): after each name, zeros
/// up to the next 4-byte offset of the whole stream; nothing after a body.
List<(String, int, List<int>)> readStream(Uint8List s) {
  final d = ByteData.sublistView(s);
  expect(ascii.decode(s.sublist(0, 8)), 'AERAWEB1');
  final count = d.getUint32(8, Endian.little);
  var total = 12;
  final out = <(String, int, List<int>)>[];
  for (var i = 0; i < count; i++) {
    final length = d.getUint16(total, Endian.little);
    final mode = d.getUint16(total + 2, Endian.little);
    final size = d.getUint64(total + 4, Endian.little);
    total += 12;
    expect(length, inInclusiveRange(1, 239));
    expect(size, lessThanOrEqualTo(100 * 1024 * 1024));
    expect(mode, anyOf(0, 0x1a4, 0x1ed));
    final name = utf8.decode(s.sublist(total, total + length));
    total += length;
    final padding = (4 - total % 4) % 4;
    expect(s.sublist(total, total + padding), everyElement(0), reason: 'padding after $name');
    total += padding;
    out.add((name, mode, s.sublist(total, total + size)));
    total += size;
  }
  expect(total, s.length);
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

  test('runtime stream pads names to the stream offset when bodies are unaligned', () {
    final members = [
      for (final (i, size) in [1, 2, 3, 5, 6750, 0, 7].indexed)
        RuntimeMember('m$i/${'n' * (i + 1)}', List.filled(size, i + 1)),
    ];
    final read = readStream(runtimeStream(members));
    expect(read.map((m) => m.$3.length), [1, 2, 3, 5, 6750, 0, 7]);
    for (final (i, m) in read.indexed) {
      expect(m.$3, everyElement(i + 1));
    }
  });

  test('runtime stream rejects duplicates and escaping names', () {
    expect(
      () => runtimeStream([RuntimeMember('a', []), RuntimeMember('a', [])]),
      throwsArgumentError,
    );
    expect(() => runtimeStream([RuntimeMember('../x', [])]), throwsArgumentError);
    expect(() => runtimeStream([RuntimeMember('/x', [])]), throwsArgumentError);
    expect(() => runtimeStream([RuntimeMember('a' * 240, [])]), throwsArgumentError);
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
      expect(m['protocol_version'], 3);
      expect(m['permissions'], containsAll(['display', 'touch-input', 'pixel-surface']));
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

    String meta({String mode = 'debug', String engine = 'abc'}) => jsonEncode({
      'kit': 1,
      'arch': 'arm64',
      'mode': mode,
      'flutter': '3.47.5',
      'engine_revision': engine,
    });

    test('accepts the released debug kit layout', () {
      final k = kit({'kit.json': meta(), 'usr/bin/aera-plugin': 'x'});
      expect(validateAeraKit(k, 'abc'), isNull);
      expect(kitTarget(k), 'linux-arm64');
      expect(kitMode(k), 'debug');
    });

    test('rejects another engine', () {
      expect(
        validateAeraKit(kit({'kit.json': meta(engine: 'def'), 'usr/bin/aera-plugin': 'x'}), 'abc'),
        contains('engine'),
      );
    });

    test('release needs the host gen_snapshot', () {
      final base = {'kit.json': meta(mode: 'release'), 'usr/bin/aera-plugin': 'x'};
      expect(validateAeraKit(kit(base), 'abc'), contains('gen_snapshot'));
      expect(validateAeraKit(kit({...base, 'host/gen_snapshot': 'g'}), 'abc'), isNull);
    });

    test('kit.json and host/ stay out of the payload', () {
      expect(isKitMetadata('kit.json'), isTrue);
      expect(isKitMetadata('host/gen_snapshot'), isTrue);
      expect(isKitMetadata('usr/lib/libc.so.6'), isFalse);
    });

    test('release URL', () {
      expect(
        aeraKitUrl('3.47.5', 'debug'),
        'https://github.com/p0g-stack/flutter-aera/releases/download/kit-3.47.5/'
        'flutter-aera-kit-linux-arm64-debug-3.47.5.tar.xz',
      );
    });
  });

  group('viewJson', () {
    test('the app\'s padding, in dp, edges as given', () {
      expect(
        jsonDecode(
          viewJson({
            'id': 'x',
            'padding': {'left': 4, 'top': 0, 'right': 4, 'bottom': 8},
          })!,
        ),
        {
          'padding': {'left': 4, 'top': 0, 'right': 4, 'bottom': 8},
        },
      );
      expect(
        jsonDecode(
          viewJson({
            'padding': {'bottom': 12.5},
          })!,
        ),
        {
          'padding': {'bottom': 12.5},
        },
      );
    });

    test('no padding key: no file, so the embedder falls through', () {
      expect(viewJson({'id': 'x'}), isNull);
    });

    test('bad padding is refused', () {
      for (final bad in [
        4,
        {'middle': 1},
        {'left': -1},
        {'left': '4'},
      ]) {
        expect(() => viewJson({'padding': bad}), throwsFormatException, reason: '$bad');
      }
    });
  });
}
