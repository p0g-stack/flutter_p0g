/// Reads an APK's zip entries raw and writes them back the way zipalign
/// lays them out, so the result can take an APK Signature Scheme v2 block.
library;

import 'dart:io' show ZLibDecoder, ZLibEncoder;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

class ZipEntry {
  ZipEntry({
    required this.name,
    required this.method,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.modTime,
    required this.modDate,
    required this.data,
  });

  /// A new entry from [bytes], deflated unless [store].
  factory ZipEntry.fromBytes(String name, List<int> bytes, {bool store = false}) {
    final data = store ? Uint8List.fromList(bytes) : _rawDeflate(bytes);
    return ZipEntry(
      name: name,
      method: store ? 0 : 8,
      crc32: getCrc32(bytes),
      compressedSize: data.length,
      uncompressedSize: bytes.length,
      // 1980-01-01 00:00, as apksigner and Gradle write.
      modTime: 0,
      modDate: (0 << 9) | (1 << 5) | 1,
      data: data,
    );
  }

  final String name;
  final int method;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int modTime;
  final int modDate;

  /// The entry's data as stored (deflated or not).
  final Uint8List data;
}

Uint8List _rawDeflate(List<int> bytes) =>
    Uint8List.fromList(ZLibEncoder(raw: true, level: 9).convert(bytes));

/// The entries of [zip], in central directory order.
List<ZipEntry> readZipEntries(Uint8List zip) {
  final d = ByteData.sublistView(zip);
  final eocd = _findEocd(d);
  final count = d.getUint16(eocd + 10, Endian.little);
  var p = d.getUint32(eocd + 16, Endian.little);
  final out = <ZipEntry>[];
  for (var i = 0; i < count; i++) {
    if (d.getUint32(p, Endian.little) != 0x02014b50) {
      throw const FormatException('bad central directory');
    }
    final method = d.getUint16(p + 10, Endian.little);
    final time = d.getUint16(p + 12, Endian.little);
    final date = d.getUint16(p + 14, Endian.little);
    final crc = d.getUint32(p + 16, Endian.little);
    final csize = d.getUint32(p + 20, Endian.little);
    final usize = d.getUint32(p + 24, Endian.little);
    final nameLen = d.getUint16(p + 28, Endian.little);
    final extraLen = d.getUint16(p + 30, Endian.little);
    final commentLen = d.getUint16(p + 32, Endian.little);
    final local = d.getUint32(p + 42, Endian.little);
    final name = String.fromCharCodes(zip.sublist(p + 46, p + 46 + nameLen));
    final localName = d.getUint16(local + 26, Endian.little);
    final localExtra = d.getUint16(local + 28, Endian.little);
    final start = local + 30 + localName + localExtra;
    out.add(
      ZipEntry(
        name: name,
        method: method,
        crc32: crc,
        compressedSize: csize,
        uncompressedSize: usize,
        modTime: time,
        modDate: date,
        data: Uint8List.fromList(zip.sublist(start, start + csize)),
      ),
    );
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

int _findEocd(ByteData d) {
  for (var p = d.lengthInBytes - 22; p >= 0 && p >= d.lengthInBytes - 22 - 0xffff; p--) {
    if (d.getUint32(p, Endian.little) == 0x06054b50) return p;
  }
  throw const FormatException('not a zip (no end of central directory)');
}

/// Uncompressed data of a stored or deflated [entry].
Uint8List entryBytes(ZipEntry entry) {
  if (entry.method == 0) return entry.data;
  if (entry.method != 8) throw FormatException('${entry.name}: zip method ${entry.method}');
  return Uint8List.fromList(ZLibDecoder(raw: true).convert(entry.data));
}

/// Writes [entries] as a zip: stored entries aligned to 4 bytes (shared
/// libraries to 4096), with the padding in the local header's extra field,
/// as zipalign does.
Uint8List writeAlignedZip(List<ZipEntry> entries) {
  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  for (final e in entries) {
    final name = e.name.codeUnits;
    final offset = out.length;
    var extra = 0;
    if (e.method == 0) {
      final align = e.name.endsWith('.so') ? 4096 : 4;
      final dataStart = offset + 30 + name.length;
      extra = (align - dataStart % align) % align;
    }
    final h = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, e.method == 0 ? 10 : 20, Endian.little)
      ..setUint16(6, 0x0800, Endian.little) // UTF-8 names, sizes in header
      ..setUint16(8, e.method, Endian.little)
      ..setUint16(10, e.modTime, Endian.little)
      ..setUint16(12, e.modDate, Endian.little)
      ..setUint32(14, e.crc32, Endian.little)
      ..setUint32(18, e.compressedSize, Endian.little)
      ..setUint32(22, e.uncompressedSize, Endian.little)
      ..setUint16(26, name.length, Endian.little)
      ..setUint16(28, extra, Endian.little);
    out
      ..add(h.buffer.asUint8List())
      ..add(name)
      ..add(Uint8List(extra))
      ..add(e.data);
    final c = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 0x0314, Endian.little) // made by: unix, 2.0
      ..setUint16(6, e.method == 0 ? 10 : 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(10, e.method, Endian.little)
      ..setUint16(12, e.modTime, Endian.little)
      ..setUint16(14, e.modDate, Endian.little)
      ..setUint32(16, e.crc32, Endian.little)
      ..setUint32(20, e.compressedSize, Endian.little)
      ..setUint32(24, e.uncompressedSize, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(38, 0x81a40000, Endian.little) // -rw-r--r--
      ..setUint32(42, offset, Endian.little);
    central
      ..add(c.buffer.asUint8List())
      ..add(name);
  }
  final cdOffset = out.length;
  final cd = central.takeBytes();
  out.add(cd);
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, cd.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.takeBytes();
}
