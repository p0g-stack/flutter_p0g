import 'dart:convert';

import 'package:args/command_runner.dart';

import '../probe.dart';

/// Prints the facts of the place the CLI runs in.
class FactsCommand extends Command<int> {
  @override
  String get name => 'facts';

  @override
  String get description => 'Print what this place has checked it can do.';

  @override
  Future<int> run() async {
    final place = await cliPlace();
    print(const JsonEncoder.withIndent('  ').convert(place.facts.toJson()));
    return 0;
  }
}
