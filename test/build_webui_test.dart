import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_p0g/src/commands/build_webui.dart';
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:test/test.dart';

class _Command extends BuildWebUiCommand {
  _Command() : super(verboseHelp: false);

  ArgParser? fixtureParser;
  ArgResults? results;

  @override
  ArgParser get argParser => fixtureParser ?? super.argParser;

  @override
  ArgResults? get argResults => results;
}

void main() {
  Future<void> withCommand(void Function(_Command) body) => context.run<void>(
    overrides: <Type, Generator>{
      FileSystem: () => MemoryFileSystem.test(),
      Logger: () => BufferLogger.test(),
    },
    body: () => body(_Command()),
  );

  test('registered pwa-strategy defaults to none', () async {
    await withCommand((command) {
      expect(command.argParser.options, contains('pwa-strategy'));
      command.results = command.argParser.parse([]);
      expect(command.stringArg('pwa-strategy'), 'none');
    });
  });

  test('registered pwa-strategy keeps explicit values', () async {
    await withCommand((command) {
      for (final value in ['none', 'offline-first']) {
        command.results = command.argParser.parse(['--pwa-strategy=$value']);
        expect(command.stringArg('pwa-strategy'), value);
      }
    });
  });

  test('absent pwa-strategy returns null; CLI still rejects it', () async {
    await withCommand((command) {
      command.fixtureParser = ArgParser()..addOption('output');
      command.results = command.argParser.parse(['--output=site']);
      expect(command.stringArg('pwa-strategy'), isNull);
      expect(command.stringArg('output'), 'site');
      expect(() => command.argParser.parse(['--pwa-strategy=none']), throwsFormatException);
      expect(command.argParser.options, isNot(contains('pwa-strategy')));
    });
  });
}
