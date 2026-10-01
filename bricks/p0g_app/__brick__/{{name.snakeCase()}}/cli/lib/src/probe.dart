import 'dart:io';

import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

/// The facts of the place the CLI runs in, each one checked, not guessed.
Future<Facts> probeFacts() async {
  final facts = <String, Object?>{};

  try {
    final id = await Process.run('id', ['-u']);
    facts[Fact.processSpawn] = true;
    facts[Fact.root] = id.exitCode == 0 && '${id.stdout}'.trim() == '0';
  } on ProcessException {
    facts[Fact.processSpawn] = false;
  }

  facts[Fact.blockDevices] = await _canRead('/dev/block');
  facts[Fact.fsPersistent] = await _canWriteTemp();
  return Facts(facts);
}

/// The CLI running a command itself.
Future<Place> cliPlace() async => Place('cli', await probeFacts());

Future<bool> _canRead(String dir) async {
  try {
    await Directory(dir).list().first;
    return true;
  } on Object {
    return false;
  }
}

Future<bool> _canWriteTemp() async {
  try {
    final d = await Directory.systemTemp.createTemp('p0g');
    await d.delete();
    return true;
  } on Object {
    return false;
  }
}
