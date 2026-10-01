import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_p0g/src/webui/dart_android.dart';
import 'package:test/test.dart';

Archive kit(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return a;
}

void main() {
  group('validateKitArchive', () {
    test('accepts a kit for this Dart', () {
      expect(
        validateKitArchive(
          kit({'VERSION': '3.13.4\n', 'gen_snapshot': 'x', 'dartaotruntime': 'y'}),
          '3.13.4',
        ),
        isNull,
      );
    });

    test('rejects another Dart version: snapshots only load in their own runtime', () {
      expect(
        validateKitArchive(
          kit({'VERSION': '3.13.5', 'gen_snapshot': 'x', 'dartaotruntime': 'y'}),
          '3.13.4',
        ),
        contains('3.13.5'),
      );
    });

    test('rejects a kit missing a half', () {
      expect(
        validateKitArchive(kit({'VERSION': '3.13.4', 'gen_snapshot': 'x'}), '3.13.4'),
        contains('dartaotruntime'),
      );
    });
  });

  test('launcher picks the ABI directory and passes arguments through', () {
    final s = launcherScript('counterd');
    expect(s, startsWith('#!/system/bin/sh\n'));
    expect(s, contains(r'd=$b/$(getprop ro.product.cpu.abi)'));
    expect(s, contains(r'export TMPDIR="$b/../tmp"'));
    expect(s, contains(r'exec "$d/dartaotruntime" "$d/counterd.aot" "$@"'));
  });

  test('kit ABI defaults to arm64-v8a; unknown ABIs are rejected', () {
    expect(kitAbi(kit({})), 'arm64-v8a');
    expect(kitAbi(kit({'ABI': 'x86_64\n'})), 'x86_64');
    expect(
      validateKitArchive(
        kit({'VERSION': '3.13.4', 'ABI': 'mips', 'gen_snapshot': 'x', 'dartaotruntime': 'y'}),
        '3.13.4',
      ),
      contains('mips'),
    );
  });

  test('default kit URL names the ABI and Dart version', () {
    expect(defaultKitUrl('3.13.4', 'x86_64'), endsWith('/dart-android-x86_64-3.13.4.tar.gz'));
    expect(
      defaultKitUrl('3.13.4', 'arm64-v8a'),
      endsWith('/dart-android-3.13.4/dart-android-arm64-v8a-3.13.4.tar.gz'),
    );
  });
}
