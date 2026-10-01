@TestOn('linux || mac-os')
library;

import 'package:test/test.dart';
import 'package:{{name.snakeCase()}}_core/src/facts/posix_open.dart';

void main() {
  test('opens what libc can open for reading', () {
    expect(canOpenForReading('/dev/null'), isTrue);
    expect(canOpenForReading('/nonexistent/p0g'), isFalse);
  });
}
