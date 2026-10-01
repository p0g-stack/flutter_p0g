import 'dart:typed_data';

import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';

Object? roundTrip(Object? v) => PlaceCodec.decode(PlaceCodec.encode(v));

void main() {
  test('scalars round-trip', () {
    for (final v in [
      null,
      true,
      false,
      0,
      -1,
      0x7fffffff,
      -0x80000000,
      0x80000000,
      -0x80000001,
      1 << 52,
      -(1 << 52),
      1.5,
      -0.0,
      double.infinity,
      '',
      'héllo ✓',
    ]) {
      expect(roundTrip(v), v, reason: '$v');
    }
  });

  test('typed data round-trips with its type', () {
    final bytes = Uint8List.fromList([0, 1, 255]);
    expect(roundTrip(bytes), isA<Uint8List>().having((b) => b, 'bytes', bytes));
    final ints = Int32List.fromList([-1, 0, 1 << 30]);
    expect(roundTrip(ints), isA<Int32List>().having((b) => b, 'ints', ints));
    final doubles = Float64List.fromList([0.5, -2.25]);
    expect(
      roundTrip(doubles),
      isA<Float64List>().having((b) => b, 'doubles', doubles),
    );
  });

  test('typed data views encode only their window', () {
    final base = Uint8List.fromList(List.generate(16, (i) => i));
    final view = Int32List.sublistView(base, 4, 12);
    expect(roundTrip(view), [view[0], view[1]]);
  });

  test('collections nest', () {
    final v = {
      'a': [
        1,
        'two',
        {3: null},
      ],
      'b': <Object?>[],
      null: {'deep': Uint8List(3)},
    };
    expect(roundTrip(v), v);
  });

  test('iterables become lists', () {
    expect(roundTrip({1, 2}.map((e) => e * 2)), [2, 4]);
  });

  test('unsupported values name the type', () {
    expect(
      () => PlaceCodec.encode([Object()]),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('marshal'),
        ),
      ),
    );
  });

  test('truncated and trailing input is rejected', () {
    final bytes = PlaceCodec.encode('hello');
    expect(
      () => PlaceCodec.decode(bytes.sublist(0, bytes.length - 1)),
      throwsFormatException,
    );
    expect(
      () => PlaceCodec.decode(Uint8List.fromList([...bytes, 0])),
      throwsFormatException,
    );
    expect(
      () => PlaceCodec.decode(Uint8List.fromList([99])),
      throwsFormatException,
    );
  });
}
