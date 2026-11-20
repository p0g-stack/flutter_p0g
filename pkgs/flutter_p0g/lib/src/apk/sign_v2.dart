/// APK Signature Scheme v2 (https://source.android.com/docs/security/features/apksigning/v2),
/// RSASSA-PKCS1-v1_5 with SHA-256, one signer.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import 'der.dart';

const _v2BlockId = 0x7109871a;
const _rsaPkcs1Sha256 = 0x0103;
const _chunk = 1024 * 1024;
const _magic = 'APK Sig Block 42';

/// A signing key: the RSA private key and its X.509 certificate (DER).
class ApkSigningKey {
  ApkSigningKey(this.privateKey, this.certificate);

  final RSAPrivateKey privateKey;
  final Uint8List certificate;

  /// SubjectPublicKeyInfo, as the certificate carries it.
  Uint8List get publicKeyInfo => Der.parse(certificate)[0].children
      .firstWhere(
        (e) => e.tag == 0x30 && e.children.length == 2 && e[0].tag == 0x30 && e[1].tag == 0x03,
      )
      .encoded;
}

/// [zip] (no signing block yet, as [writeAlignedZip] writes it) with a v2
/// signing block from [key] in front of the central directory.
Uint8List signApkV2(Uint8List zip, ApkSigningKey key) {
  final d = ByteData.sublistView(zip);
  final eocd = _findEocd(d);
  final cdOffset = d.getUint32(eocd + 16, Endian.little);
  final entries = Uint8List.sublistView(zip, 0, cdOffset);
  final cd = Uint8List.sublistView(zip, cdOffset, eocd);
  final eocdBytes = Uint8List.fromList(zip.sublist(eocd));

  final digest = _contentDigest([entries, cd, eocdBytes]);
  final signedData = _lp(
    _cat([
      _lp(_lp(_cat([_u32(_rsaPkcs1Sha256), _lp(digest)]))), // digests
      _lp(_lp(key.certificate)), // certificates
      _lp(const []), // additional attributes
    ]),
  );
  // The signature covers the signed data without its own length prefix.
  final signedBody = Uint8List.sublistView(signedData, 4);
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(key.privateKey));
  final signature = signer.generateSignature(signedBody).bytes;
  final signerBlock = _cat([
    signedData,
    _lp(_lp(_cat([_u32(_rsaPkcs1Sha256), _lp(signature)]))),
    _lp(key.publicKeyInfo),
  ]);
  final value = _lp(_lp(signerBlock));

  final pair = _cat([_u64(4 + value.length), _u32(_v2BlockId), value]);
  final blockSize = pair.length + 8 + 16;
  final block = _cat([_u64(blockSize), pair, _u64(blockSize), _magic.codeUnits]);

  final out = BytesBuilder(copy: false)
    ..add(entries)
    ..add(block)
    ..add(cd);
  final newEocd = Uint8List.fromList(eocdBytes);
  ByteData.sublistView(newEocd).setUint32(16, cdOffset + block.length, Endian.little);
  out.add(newEocd);
  return out.takeBytes();
}

Uint8List _contentDigest(List<Uint8List> sections) {
  final chunkDigests = BytesBuilder(copy: false);
  var count = 0;
  for (final s in sections) {
    for (var i = 0; i < s.length; i += _chunk) {
      final part = Uint8List.sublistView(s, i, i + _chunk > s.length ? s.length : i + _chunk);
      chunkDigests.add(
        sha256
            .convert(
              _cat([
                const [0xa5],
                _u32(part.length),
                part,
              ]),
            )
            .bytes,
      );
      count++;
    }
  }
  return Uint8List.fromList(
    sha256
        .convert(
          _cat([
            const [0x5a],
            _u32(count),
            chunkDigests.takeBytes(),
          ]),
        )
        .bytes,
  );
}

int _findEocd(ByteData d) {
  for (var p = d.lengthInBytes - 22; p >= 0; p--) {
    if (d.getUint32(p, Endian.little) == 0x06054b50) return p;
  }
  throw const FormatException('not a zip');
}

Uint8List _u32(int v) => (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();
Uint8List _u64(int v) => (ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List();
Uint8List _lp(List<int> b) => _cat([_u32(b.length), b]);
Uint8List _cat(List<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return b.takeBytes();
}
