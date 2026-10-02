import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_p0g/src/apk/axml.dart';
import 'package:flutter_p0g/src/apk/der.dart';
import 'package:flutter_p0g/src/apk/keystore.dart';
import 'package:flutter_p0g/src/apk/rename_apk.dart';
import 'package:flutter_p0g/src/apk/sign_v2.dart';
import 'package:flutter_p0g/src/apk/zip_apk.dart';
import 'package:flutter_p0g/src/webui/app_plane.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

// A minimal compiled manifest: `<manifest package=...><application
// android:label=@0x7f010000><receiver android:name=.../></application></manifest>`.
Uint8List manifestXml(List<String> extra) {
  final strings = [
    'package',
    'label',
    'name',
    'versionCode',
    'manifest',
    'application',
    'receiver',
    ...extra,
  ];
  int s(String v) => strings.indexOf(v);
  final pool = BytesBuilder();
  final offsets = <int>[];
  for (final str in strings) {
    offsets.add(pool.length);
    pool.add([str.length & 0xff, str.length >> 8]);
    for (final c in str.codeUnits) {
      pool.add([c & 0xff, c >> 8]);
    }
    pool.add([0, 0]);
  }
  while (pool.length % 4 != 0) {
    pool.addByte(0);
  }
  final data = pool.takeBytes();
  final poolChunk = ByteData(28 + strings.length * 4 + data.length)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 28, Endian.little)
    ..setUint32(4, 28 + strings.length * 4 + data.length, Endian.little)
    ..setUint32(8, strings.length, Endian.little)
    ..setUint32(20, 28 + strings.length * 4, Endian.little);
  for (var i = 0; i < offsets.length; i++) {
    poolChunk.setUint32(28 + i * 4, offsets[i], Endian.little);
  }
  final poolBytes = poolChunk.buffer.asUint8List()..setAll(28 + strings.length * 4, data);

  Uint8List start(String name, List<(String, int, int, int)> attrs) {
    final c = ByteData(36 + attrs.length * 20)
      ..setUint16(0, 0x0102, Endian.little)
      ..setUint16(2, 16, Endian.little)
      ..setUint32(4, 36 + attrs.length * 20, Endian.little)
      ..setUint32(16, 0xffffffff, Endian.little)
      ..setUint32(20, s(name), Endian.little)
      ..setUint16(24, 20, Endian.little)
      ..setUint16(26, 20, Endian.little)
      ..setUint16(28, attrs.length, Endian.little);
    for (var i = 0; i < attrs.length; i++) {
      final (attr, raw, type, value) = attrs[i];
      final a = 36 + i * 20;
      c
        ..setUint32(a, 0xffffffff, Endian.little)
        ..setUint32(a + 4, s(attr), Endian.little)
        ..setUint32(a + 8, raw, Endian.little)
        ..setUint16(a + 12, 8, Endian.little)
        ..setUint8(a + 15, type)
        ..setUint32(a + 16, value, Endian.little);
    }
    return c.buffer.asUint8List();
  }

  final body = BytesBuilder()
    ..add(poolBytes)
    ..add(
      start('manifest', [
        ('package', s(extra[0]), 3, s(extra[0])),
        ('versionCode', 0xffffffff, 0x10, 1008),
      ]),
    )
    ..add(start('application', [('label', 0xffffffff, 1, 0x7f010000)]))
    ..add(start('receiver', [('name', s(extra[1]), 3, s(extra[1]))]));
  final bytes = body.takeBytes();
  return Uint8List.fromList([
    ...(ByteData(8)
          ..setUint16(0, 3, Endian.little)
          ..setUint16(2, 8, Endian.little)
          ..setUint32(4, 8 + bytes.length, Endian.little))
        .buffer
        .asUint8List(),
    ...bytes,
  ]);
}

final _base = [
  'com.webui.termux.api',
  'com.termux.api.TermuxApiReceiver',
  'com.webui.termux.api.sharedfiles',
  'com.webui.termux.apix',
];

