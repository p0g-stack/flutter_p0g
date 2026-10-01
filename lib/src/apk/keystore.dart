/// PKCS#12 keystores (what `keytool` writes by default since JDK 9, and
/// Android's debug keystore) read and written in Dart, and a generated
/// debug key, so APK signing needs no JDK.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'der.dart';
import 'sign_v2.dart';

/// Android's debug key: the alias and passwords Gradle uses.
const kDebugKeyAlias = 'androiddebugkey';
const kDebugKeyPassword = 'android';

/// A new RSA 2048 key with a self-signed certificate, valid 30 years, as
/// Android Gradle Plugin makes its debug key.
ApkSigningKey generateSigningKey({String subject = 'Android Debug', DateTime? now}) {
  final random = _secureRandom();
  final gen = RSAKeyGenerator()
    ..init(ParametersWithRandom(RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64), random));
  final pair = gen.generateKeyPair();
  final pub = pair.publicKey;
  final priv = pair.privateKey;
  final from = (now ?? DateTime.now()).toUtc();
  final to = DateTime.utc(from.year + 30, from.month, from.day);
  final name = Der.seq([
    Der.set([
      Der.seq([Der.oidOf(Oids.commonName), Der.utf8String(subject)]),
    ]),
  ]);
  final sigAlg = Der.seq([Der.oidOf(Oids.sha256WithRsa), Der.nul()]);
  final serial = BigInt.parse(
    List.generate(16, (_) => random.nextUint8().toRadixString(16).padLeft(2, '0')).join(),
    radix: 16,
  );
  Uint8List time(DateTime t) => t.year < 2050 ? Der.utcTime(t) : Der.generalizedTime(t);
  final tbs = Der.seq([
    Der.explicit(0, Der.intOf(2)), // v3
    Der.integerOf(serial),
    sigAlg,
    name,
    Der.seq([time(from), time(to)]),
    name,
    publicKeyInfo(pub),
  ]);
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
  final sig = signer.generateSignature(tbs).bytes;
  return ApkSigningKey(priv, Der.seq([tbs, sigAlg, Der.bits(sig)]));
}

Uint8List publicKeyInfo(RSAPublicKey key) => Der.seq([
  Der.seq([Der.oidOf(Oids.rsaEncryption), Der.nul()]),
  Der.bits(Der.seq([Der.integerOf(key.modulus!), Der.integerOf(key.exponent!)])),
]);

/// Reads the key [alias] (or the only key when [alias] is null) from a
/// PKCS#12 keystore.
ApkSigningKey readPkcs12(
  Uint8List bytes, {
  required String storePassword,
  String? alias,
  String? keyPassword,
}) {
  if (bytes.length >= 4 && bytes[0] == 0xfe && bytes[1] == 0xed && bytes[2] == 0xfe) {
    throw const FormatException(
      'a JKS keystore; convert it to PKCS12 with `keytool -importkeystore '
      '-srckeystore <file> -destkeystore <file>.p12 -deststoretype PKCS12`',
    );
  }
  final pfx = Der.parse(bytes);
  final authSafeBytes = pfx[1][1][0].content;
  if (pfx.children.length > 2) _checkMac(pfx[2], authSafeBytes, storePassword);
  final authSafe = Der.parse(authSafeBytes);
  final keys = <({String? name, Uint8List? id, Uint8List pkcs8})>[];
  final certs = <({String? name, Uint8List? id, Uint8List der})>[];
  for (final info in authSafe.children) {
    final type = info[0].oid;
    List<Der> bags;
    if (type == Oids.data) {
      bags = Der.parse(info[1][0].content).children;
    } else if (type == Oids.encryptedData) {
      final eci = info[1][0][1];
      final plain = _decrypt(eci[1], eci[2].content, storePassword);
      bags = Der.parse(plain).children;
    } else {
      continue;
    }
    for (final bag in bags) {
      final kind = bag[0].oid;
      final value = bag[1][0];
      String? name;
      Uint8List? id;
      if (bag.children.length > 2) {
        for (final attr in bag[2].children) {
          final v = attr[1][0];
          if (attr[0].oid == Oids.friendlyName) {
            name = String.fromCharCodes([
              for (var i = 0; i + 1 < v.content.length; i += 2)
                (v.content[i] << 8) | v.content[i + 1],
            ]);
          } else if (attr[0].oid == Oids.localKeyId) {
            id = v.content;
          }
        }
      }
      if (kind == Oids.shroudedKeyBag) {
        final pkcs8 = _decrypt(value[0], value[1].content, keyPassword ?? storePassword);
        keys.add((name: name, id: id, pkcs8: pkcs8));
      } else if (kind == Oids.keyBag) {
        keys.add((name: name, id: id, pkcs8: value.encoded));
      } else if (kind == Oids.certBag && value[0].oid == Oids.x509Certificate) {
        certs.add((name: name, id: id, der: value[1][0].content));
      }
    }
  }
  if (keys.isEmpty) throw const FormatException('no private key in the keystore');
  final key = alias == null
      ? (keys.length == 1
            ? keys.single
            : throw const FormatException('several keys in the keystore: name the alias'))
      : keys.firstWhere(
          (k) => k.name?.toLowerCase() == alias.toLowerCase(),
          orElse: () => throw FormatException('no key "$alias" in the keystore'),
        );
  final cert = certs.firstWhere(
    (c) => key.id != null && c.id != null && _same(c.id!, key.id!),
    orElse: () => certs.length == 1
        ? certs.single
        : throw const FormatException('no certificate for the key in the keystore'),
  );
  return ApkSigningKey(_rsaFromPkcs8(key.pkcs8), cert.der);
}

