/// Rewrites a compiled (binary XML) AndroidManifest.xml in place of aapt2's
/// `--rename-manifest-package`: the package and every package-scoped name,
/// and the application label.
library;

import 'dart:convert' as convert;
import 'dart:typed_data';

const _resXmlType = 0x0003;
const _stringPoolType = 0x0001;
const _startElementType = 0x0102;
const _utf8Flag = 0x100;
const _typeString = 0x03;

/// [manifest] with [from] renamed to [to] in every string that is exactly
/// [from] or starts with `[from].` (the package, authorities, permissions),
/// and `<application android:label>` set to [label] when given. Class names
/// in other packages are untouched.
Uint8List renameManifestPackage(
  Uint8List manifest, {
  required String from,
  required String to,
  String? label,
}) {
  final d = ByteData.sublistView(manifest);
  if (d.getUint16(0, Endian.little) != _resXmlType) {
    throw const FormatException('not a binary XML manifest');
  }
  final poolStart = d.getUint16(2, Endian.little);
  if (d.getUint16(poolStart, Endian.little) != _stringPoolType) {
    throw const FormatException('binary XML without a string pool first');
  }
  final pool = _StringPool.read(d, poolStart);
  final poolEnd = poolStart + d.getUint32(poolStart + 4, Endian.little);

  var renamed = 0;
  for (var i = 0; i < pool.strings.length; i++) {
    final s = pool.strings[i];
    if (s == from || s.startsWith('$from.')) {
      pool.strings[i] = to + s.substring(from.length);
      renamed++;
    }
  }
  if (renamed == 0) throw FormatException('no "$from" in the manifest');

  // The rest of the document, edited after the pool is rebuilt; the label
  // string is appended so existing indices (and the resource map) hold.
  final rest = Uint8List.fromList(manifest.sublist(poolEnd));
  if (label != null) {
    final labelIndex = pool.strings.length;
    pool.strings.add(label);
    if (!_setApplicationLabel(rest, pool.strings, labelIndex)) {
      throw const FormatException('no <application> element in the manifest');
    }
  }

  final newPool = pool.write();
  final out = BytesBuilder(copy: false)
    ..add(manifest.sublist(0, poolStart))
    ..add(newPool)
    ..add(rest);
  final bytes = out.takeBytes();
  ByteData.sublistView(bytes).setUint32(4, bytes.length, Endian.little);
  return bytes;
}

/// Points `android:label` on `<application>` at string [labelIndex].
bool _setApplicationLabel(Uint8List rest, List<String> strings, int labelIndex) {
  final d = ByteData.sublistView(rest);
  var p = 0;
  while (p + 8 <= rest.length) {
    final type = d.getUint16(p, Endian.little);
    final size = d.getUint32(p + 4, Endian.little);
    if (size < 8) throw const FormatException('bad chunk size');
    if (type == _startElementType) {
      final headerSize = d.getUint16(p + 2, Endian.little);
      final ext = p + headerSize;
      final name = d.getUint32(ext + 4, Endian.little);
      if (strings[name] == 'application') {
        final attrStart = d.getUint16(ext + 8, Endian.little);
        final attrSize = d.getUint16(ext + 10, Endian.little);
        final attrCount = d.getUint16(ext + 12, Endian.little);
        for (var i = 0; i < attrCount; i++) {
          final a = ext + attrStart + i * attrSize;
          if (strings[d.getUint32(a + 4, Endian.little)] != 'label') continue;
          d.setUint32(a + 8, labelIndex, Endian.little); // rawValue
          d.setUint8(a + 15, _typeString); // Res_value.dataType
          d.setUint32(a + 16, labelIndex, Endian.little); // Res_value.data
          return true;
        }
        throw const FormatException('<application> has no android:label to replace');
      }
    }
    p += size;
  }
  return false;
}

class _StringPool {
  _StringPool(this.strings, this.utf8, this.styleOffsets, this.styleData, this.flags);

  factory _StringPool.read(ByteData d, int start) {
    final headerSize = d.getUint16(start + 2, Endian.little);
    final count = d.getUint32(start + 8, Endian.little);
    final styleCount = d.getUint32(start + 12, Endian.little);
    final flags = d.getUint32(start + 16, Endian.little);
    final stringsStart = d.getUint32(start + 20, Endian.little);
    final stylesStart = d.getUint32(start + 24, Endian.little);
    final size = d.getUint32(start + 4, Endian.little);
    final isUtf8 = flags & _utf8Flag != 0;
    final strings = <String>[];
    for (var i = 0; i < count; i++) {
      final off = d.getUint32(start + headerSize + i * 4, Endian.little);
      var p = start + stringsStart + off;
      if (isUtf8) {
        p += (d.getUint8(p) & 0x80) != 0 ? 2 : 1; // UTF-16 length
        var n = d.getUint8(p++);
        if (n & 0x80 != 0) n = ((n & 0x7f) << 8) | d.getUint8(p++);
        strings.add(convert.utf8.decode(d.buffer.asUint8List(d.offsetInBytes + p, n)));
      } else {
        var n = d.getUint16(p, Endian.little);
        p += 2;
        if (n & 0x8000 != 0) {
          n = ((n & 0x7fff) << 16) | d.getUint16(p, Endian.little);
          p += 2;
        }
        strings.add(
          String.fromCharCodes([for (var k = 0; k < n; k++) d.getUint16(p + k * 2, Endian.little)]),
        );
      }
    }
    final styleOffsets = [
      for (var i = 0; i < styleCount; i++)
        d.getUint32(start + headerSize + count * 4 + i * 4, Endian.little),
    ];
    final styleData = styleCount == 0
        ? Uint8List(0)
        : Uint8List.fromList(
            d.buffer.asUint8List(d.offsetInBytes + start + stylesStart, size - stylesStart),
          );
    return _StringPool(strings, isUtf8, styleOffsets, styleData, flags);
  }