void main() {
  late ApkSigningKey key;
  setUpAll(() => key = generateSigningKey());

  group('manifest', () {
    test('renames the package and names under it, sets the label', () {
      final out = renameManifestPackage(
        manifestXml(_base),
        from: 'com.webui.termux.api',
        to: 'com.webui.api.demo',
        label: 'Démo',
      );
      expect(
        manifestStrings(out),
        containsAll([
          'com.webui.api.demo',
          'com.webui.api.demo.sharedfiles',
          'com.termux.api.TermuxApiReceiver',
          'com.webui.termux.apix',
        ]),
      );
      expect(manifestStrings(out), isNot(contains('com.webui.termux.api')));
      expect(manifestApplicationLabel(out), 'Démo');
      expect(manifestVersionCode(out), 1008);
      expect(ByteData.sublistView(out).getUint32(4, Endian.little), out.length);
    });

    test('refuses a manifest without the package', () {
      expect(
        () => renameManifestPackage(manifestXml(_base), from: 'org.other', to: 'x.y'),
        throwsFormatException,
      );
    });
  });

  test('zip round trip keeps entries and aligns stored ones', () {
    final entries = [
      ZipEntry.fromBytes('a.txt', utf8.encode('hello' * 100)),
      ZipEntry.fromBytes('resources.arsc', List.filled(33, 7), store: true),
      ZipEntry.fromBytes('lib/x86_64/libx.so', List.filled(10, 1), store: true),
    ];
    final zip = writeAlignedZip(entries);
    final back = readZipEntries(zip);
    expect(back.map((e) => e.name), ['a.txt', 'resources.arsc', 'lib/x86_64/libx.so']);
    expect(utf8.decode(entryBytes(back[0])), 'hello' * 100);
    final d = ByteData.sublistView(zip);
    int dataOffset(String name) {
      for (var p = 0; p < zip.length - 4; p++) {
        if (d.getUint32(p, Endian.little) != 0x04034b50) continue;
        final n = d.getUint16(p + 26, Endian.little);
        if (String.fromCharCodes(zip.sublist(p + 30, p + 30 + n)) == name) {
          return p + 30 + n + d.getUint16(p + 28, Endian.little);
        }
      }
      throw StateError(name);
    }

    expect(dataOffset('resources.arsc') % 4, 0);
    expect(dataOffset('lib/x86_64/libx.so') % 4096, 0);
  });

  group('keystore', () {
    test('PKCS12 written here reads back', () {
      final p12 = writePkcs12(key, alias: 'upload', password: 's3cret');
      final back = readPkcs12(p12, storePassword: 's3cret', alias: 'UPLOAD');
      expect(back.certificate, key.certificate);
      expect(back.privateKey.modulus, key.privateKey.modulus);
    });

    test('a wrong password fails the integrity check', () {
      final p12 = writePkcs12(key, alias: 'upload', password: 's3cret');
      expect(
        () => readPkcs12(p12, storePassword: 'nope'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('password'))),
      );
    });

    test('JKS gets the conversion hint', () {
      expect(
        () => readPkcs12(Uint8List.fromList([0xfe, 0xed, 0xfe, 0xed, 0, 0]), storePassword: 'x'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('keytool'))),
      );
    });

    test('key.properties', () {
      expect(
        parseKeyProperties('# c\nstoreFile=upload.jks\r\nstorePassword = a=b\nkeyAlias:upload\n'),
        {'storeFile': 'upload.jks', 'storePassword': 'a=b', 'keyAlias': 'upload'},
      );
    });
  });

  test('v2 signature block verifies against the certificate key', () {
    final zip = writeAlignedZip([ZipEntry.fromBytes('a', utf8.encode('a'))]);
    final signed = signApkV2(zip, key);
    final d = ByteData.sublistView(signed);
    final eocd = signed.length - 22;
    final cd = d.getUint32(eocd + 16, Endian.little);
    expect(String.fromCharCodes(signed.sublist(cd - 16, cd)), 'APK Sig Block 42');
    final blockSize = d.getUint64(cd - 24, Endian.little);
    final start = cd - blockSize - 8;
    expect(d.getUint64(start, Endian.little), blockSize);
    expect(d.getUint32(start + 16, Endian.little), 0x7109871a);
    // pair value: signers(lp) -> signer(lp) -> signedData(lp) ...
    var p = start + 20 + 8;
    final signedLen = d.getUint32(p, Endian.little);
    final signedData = signed.sublist(p + 4, p + 4 + signedLen);
    p += 4 + signedLen;
    final sigs = p + 4;
    final sigLen = d.getUint32(sigs + 4 + 4, Endian.little);
    final signature = signed.sublist(sigs + 12, sigs + 12 + sigLen);
    final spki = Der.parse(key.publicKeyInfo);
    final rsa = Der.parse(spki[1].content.sublist(1));
    final verifier = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(false, PublicKeyParameter<RSAPublicKey>(RSAPublicKey(rsa[0].integer, rsa[1].integer)));
    expect(verifier.verifySignature(signedData, RSASignature(signature)), isTrue);
  });

  test('renameApk drops the v1 signature and renames the manifest', () {
    final apk = writeAlignedZip([
      ZipEntry.fromBytes('AndroidManifest.xml', manifestXml(_base)),
      ZipEntry.fromBytes('META-INF/MANIFEST.MF', [1]),
      ZipEntry.fromBytes('META-INF/CERT.RSA', [1]),
      ZipEntry.fromBytes('META-INF/services/x', [1]),
      ZipEntry.fromBytes('classes.dex', [1, 2, 3]),
    ]);
    final out = renameApk(
      apk,
      from: kAppPlaneBasePackage,
      to: appPlanePackageName('demo'),
      label: 'Demo',
      key: key,
    );
    final entries = readZipEntries(out);
    expect(entries.map((e) => e.name), [
      'AndroidManifest.xml',
      'META-INF/services/x',
      'classes.dex',
    ]);
    expect(manifestStrings(entryBytes(entries.first)), contains('com.webui.api.demo'));
  });

  test('module naming', () {
    expect(appPlanePackageName('demo'), 'com.webui.api.demo');
    expect(appPlanePackageName('my-mod.x'), 'com.webui.api.my_mod_x');
    expect(appPlanePackageName('2fa'), 'com.webui.api.m2fa');
  });
}