/// A PKCS#12 keystore holding [key] under [alias], the way JDK 21's
/// `keytool` writes one (PBES2 with AES-256 and PBKDF2-HMAC-SHA256, an
/// HMAC-SHA256 integrity MAC), readable by `keytool` and Gradle.
Uint8List writePkcs12(ApkSigningKey key, {required String alias, required String password}) {
  final random = _secureRandom();
  final localId = Der.set([
    Der.seq([
      Der.oidOf(Oids.localKeyId),
      Der.set([Der.octets(utf8.encode('Time 1'))]),
    ]),
    Der.seq([
      Der.oidOf(Oids.friendlyName),
      Der.set([Der.bmpString(alias)]),
    ]),
  ]);
  final keySalt = random.nextBytes(16);
  final keyIv = random.nextBytes(16);
  const iterations = 10000;
  final pkcs8 = _pkcs8(key.privateKey);
  final encKey = _pbes2(true, utf8.encode(password), keySalt, iterations, keyIv, pkcs8);
  final pbes2Alg = Der.seq([
    Der.oidOf(Oids.pbes2),
    Der.seq([
      Der.seq([
        Der.oidOf(Oids.pbkdf2),
        Der.seq([
          Der.octets(keySalt),
          Der.intOf(iterations),
          Der.seq([Der.oidOf(Oids.hmacSha256), Der.nul()]),
        ]),
      ]),
      Der.seq([Der.oidOf(Oids.aes256Cbc), Der.octets(keyIv)]),
    ]),
  ]);
  final keyBags = Der.seq([
    Der.seq([
      Der.oidOf(Oids.shroudedKeyBag),
      Der.explicit(0, Der.seq([pbes2Alg, Der.octets(encKey)])),
      localId,
    ]),
  ]);
  final certBags = Der.seq([
    Der.seq([
      Der.oidOf(Oids.certBag),
      Der.explicit(
        0,
        Der.seq([Der.oidOf(Oids.x509Certificate), Der.explicit(0, Der.octets(key.certificate))]),
      ),
      localId,
    ]),
  ]);
  Uint8List dataInfo(Uint8List content) =>
      Der.seq([Der.oidOf(Oids.data), Der.explicit(0, Der.octets(content))]);
  final authSafe = Der.seq([dataInfo(keyBags), dataInfo(certBags)]);
  final macSalt = random.nextBytes(20);
  final macKey = (PKCS12ParametersGenerator(
    SHA256Digest(),
  )..init(_bmpPassword(password), macSalt, iterations)).generateDerivedMacParameters(32);
  final hmac = HMac(SHA256Digest(), 64)..init(macKey);
  final mac = hmac.process(authSafe);
  return Der.seq([
    Der.intOf(3),
    dataInfo(authSafe),
    Der.seq([
      Der.seq([
        Der.seq([Der.oidOf(Oids.sha256), Der.nul()]),
        Der.octets(mac),
      ]),
      Der.octets(macSalt),
      Der.intOf(iterations),
    ]),
  ]);
}

/// Checks the keystore's integrity MAC, which is what tells a wrong store
/// password apart from a damaged file.
void _checkMac(Der macData, Uint8List authSafe, String password) {
  final digestInfo = macData[0];
  final alg = digestInfo[0][0].oid;
  final Digest Function() digest = switch (alg) {
    Oids.sha256 => SHA256Digest.new,
    Oids.sha1 => SHA1Digest.new,
    _ => throw FormatException('keystore MAC digest $alg is not supported'),
  };
  final salt = macData[1].content;
  final iterations = macData.children.length > 2 ? macData[2].smallInt : 1;
  final size = digest().digestSize;
  final macKey = (PKCS12ParametersGenerator(
    digest(),
  )..init(_bmpPassword(password), salt, iterations)).generateDerivedMacParameters(size);
  final mac = (HMac(digest(), 64)..init(macKey)).process(authSafe);
  if (!_same(mac, digestInfo[1].content)) {
    throw const FormatException('wrong keystore password (integrity check failed)');
  }
}

Uint8List _pkcs8(RSAPrivateKey k) {
  // ignore: deprecated_member_use
  final e = k.publicExponent ?? BigInt.from(65537);
  final p = k.p!, q = k.q!, d = k.privateExponent!;
  final rsa = Der.seq([
    Der.intOf(0),
    Der.integerOf(k.modulus!),
    Der.integerOf(e),
    Der.integerOf(d),
    Der.integerOf(p),
    Der.integerOf(q),
    Der.integerOf(d % (p - BigInt.one)),
    Der.integerOf(d % (q - BigInt.one)),
    Der.integerOf(q.modInverse(p)),
  ]);
  return Der.seq([
    Der.intOf(0),
    Der.seq([Der.oidOf(Oids.rsaEncryption), Der.nul()]),
    Der.octets(rsa),
  ]);
}

