@TestOn('vm')
library;

import 'dart:io';

import 'package:squadron/squadron.dart';
import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';

import 'support/echo_service.dart';

const awkward = "it's a \"tricky\" \$HOME `arg` with \\ and spaces";

void expectWrap(
  ElevatedLauncher l,
  ProcessCommand c,
  String exe,
  List<String> args,
) {
  final (e, a) = l.wrap(c);
  expect(e, exe);
  expect(a, args);
}

void main() {
  group('POSIX command line', () {
    test('survives a real sh round trip', () async {
      final dir = await Directory.systemTemp.createTemp('sp q ');
      final c = ProcessCommand(
        'printf',
        arguments: ['%s|', awkward, '', 'plain'],
        environment: {'SP_VAR': awkward},
        workingDirectory: dir.path,
      );
      final r = await Process.run('sh', ['-c', '${posixCommandLine(c)}; ']);
      expect(r.stdout, '$awkward||plain|');
      final env = await Process.run('sh', [
        '-c',
        posixCommandLine(
          ProcessCommand(
            'sh',
            arguments: ['-c', r'printf %s "$SP_VAR|$PWD"'],
            environment: {'SP_VAR': awkward},
            workingDirectory: dir.path,
          ),
        ),
      ]);
      expect(env.stdout, '$awkward|${dir.resolveSymbolicLinksSync()}');
      await dir.delete();
    });

    test('leaves simple words unquoted', () {
      expect(shellQuote('/usr/bin/app'), '/usr/bin/app');
      expect(shellQuote(''), "''");
      expect(shellQuote("a'b"), r"'a'\''b'");
    });
  });

  group('wrapping', () {
    const cmd = ProcessCommand('/opt/app/bin/app', arguments: ['serve', 'x y']);

    test('pkexec passes argv as is, env and cwd through env', () {
      expectWrap(const PkexecLauncher(), cmd, 'pkexec', [
        '/opt/app/bin/app',
        'serve',
        'x y',
      ]);
      final withEnv = ProcessCommand(
        cmd.executable,
        arguments: cmd.arguments,
        environment: {'A': '1'},
        workingDirectory: '/w',
      );
      expectWrap(const PkexecLauncher(), withEnv, 'pkexec', [
        '/usr/bin/env',
        '-C',
        '/w',
        'A=1',
        '/opt/app/bin/app',
        'serve',
        'x y',
      ]);
    });

    test('su runs one shell command line', () {
      expectWrap(const SuLauncher(), cmd, 'su', [
        '-c',
        "exec /opt/app/bin/app serve 'x y'",
      ]);
    });

    test('macOS asks for admin rights and backgrounds the host', () {
      final (exe, args) = const MacAdminLauncher(prompt: 'Demo needs "admin"')
          .wrap(cmd);
      expect(exe, '/usr/bin/osascript');
      expect(args, [
        '-e',
        r'''do shell script "exec /opt/app/bin/app serve 'x y' </dev/null >/dev/null 2>&1 &" with prompt "Demo needs \"admin\"" with administrator privileges''',
      ]);
    });

    test('Windows uses RunAs with CommandLineToArgvW quoting', () {
      final (exe, args) = const WindowsRunAsLauncher().wrap(
        const ProcessCommand(
          r'C:\Program Files\App\app.exe',
          arguments: ['serve', r"C:\it's here\", 'say "hi"'],
          workingDirectory: r'C:\w',
        ),
      );
      expect(exe, 'powershell.exe');
      expect(
        args.last,
        r'''Start-Process -FilePath 'C:\Program Files\App\app.exe' -ArgumentList 'serve "C:\it''s here\\" "say \"hi\""' -WorkingDirectory 'C:\w' -Verb RunAs -WindowStyle Hidden''',
      );
      expect(
        () => const WindowsRunAsLauncher().wrap(
          const ProcessCommand('a', environment: {'X': '1'}),
        ),
        throwsArgumentError,
      );
    });

    test('Windows argument quoting', () {
      expect(windowsArgument('plain'), 'plain');
      expect(windowsArgument(''), '""');
      expect(windowsArgument('a b'), '"a b"');
      expect(windowsArgument(r'a\b'), r'a\b');
      expect(windowsArgument(r'a b\'), r'"a b\\"');
      expect(windowsArgument(r'a\"b'), r'"a\\\"b"');
    });
  });

  group('end to end through a stand-in front-end', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('sp_elev '));
    tearDown(() => dir.delete(recursive: true));

    Future<String> script(String name, String body) async {
      final f = File('${dir.path}/$name');
      await f.writeAsString('#!/bin/sh\n$body\n');
      await Process.run('chmod', ['+x', f.path]);
      return f.path;
    }

    Future<void> runThrough(ElevatedLauncher launcher) async {
      final session = '${dir.path}/run dir/host.json';
      final place = ProcessPlace(
        launcher: launcher,
        command: ProcessCommand(
          Platform.resolvedExecutable,
          arguments: [
            'run',
            'test/support/serve_main.dart',
            'serve',
            '--session-file',
            session,
            '--grace-ms',
            '200',
          ],
          workingDirectory: Directory.current.path,
        ),
        store: FileEndpointStore(session),
        storePollInterval: const Duration(milliseconds: 100),
      );
      final w = place.bind(EchoWorker());
      expect(
        await w.echo('through ${launcher.runtimeType}'),
        'through ${launcher.runtimeType}',
      );
      expect(place.endpoint!.launchId, isNotNull);
      w.stop();
    }

    test('su', () async {
      await runThrough(
        SuLauncher(su: await script('su', r'[ "$1" = -c ] && exec sh -c "$2"')),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('pkexec', () async {
      await runThrough(
        PkexecLauncher(pkexec: await script('pkexec', r'exec "$@"')),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a front-end that hides stdout (found through the store)', () async {
      // Runs the shell command line in the background with output discarded,
      // like osascript does.
      final fake = await script(
        'osascript',
        r'cmd=$(printf %s "$2" | sed -e "s/^do shell script \"//" -e "s/\" with administrator privileges$//" -e "s/\\\\\"/\"/g")'
            '\n'
            r'sh -c "$cmd"',
      );
      await runThrough(MacAdminLauncher(osascript: fake));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  test('forHost picks the front-end for this OS', () {
    final l = ElevatedLauncher.forHost();
    if (Platform.isLinux) expect(l, isA<PkexecLauncher>());
  });

  test('Squadron types stay usable', () => expect(EchoWorker(), isA<Worker>()));
}