  final List<String> strings;
  final bool utf8;
  final List<int> styleOffsets;
  final Uint8List styleData;
  final int flags;

  Uint8List write() {
    final data = BytesBuilder(copy: false);
    final offsets = <int>[];
    for (final s in strings) {
      offsets.add(data.length);
      data.add(utf8 ? _utf8Entry(s) : _utf16Entry(s));
    }
    while (data.length % 4 != 0) {
      data.addByte(0);
    }
    const headerSize = 28;
    final stringsStart = headerSize + strings.length * 4 + styleOffsets.length * 4;
    final stylesStart = styleOffsets.isEmpty ? 0 : stringsStart + data.length;
    final size = stringsStart + data.length + styleData.length;
    final out = ByteData(size);
    out
      ..setUint16(0, _stringPoolType, Endian.little)
      ..setUint16(2, headerSize, Endian.little)
      ..setUint32(4, size, Endian.little)
      ..setUint32(8, strings.length, Endian.little)
      ..setUint32(12, styleOffsets.length, Endian.little)
      // Not sorted any more; keep the encoding flag only.
      ..setUint32(16, flags & _utf8Flag, Endian.little)
      ..setUint32(20, stringsStart, Endian.little)
      ..setUint32(24, stylesStart, Endian.little);
    for (var i = 0; i < offsets.length; i++) {
      out.setUint32(headerSize + i * 4, offsets[i], Endian.little);
    }
    for (var i = 0; i < styleOffsets.length; i++) {
      out.setUint32(headerSize + offsets.length * 4 + i * 4, styleOffsets[i], Endian.little);
    }
    final bytes = out.buffer.asUint8List();
    bytes.setRange(stringsStart, stringsStart + data.length, data.takeBytes());
    if (styleData.isNotEmpty) bytes.setRange(stylesStart, size, styleData);
    return bytes;
  }

  static List<int> _utf16Entry(String s) {
    final units = s.codeUnits;
    final n = units.length;
    final b = BytesBuilder();
    void u16(int v) => b.add([v & 0xff, v >> 8]);
    if (n > 0x7fff) {
      u16(0x8000 | (n >> 16));
      u16(n & 0xffff);
    } else {
      u16(n);
    }
    units.forEach(u16);
    u16(0);
    return b.takeBytes();
  }

  static List<int> _utf8Entry(String s) {
    final bytes = const convert.Utf8Encoder().convert(s);
    List<int> len(int n) => n > 0x7f ? [0x80 | (n >> 8), n & 0xff] : [n];
    return [...len(s.length), ...len(bytes.length), ...bytes, 0];
  }
}

/// The strings of a binary XML document, for tests and diagnostics.
List<String> manifestStrings(Uint8List manifest) {
  final d = ByteData.sublistView(manifest);
  return _StringPool.read(d, d.getUint16(2, Endian.little)).strings;
}

/// `<application android:label>` as a plain string, or null when it is a
/// resource reference.
String? manifestApplicationLabel(Uint8List manifest) {
  final d = ByteData.sublistView(manifest);
  final poolStart = d.getUint16(2, Endian.little);
  final strings = _StringPool.read(d, poolStart).strings;
  var p = poolStart + d.getUint32(poolStart + 4, Endian.little);
  while (p + 8 <= manifest.length) {
    final size = d.getUint32(p + 4, Endian.little);
    if (d.getUint16(p, Endian.little) == _startElementType) {
      final ext = p + d.getUint16(p + 2, Endian.little);
      if (strings[d.getUint32(ext + 4, Endian.little)] == 'application') {
        final attrStart = d.getUint16(ext + 8, Endian.little);
        final attrSize = d.getUint16(ext + 10, Endian.little);
        for (var i = 0; i < d.getUint16(ext + 12, Endian.little); i++) {
          final a = ext + attrStart + i * attrSize;
          if (strings[d.getUint32(a + 4, Endian.little)] == 'label') {
            return d.getUint8(a + 15) == _typeString
                ? strings[d.getUint32(a + 16, Endian.little)]
                : null;
          }
        }
        return null;
      }
    }
    p += size;
  }
  return null;
}
