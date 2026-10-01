/// Makes a module's own copy of an APK: a new package name and label,
/// zip-aligned and signed with APK Signature Scheme v2.
library;

import 'dart:typed_data';

import 'axml.dart';
import 'sign_v2.dart';
import 'zip_apk.dart';

final _v1Signature = RegExp(r'^META-INF/([^/]+\.(SF|RSA|DSA|EC)|MANIFEST\.MF)$');

/// [apk] with package [from] renamed to [to] (and every manifest name under
/// `[from].`), its application label set to [label], the old v1 signature
/// dropped and a v2 signature from [key].
Uint8List renameApk(
  Uint8List apk, {
  required String from,
  required String to,
  required String label,
  required ApkSigningKey key,
}) {
  final entries = [
    for (final e in readZipEntries(apk))
      if (!_v1Signature.hasMatch(e.name))
        e.name == 'AndroidManifest.xml'
            ? ZipEntry.fromBytes(
                e.name,
                renameManifestPackage(entryBytes(e), from: from, to: to, label: label),
              )
            : e,
  ];
  return signApkV2(writeAlignedZip(entries), key);
}
