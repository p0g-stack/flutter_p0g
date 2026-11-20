import 'dart:convert';
import 'dart:typed_data';

/// Binary codec for values crossing the process link.
///
/// Carries the same value types as Flutter's `StandardMessageCodec` (null,
/// bool, int, double, String, Uint8List, Int32List, Float64List, List, Map),
/// which is what Squadron services already restrict themselves to for Web
/// Workers. Anything else must be marshaled by the service (Squadron
/// marshalers) before it reaches the channel.
///
/// The encoding is this package's own and only promises to round-trip with
/// itself; both ends of a link always come from the same app build.
abstract final class PlaceCodec {
  static Uint8List encode(Object? value) {
    final w = _Writer();
    w.value(value);
    return w.takeBytes();
  }

  static Object? decode(Uint8List bytes) {
    final r = _Reader(ByteData.sublistView(bytes));
    final value = r.value();
    if (!r.done) throw const FormatException('trailing bytes in message');
    return value;
  }
}

const _null = 0;
const _true = 1;
const _false = 2;
const _int32 = 3;
const _int64 = 4;
const _float64 = 6;
const _string = 7;
const _uint8List = 8;
const _int32List = 9;
const _float64List = 11;
const _list = 12;
const _map = 13;

const _two32 = 4294967296;
const bool _web = identical(0, 0.0);

// On the web every integral double (Infinity included) `is int`; only the
// exactly representable ones travel as ints, the rest as doubles.
bool _safeWebInt(int v) {
  final n = v as num;
  return n.isFinite && n.abs() <= 9007199254740991;
}

class _Writer {
  final _out = BytesBuilder();
  final _scratch = ByteData(8);

  Uint8List takeBytes() => _out.takeBytes();

  void _byte(int b) => _out.addByte(b);

  void _uint32(int v) {
    _scratch.setUint32(0, v, Endian.little);
    _out.add(_scratch.buffer.asUint8List(0, 4));
  }

  void _int32v(int v) {
    _scratch.setInt32(0, v, Endian.little);
    _out.add(_scratch.buffer.asUint8List(0, 4));
  }

  void _float64v(double v) {
    _scratch.setFloat64(0, v, Endian.little);
    _out.add(_scratch.buffer.asUint8List(0, 8));
  }

  void _size(int n) => _uint32(n);

  void _bytes(Uint8List b) {
    _size(b.length);
    _out.add(b);
  }

  void value(Object? v) {
    if (v == null) {
      _byte(_null);
    } else if (v is bool) {
      _byte(v ? _true : _false);
    } else if (v is int && (!_web || _safeWebInt(v))) {
      if (v >= -0x80000000 && v <= 0x7fffffff) {
        _byte(_int32);
        _int32v(v);
      } else {
        // Two 32-bit halves. Web ints are doubles (exact up to 2^53) and
        // web bit operators truncate to 32 bits, so the web splits with
        // arithmetic; the VM keeps the full 64-bit range with shifts.
        final hi = _web ? (v / _two32).floor() : v >> 32;
        final lo = _web ? v - hi * _two32 : v & 0xffffffff;
        _byte(_int64);
        _uint32(lo);
        _int32v(hi);
      }
    } else if (v is double) {
      _byte(_float64);
      _float64v(v);
    } else if (v is String) {
      _byte(_string);
      _bytes(utf8.encode(v));
    } else if (v is Uint8List) {
      _byte(_uint8List);
      _bytes(v);
    } else if (v is Int32List) {
      _byte(_int32List);
      _bytes(v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes));
    } else if (v is Float64List) {
      _byte(_float64List);
      _bytes(v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes));
    } else if (v is List) {
      _byte(_list);
      _size(v.length);
      for (final e in v) {
        value(e);
      }
    } else if (v is Map) {
      _byte(_map);
      _size(v.length);
      v.forEach((k, e) {
        value(k);
        value(e);
      });
    } else if (v is Iterable) {
      value(v.toList());
    } else {
      throw ArgumentError.value(
        v,
        'value',
        'cannot cross a process link (${v.runtimeType}); marshal it first',
      );
    }
  }
}

class _Reader {
  _Reader(this._data);

  final ByteData _data;
  int _pos = 0;

  bool get done => _pos == _data.lengthInBytes;

  void _need(int n) {
    if (_pos + n > _data.lengthInBytes) {
      throw const FormatException('truncated message');
    }
  }

  int _byte() {
    _need(1);
    return _data.getUint8(_pos++);
  }

  int _uint32() {
    _need(4);
    final v = _data.getUint32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  int _readInt32() {
    _need(4);
    final v = _data.getInt32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  Uint8List _bytes() {
    final n = _uint32();
    _need(n);
    final b = Uint8List.sublistView(_data, _pos, _pos + n);
    _pos += n;
    // Copy so the result owns aligned storage and outlives the frame.
    return Uint8List.fromList(b);
  }

  Object? value() {
    final tag = _byte();
    switch (tag) {
      case _null:
        return null;
      case _true:
        return true;
      case _false:
        return false;
      case _int32:
        return _readInt32();
      case _int64:
        final lo = _uint32();
        final hi = _readInt32();
        return _web ? hi * _two32 + lo : (hi << 32) | lo;
      case _float64:
        _need(8);
        final v = _data.getFloat64(_pos, Endian.little);
        _pos += 8;
        return v;
      case _string:
        return utf8.decode(_bytes());
      case _uint8List:
        return _bytes();
      case _int32List:
        return _bytes().buffer.asInt32List();
      case _float64List:
        return _bytes().buffer.asFloat64List();
      case _list:
        final n = _uint32();
        return List<Object?>.generate(n, (_) => value(), growable: true);
      case _map:
        final n = _uint32();
        final m = <Object?, Object?>{};
        for (var i = 0; i < n; i++) {
          final k = value();
          m[k] = value();
        }
        return m;
      default:
        throw FormatException('unknown value tag $tag');
    }
  }
}
