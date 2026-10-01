/// The DER subset the APK signer needs: X.509 certificates, PKCS#8 keys and
/// PKCS#12 keystores, read and written.
library;

import 'dart:convert';
import 'dart:typed_data';

class Der {
  Der(this.tag, this.content);

  /// Parses one element from [bytes] at [offset]; [end] is set past it.
  factory Der.parse(List<int> bytes, [int offset = 0]) => _parse(bytes, offset).$1;

  /// Every element in [bytes], one after the other.
  static List<Der> parseAll(List<int> bytes) {
    final out = <Der>[];
    var i = 0;
    while (i < bytes.length) {
      final (der, next) = _parse(bytes, i);
      out.add(der);
      i = next;
    }
    return out;
  }

  static (Der, int) _parse(List<int> b, int i) {
    if (i + 2 > b.length) throw const FormatException('DER: truncated');
    final tag = b[i++];
    var len = b[i++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      if (n == 0 || n > 4 || i + n > b.length) throw const FormatException('DER: bad length');
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | b[i++];
      }
    }
    if (i + len > b.length) throw const FormatException('DER: truncated');
    return (Der(tag, Uint8List.fromList(b.sublist(i, i + len))), i + len);
  }

  final int tag;
  final Uint8List content;

  bool get constructed => tag & 0x20 != 0;

  /// Children of a constructed element (SEQUENCE, SET, [n] EXPLICIT).
  List<Der> get children => parseAll(content);
  Der operator [](int i) => children[i];

  BigInt get integer {
    var v = BigInt.zero;
    for (final x in content) {
      v = (v << 8) | BigInt.from(x);
    }
    if (content.isNotEmpty && content[0] & 0x80 != 0) {
      v -= BigInt.one << (content.length * 8);
    }
    return v;
  }

  int get smallInt => integer.toInt();

  String get oid {
    final parts = <int>[content[0] ~/ 40, content[0] % 40];
    var v = 0;
    for (final x in content.skip(1)) {
      v = (v << 7) | (x & 0x7f);
      if (x & 0x80 == 0) {
        parts.add(v);
        v = 0;
      }
    }
    return parts.join('.');
  }

  /// The encoded element, header included.
  Uint8List get encoded => _tlv(tag, content);

  // Encoders.
  static Uint8List seq(List<List<int>> items) => _tlv(0x30, _cat(items));
  static Uint8List set(List<List<int>> items) => _tlv(0x31, _cat(items));
  static Uint8List explicit(int n, List<int> inner) => _tlv(0xa0 | n, inner);
  static Uint8List implicitConstructed(int n, List<List<int>> items) => _tlv(0xa0 | n, _cat(items));
  static Uint8List octets(List<int> b) => _tlv(0x04, b);
  static Uint8List bits(List<int> b) => _tlv(0x03, [0, ...b]);
  static Uint8List nul() => _tlv(0x05, const []);
  static Uint8List utf8String(String s) => _tlv(0x0c, utf8.encode(s));
  static Uint8List bmpString(String s) => _tlv(0x1e, [
    for (final c in s.codeUnits) ...[c >> 8, c & 0xff],
  ]);
  static Uint8List utcTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final u = t.toUtc();
    return _tlv(
      0x17,
      ascii.encode(
        '${two(u.year % 100)}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z',
      ),
    );
  }

  static Uint8List generalizedTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final u = t.toUtc();
    return _tlv(
      0x18,
      ascii.encode(
        '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z',
      ),
    );
  }

  static Uint8List integerOf(BigInt v) {
    if (v.isNegative) throw ArgumentError('negative INTEGER');
    var bytes = <int>[];
    var x = v;
    while (x > BigInt.zero) {
      bytes.insert(0, (x & BigInt.from(0xff)).toInt());
      x >>= 8;
    }
    if (bytes.isEmpty || bytes[0] & 0x80 != 0) bytes.insert(0, 0);
    return _tlv(0x02, bytes);
  }

  static Uint8List intOf(int v) => integerOf(BigInt.from(v));

  static Uint8List oidOf(String dotted) {
    final p = dotted.split('.').map(int.parse).toList();
    final out = <int>[p[0] * 40 + p[1]];
    for (final v in p.skip(2)) {
      final groups = <int>[];
      var x = v;
      do {
        groups.insert(0, x & 0x7f);
        x >>= 7;
      } while (x > 0);
      for (var i = 0; i < groups.length; i++) {
        out.add(groups[i] | (i < groups.length - 1 ? 0x80 : 0));
      }
    }
    return _tlv(0x06, out);
  }

  static Uint8List _cat(List<List<int>> items) {
    final b = BytesBuilder(copy: false);
    for (final i in items) {
      b.add(i);
    }
    return b.takeBytes();
  }

  static Uint8List _tlv(int tag, List<int> content) {
    final n = content.length;
    final head = <int>[tag];
    if (n < 0x80) {
      head.add(n);
    } else {
      final len = <int>[];
      var x = n;
      while (x > 0) {
        len.insert(0, x & 0xff);
        x >>= 8;
      }
      head
        ..add(0x80 | len.length)
        ..addAll(len);
    }
    return Uint8List.fromList([...head, ...content]);
  }
}

/// Object identifiers used here.
abstract final class Oids {
  static const rsaEncryption = '1.2.840.113549.1.1.1';
  static const sha256WithRsa = '1.2.840.113549.1.1.11';
  static const commonName = '2.5.4.3';
  static const data = '1.2.840.113549.1.7.1';
  static const encryptedData = '1.2.840.113549.1.7.6';
  static const keyBag = '1.2.840.113549.1.12.10.1.1';
  static const shroudedKeyBag = '1.2.840.113549.1.12.10.1.2';
  static const certBag = '1.2.840.113549.1.12.10.1.3';
  static const x509Certificate = '1.2.840.113549.1.9.22.1';
  static const friendlyName = '1.2.840.113549.1.9.20';
  static const localKeyId = '1.2.840.113549.1.9.21';
  static const pbeSha3Des = '1.2.840.113549.1.12.1.3';
  static const pbeSha40Rc2 = '1.2.840.113549.1.12.1.6';
  static const pbeSha128Rc2 = '1.2.840.113549.1.12.1.5';
  static const pbes2 = '1.2.840.113549.1.5.13';
  static const pbkdf2 = '1.2.840.113549.1.5.12';
  static const hmacSha1 = '1.2.840.113549.2.7';
  static const hmacSha256 = '1.2.840.113549.2.9';
  static const aes128Cbc = '2.16.840.1.101.3.4.1.2';
  static const aes256Cbc = '2.16.840.1.101.3.4.1.42';
  static const desEde3Cbc = '1.2.840.113549.3.7';
  static const sha1 = '1.3.14.3.2.26';
  static const sha256 = '2.16.840.1.101.3.4.2.1';
}
