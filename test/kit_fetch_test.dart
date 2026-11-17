import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file/memory.dart';
import 'package:flutter_p0g/src/aera/kit.dart';
import 'package:flutter_p0g/src/artifact_cache.dart';
import 'package:flutter_p0g/src/commands/precache.dart';
import 'package:flutter_p0g/src/webui/dart_android.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/version.dart';
import 'package:test/test.dart';

class _Version implements FlutterVersion {
  @override
  String get frameworkVersion => '3.47.5';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Os implements OperatingSystemUtils {
  bool failChmod = false;

  @override
  void chmod(FileSystemEntity entity, String mode) {
    if (failChmod) throw StateError('fixture chmod failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<int> _archive(Map<String, String> members) {
  final archive = Archive();
  for (final entry in members.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes)..mode = 0x1ed);
  }
  return GZipEncoder().encode(TarEncoder().encode(archive))!;
}

void main() {
  late MemoryFileSystem fs;
  late _Os os;
  String? previousRoot;

  setUp(() {
    fs = MemoryFileSystem.test();
    os = _Os();
    previousRoot = Cache.flutterRoot;
    Cache.flutterRoot = '/flutter';
    fs.file('/flutter/bin/cache/dart-sdk/version')
      ..createSync(recursive: true)
      ..writeAsStringSync('3.13.4');
    fs.file('/flutter/bin/internal/engine.version')
      ..createSync(recursive: true)
      ..writeAsStringSync('engine');
  });
  tearDown(() => Cache.flutterRoot = previousRoot);

  Future<void> inContext(Future<void> Function() body) => context.run<void>(
    body: () => io.HttpOverrides.runZoned(
      body,
      createHttpClient: (_) => throw StateError('unexpected network access'),
    ),
    overrides: {
      FileSystem: () => fs,
      OperatingSystemUtils: () => os,
      Logger: () => BufferLogger.test(),
      FlutterVersion: () => _Version(),
    },
  );

  File android({String runtime = 'runtime', String version = '3.13.4', bool complete = true}) {
    return fs.file('/android.tar.gz')..writeAsBytesSync(
      _archive({
        'VERSION': version,
        'ABI': 'arm64-v8a',
        'gen_snapshot': 'snapshot',
        if (complete) 'dartaotruntime': runtime,
      }),
    );
  }

  File aera({String launcher = 'launcher', String engine = 'engine', bool complete = true}) {
    return fs.file('/aera.tar.gz')..writeAsBytesSync(
      _archive({
        'kit.json': jsonEncode({
          'kit': 1,
          'flutter': '3.47.5',
          'arch': 'arm64',
          'mode': 'debug',
          'engine_revision': engine,
        }),
        if (complete) 'usr/bin/aera-plugin': launcher,
      }),
    );
  }

  String digest(File file) => sha256.convert(file.readAsBytesSync()).toString();

  test('explicit kit hashes are required and validated before local or network I/O', () async {
    await inContext(() async {
      for (final source in ['/missing.tar.gz', 'https://example.invalid/kit.tar.gz']) {
        for (final hash in [null, '', 'f' * 63, 'z' * 64, 'f' * 65]) {
          await expectLater(
            precacheDartAndroid(source: source, sha256Hex: hash),
            throwsA(isA<ToolExit>()),
          );
          await expectLater(precacheAeraKit(source, sha256Hex: hash), throwsA(isA<ToolExit>()));
        }
      }
    });
  });

  test('hash without source cannot identify several default ABIs', () {
    expect(() => validateKitSelection(null, 'f' * 64, 2), throwsA(isA<ToolExit>()));
    expect(() => validateKitSelection('/kit', null, 1), throwsA(isA<ToolExit>()));
    validateKitSelection(null, 'f' * 64, 1);
    validateKitSelection(null, null, 2);
  });

  test('unknown default identities fail without network access', () async {
    await inContext(() async {
      await expectLater(precacheDartAndroid(abi: 'mips'), throwsA(isA<ToolExit>()));
      await expectLater(precacheAeraKit(null, mode: 'release'), throwsA(isA<ToolExit>()));
      await expectLater(precacheAeraKit(null, target: 'linux-mips'), throwsA(isA<ToolExit>()));
      fs.file('/flutter/bin/cache/dart-sdk/version').writeAsStringSync('future');
      await expectLater(precacheDartAndroid(), throwsA(isA<ToolExit>()));
    });
  });

  test('Android correct digest installs identity; missing identity is not reusable', () async {
    await inContext(() async {
      final source = android();
      final hash = digest(source);
      await precacheDartAndroid(source: source.path, sha256Hex: hash.toUpperCase());
      final kit = DartAndroidKit.forAbi('3.13.4', 'arm64-v8a');
      expect(kit.isComplete, isTrue);
      expect(readKitIdentity(kit.dir), {
        'schema': 1,
        'sha256': hash,
        'version': '3.13.4',
        'abi': 'arm64-v8a',
      });
      kit.dir.childFile(kitIdentityFile).deleteSync();
      expect(kit.isComplete, isFalse);
      expect(DartAndroidKit.installed('3.13.4'), isEmpty);
      // A legacy cache cannot bypass the fetch for the committed pin.
      await expectLater(precacheDartAndroid(), throwsStateError);
    });
  });

  test('Android failed hash, metadata, archive or extraction preserves verified bytes', () async {
    await inContext(() async {
      final original = android();
      await precacheDartAndroid(source: original.path, sha256Hex: digest(original));
      final kit = DartAndroidKit.forAbi('3.13.4', 'arm64-v8a');
      final identity = kit.dir.childFile(kitIdentityFile).readAsStringSync();
      final changed = android(runtime: 'changed');
      await expectLater(
        precacheDartAndroid(source: changed.path, sha256Hex: '0' * 64),
        throwsA(isA<ToolExit>()),
      );
      for (final make in [() => android(complete: false), () => android(version: 'other')]) {
        final file = make();
        await expectLater(
          precacheDartAndroid(source: file.path, sha256Hex: digest(file)),
          throwsA(isA<ToolExit>()),
        );
      }
      final malformed = fs.file('/broken.tar.gz')..writeAsStringSync('not an archive');
      await expectLater(
        precacheDartAndroid(source: malformed.path, sha256Hex: digest(malformed)),
        throwsA(anything),
      );
      final valid = android(runtime: 'new');
      os.failChmod = true;
      await expectLater(
        precacheDartAndroid(source: valid.path, sha256Hex: digest(valid)),
        throwsStateError,
      );
      expect(kit.runtime.readAsStringSync(), 'runtime');
      expect(kit.dir.childFile(kitIdentityFile).readAsStringSync(), identity);
      expect(kit.isComplete, isTrue);
      expect(kit.dir.parent.listSync().map((entry) => entry.basename), ['arm64-v8a']);
    });
  });

  test('AERA correct digest installs identity; missing identity is not reusable', () async {
    await inContext(() async {
      final source = aera();
      final hash = digest(source);
      await precacheAeraKit(source.path, sha256Hex: hash);
      final kit = AeraKit.forTarget('linux-arm64', 'debug');
      expect(kit.isInstalled, isTrue);
      expect(readKitIdentity(kit.dir)?['sha256'], hash);
      expect(readKitIdentity(kit.dir)?['version'], '3.47.5');
      expect(readKitIdentity(kit.dir)?['target'], 'linux-arm64');
      expect(readKitIdentity(kit.dir)?['mode'], 'debug');
      kit.dir.childFile(kitIdentityFile).deleteSync();
      expect(kit.isInstalled, isFalse);
      await expectLater(precacheAeraKit(null), throwsStateError);
    });
  });

  test('AERA failed hash, metadata, archive or extraction preserves verified bytes', () async {
    await inContext(() async {
      final original = aera();
      await precacheAeraKit(original.path, sha256Hex: digest(original));
      final kit = AeraKit.forTarget('linux-arm64', 'debug');
      final identity = kit.dir.childFile(kitIdentityFile).readAsStringSync();
      final changed = aera(launcher: 'changed');
      await expectLater(
        precacheAeraKit(changed.path, sha256Hex: '0' * 64),
        throwsA(isA<ToolExit>()),
      );
      for (final make in [() => aera(complete: false), () => aera(engine: 'other')]) {
        final file = make();
        await expectLater(
          precacheAeraKit(file.path, sha256Hex: digest(file)),
          throwsA(isA<ToolExit>()),
        );
      }
      final escaping = fs.file('/escape.tar.gz')
        ..writeAsBytesSync(
          _archive({
            'kit.json': jsonEncode({
              'kit': 1,
              'flutter': '3.47.5',
              'arch': 'arm64',
              'mode': 'debug',
              'engine_revision': 'engine',
            }),
            'usr/bin/aera-plugin': 'new',
            '../escape': 'not allowed',
          }),
        );
      await expectLater(
        precacheAeraKit(escaping.path, sha256Hex: digest(escaping)),
        throwsA(isA<ToolExit>()),
      );
      final valid = aera(launcher: 'new');
      os.failChmod = true;
      await expectLater(precacheAeraKit(valid.path, sha256Hex: digest(valid)), throwsStateError);
      expect(kit.payload.childFile('usr/bin/aera-plugin').readAsStringSync(), 'launcher');
      expect(kit.dir.childFile(kitIdentityFile).readAsStringSync(), identity);
      expect(kit.isInstalled, isTrue);
      expect(kit.dir.parent.listSync().map((entry) => entry.basename), ['linux-arm64-debug']);
    });
  });
}
