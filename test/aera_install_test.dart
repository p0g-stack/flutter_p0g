import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_p0g/src/aera/aerap.dart';
import 'package:flutter_p0g/src/aera/install.dart';
import 'package:flutter_p0g/src/commands/install.dart' show targetOf;
import 'package:test/test.dart';

Uint8List _aerap({String id = 'counter', List<int>? payload, int? size}) {
  final xz = payload ?? utf8.encode('not really xz');
  final manifest = encodeManifest({
    'schema': 1,
    'id': id,
    'payload': 'runtime.xz',
    'payload_sha256': sha256.convert(xz).toString(),
    'payload_size': size ?? xz.length,
  });
  return aerapZip(manifest, Uint8List.fromList(xz));
}

void main() {
  test('targetOf picks the target by extension', () {
    expect(targetOf('build/aera/counter-1.0.0.aerap'), 'aera');
    expect(targetOf('build/webui/counter-v1.0.0.zip'), 'webui');
    expect(targetOf('README.md'), isNull);
  });

  group('AerapPackage.decode', () {
    test('reads what the packer writes', () {
      final p = AerapPackage.decode(_aerap());
      expect(p.id, 'counter');
      expect(utf8.decode(p.runtimeXz), 'not really xz');
      expect(p.signature, isNull);
      expect(p.payloadSha256, sha256.convert(utf8.encode('not really xz')).toString());
    });

    test('rejects a size that does not match runtime.xz', () {
      expect(() => AerapPackage.decode(_aerap(size: 1)), throwsFormatException);
    });

    test('rejects ids AERA would not scan', () {
      expect(() => AerapPackage.decode(_aerap(id: 'Counter')), throwsFormatException);
      expect(() => AerapPackage.decode(_aerap(id: '.hidden')), throwsFormatException);
    });

    test('rejects extra members', () {
      final archive = ZipDecoder().decodeBytes(_aerap())..addFile(ArchiveFile('extra', 1, [0]));
      expect(() => AerapPackage.decode(ZipEncoder().encode(archive)!), throwsFormatException);
    });
  });

  group('aeraInstallScript', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('aera_install'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<ProcessResult> install(String sha) {
      final pushed = Directory('${tmp.path}/pushed')..createSync();
      File('${pushed.path}/plugin.json').writeAsStringSync('{}');
      File('${pushed.path}/runtime.xz').writeAsStringSync('payload');
      return Process.run('sh', [
        '-c',
        aeraInstallScript(
          pushed: pushed.path,
          root: '${tmp.path}/plugins',
          id: 'counter',
          sha256: sha,
          signed: false,
        ),
      ]);
    }

    final good = sha256.convert(utf8.encode('payload')).toString();

    test('publishes read-only files under the id and removes the upload', () async {
      final r = await install(good);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final dest = '${tmp.path}/plugins/counter';
      expect(File('$dest/runtime.xz').readAsStringSync(), 'payload');
      expect(File('$dest/plugin.json').statSync().modeString(), 'r--r--r--');
      expect(Directory('${tmp.path}/pushed').existsSync(), isFalse);
      expect(Directory('${tmp.path}/plugins').listSync().map((e) => e.path.split('/').last), [
        'counter',
      ]);
    });

    test('replaces a previous install', () async {
      expect((await install(good)).exitCode, 0);
      final r = await install(good);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(Directory('${tmp.path}/plugins/counter.previous').existsSync(), isFalse);
    });

    test('refuses a payload that does not match its hash, keeping the old one', () async {
      expect((await install(good)).exitCode, 0);
      final r = await install('0' * 64);
      expect(r.exitCode, 4);
      expect(File('${tmp.path}/plugins/counter/runtime.xz').existsSync(), isTrue);
      expect(Directory('${tmp.path}/plugins').listSync(), hasLength(1));
    });
  });

  test('aeraRpcRequest is a v1 request', () {
    expect(jsonDecode(aeraRpcRequest('plugin', {'action': 'open', 'id': 'counter'})), {
      'v': 1,
      'id': 'flutter_p0g',
      'op': 'plugin',
      'args': {'action': 'open', 'id': 'counter'},
    });
  });

  test('parseAeraRpcEvents', () {
    final e = parseAeraRpcEvents(
      '{"event":"log","id":"x","text":"Opening counter\\n"}\n'
      '{"event":"error","code":"plugin_not_installed","message":"nope"}\n'
      'garbage\n'
      '{"event":"result","code":1}\n',
    );
    expect(e.code, 1);
    expect(e.logs, ['Opening counter']);
    expect(e.errors, ['plugin_not_installed: nope']);
  });

  test('aeraRpcScript writes the request and reads the reply', () async {
    final tmp = Directory.systemTemp.createTempSync('aera_rpc');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final input = '${tmp.path}/aerain', output = '${tmp.path}/aeraout';
    await Process.run('mkfifo', [input, output]);
    // AERA's side: read the request to EOF, then answer on the output FIFO.
    final aera = Process.run('sh', [
      '-c',
      'req=\$(cat $input); printf \'{"event":"log","text":"%s"}\\n{"event":"result","code":0}\\n\' '
          '"\$(echo "\$req" | tr -d \'"\')" > $output',
    ]);
    final script = aeraRpcScript(aeraRpcRequest('plugin', {'id': 'c'}))
        .replaceAll(kAeraRpcIn, input)
        .replaceAll(kAeraRpcOut, output);
    final r = await Process.run('sh', ['-c', script]);
    await aera;
    final e = parseAeraRpcEvents(r.stdout as String);
    expect(e.code, 0);
    expect(e.logs.single, contains('op:plugin'));
  });
}
