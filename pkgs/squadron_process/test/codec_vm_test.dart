@TestOn('vm')
library;

import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';

void main() {
  test('64-bit ints keep their full range on the VM', () {
    for (final v in [0x7fffffffffffffff, -0x8000000000000000, 1 << 62, -3]) {
      expect(PlaceCodec.decode(PlaceCodec.encode(v)), v);
    }
  });
}