RSAPrivateKey _rsaFromPkcs8(Uint8List pkcs8) {
  final info = Der.parse(pkcs8);
  if (info[1][0].oid != Oids.rsaEncryption) {
    throw const FormatException('the key is not RSA; APK signing here needs an RSA key');
  }
  final rsa = Der.parse(info[2].content);
  return RSAPrivateKey(rsa[1].integer, rsa[3].integer, rsa[4].integer, rsa[5].integer);
}

Uint8List _decrypt(Der alg, Uint8List data, String password) {
  final oid = alg[0].oid;
  final params = alg[1];
  if (oid == Oids.pbes2) {
    final kdf = params[0];
    final enc = params[1];
    if (kdf[0].oid != Oids.pbkdf2) throw FormatException('PBES2 KDF ${kdf[0].oid}');
    final kp = kdf[1].children;
    final salt = kp[0].content;
    final iterations = kp[1].smallInt;
    final prf = kp.length > 2 && kp.last.tag == 0x30 ? kp.last[0].oid : Oids.hmacSha1;
    final ivDer = enc[1];
    final pw = Uint8List.fromList(utf8.encode(password));
    final Digest digest = prf == Oids.hmacSha256 ? SHA256Digest() : SHA1Digest();
    final encOid = enc[0].oid;
    final keyLen = switch (encOid) {
      Oids.aes256Cbc => 32,
      Oids.aes128Cbc => 16,
      Oids.desEde3Cbc => 24,
      _ => throw FormatException('PBES2 cipher $encOid'),
    };
    final kdfImpl = PBKDF2KeyDerivator(HMac(digest, digest.byteLength == 32 ? 64 : 64))
      ..init(Pbkdf2Parameters(salt, iterations, keyLen));
    final key = kdfImpl.process(pw);
    final BlockCipher cipher = encOid == Oids.desEde3Cbc ? DESedeEngine() : AESEngine();
    return _cbc(cipher, key, ivDer.content, data);
  }
  final salt = params[0].content;
  final iterations = params[1].smallInt;
  final gen = PKCS12ParametersGenerator(SHA1Digest())
    ..init(_bmpPassword(password), salt, iterations);
  switch (oid) {
    case Oids.pbeSha3Des:
      final p = gen.generateDerivedParametersWithIV(24, 8);
      return _cbc(DESedeEngine(), (p.parameters! as KeyParameter).key, p.iv, data);
    case Oids.pbeSha40Rc2 || Oids.pbeSha128Rc2:
      final bits = oid == Oids.pbeSha40Rc2 ? 40 : 128;
      final p = gen.generateDerivedParametersWithIV(bits ~/ 8, 8);
      final key = (p.parameters! as KeyParameter).key;
      final c = CBCBlockCipher(RC2Engine())
        ..init(false, ParametersWithIV(RC2Parameters(key, bits: bits), p.iv));
      return _unpad(_run(c, data));
    default:
      throw FormatException('keystore encryption $oid is not supported');
  }
}

Uint8List _cbc(BlockCipher engine, Uint8List key, Uint8List iv, Uint8List data) {
  final c = CBCBlockCipher(engine)..init(false, ParametersWithIV(KeyParameter(key), iv));
  return _unpad(_run(c, data));
}

Uint8List _pbes2(
  bool encrypt,
  List<int> password,
  Uint8List salt,
  int iterations,
  Uint8List iv,
  Uint8List data,
) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, 32));
  final key = kdf.process(Uint8List.fromList(password));
  final c = CBCBlockCipher(AESEngine())..init(encrypt, ParametersWithIV(KeyParameter(key), iv));
  final pad = 16 - data.length % 16;
  return _run(c, Uint8List.fromList([...data, ...List.filled(pad, pad)]));
}

Uint8List _run(BlockCipher c, Uint8List data) {
  if (data.length % c.blockSize != 0) throw const FormatException('bad ciphertext length');
  final out = Uint8List(data.length);
  for (var i = 0; i < data.length; i += c.blockSize) {
    c.processBlock(data, i, out, i);
  }
  return out;
}

Uint8List _unpad(Uint8List b) {
  final n = b.isEmpty ? 0 : b.last;
  if (n < 1 || n > 16 || n > b.length) {
    throw const FormatException('wrong keystore password (bad padding)');
  }
  return Uint8List.sublistView(b, 0, b.length - n);
}

/// PKCS#12's password encoding: UTF-16BE with a two-byte terminator.
Uint8List _bmpPassword(String password) => Uint8List.fromList([
  for (final c in password.codeUnits) ...[c >> 8, c & 0xff],
  0,
  0,
]);

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

SecureRandom _secureRandom() {
  final seed = Random.secure();
  return FortunaRandom()
    ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => seed.nextInt(256)))));
}
