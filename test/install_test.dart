import 'package:flutter_p0g/src/commands/install.dart';
import 'package:test/test.dart';

void main() {
  test('shellQuote', () {
    expect(shellQuote('a b'), "'a b'");
    expect(shellQuote("it's"), r"'it'\''s'");
  });

  test('installScript probes ksud, apd, then magisk', () {
    final s = installScript('/data/local/tmp/c-v1.zip');
    expect(
      s,
      startsWith(
        "if [ -e /data/adb/ksud ]; then /data/adb/ksud module install '/data/local/tmp/c-v1.zip'",
      ),
    );
    expect(s.indexOf('/data/adb/apd'), greaterThan(s.indexOf('/data/adb/ksud')));
    expect(s.indexOf('magisk --install-module'), greaterThan(s.indexOf('/data/adb/apd')));
    expect(s, endsWith('exit 3; fi'));
  });
}
