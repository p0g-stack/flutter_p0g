import 'package:file/memory.dart';
import 'package:flutter_p0g/src/aera/rust.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:test/test.dart';

void main() {
  const arm = 'aarch64-unknown-linux-gnu';
  const key = 'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER';

  test('target platforms map to glibc Rust targets', () {
    expect(aeraRustTriple('linux-arm64'), arm);
    expect(aeraRustTriple('linux-x64'), 'x86_64-unknown-linux-gnu');
    expect(() => aeraRustTriple('android-arm64'), throwsA(isA<ToolExit>()));
  });

  group('aeraRustEnvironment', () {
    test('sets the cross linker when it is on PATH', () {
      expect(aeraRustEnvironment(arm, const {}, (p) => p == 'aarch64-linux-gnu-gcc'), {
        key: 'aarch64-linux-gnu-gcc',
      });
    });

    test('keeps a linker the user set', () {
      expect(aeraRustEnvironment(arm, const {key: 'clang'}, (_) => false), isEmpty);
    });

    test('names the requirement when the linker is missing', () {
      expect(
        () => aeraRustEnvironment(arm, const {}, (_) => false),
        throwsA(
          isA<ToolExit>().having((e) => e.message, 'message', contains('aarch64-linux-gnu-gcc')),
        ),
      );
    });

    test('x86_64 links with the host linker', () {
      expect(aeraRustEnvironment('x86_64-unknown-linux-gnu', const {}, (_) => false), isEmpty);
    });
  });

  group('prebuiltAeraRustLibs', () {
    late MemoryFileSystem fs;
    setUp(() => fs = MemoryFileSystem.test());

    test('per-target dir wins over flat files', () {
      fs.file('/libs/$arm/libdemo_native.so').createSync(recursive: true);
      fs.file('/libs/libother.so').createSync();
      expect(prebuiltAeraRustLibs(fs.directory('/libs'), arm).map((f) => f.basename), [
        'libdemo_native.so',
      ]);
    });

    test('flat dir, .so files only, sorted', () {
      fs.file('/libs/libb.so').createSync(recursive: true);
      fs.file('/libs/liba.so').createSync();
      fs.file('/libs/liba.d').createSync();
      expect(prebuiltAeraRustLibs(fs.directory('/libs'), arm).map((f) => f.basename), [
        'liba.so',
        'libb.so',
      ]);
    });

    test('a dir without libraries is an error', () {
      fs.directory('/empty').createSync();
      expect(() => prebuiltAeraRustLibs(fs.directory('/empty'), arm), throwsA(isA<ToolExit>()));
      expect(() => prebuiltAeraRustLibs(fs.directory('/nope'), arm), throwsA(isA<ToolExit>()));
    });
  });
}
