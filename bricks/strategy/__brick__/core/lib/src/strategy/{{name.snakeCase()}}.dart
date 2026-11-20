import '../facts/facts.dart';
import 'objective.dart';
import 'strategy.dart';

/// {{name.sentenceCase()}}: its strategies, in preference order. The first
/// whose `available(facts)` holds in the place runs.
final {{name.camelCase()}} = Objective<String, String>('{{name.snakeCase()}}', const [
{{#items}}  {{type}}(),
{{/items}}]);
{{#items}}
/// {{name.sentenceCase()}} via {{label}}.
final class {{type}}
    extends {{#write}}WriteStrategy{{/write}}{{^write}}ReadStrategy{{/write}}<String, String> {
  const {{type}}();

  @override
  String get name => '{{id}}';

  /// The facts this strategy cannot run without, e.g. `{Fact.root}`.
  @override
  Set<String> get requires => const {};
{{#write}}
  /// The steps [write] would take. Must change nothing.
  @override
  Future<List<String>> plan(String input, PlaceInfo place) async => [
    '{{name.snakeCase()}} $input via {{id}} in $place',
  ];

  /// Writing to a device outside this place (a phone on a cable)? Name it
  /// in the input and refuse here if another one is connected now; see
  /// `WriteStrategy` and docs/patterns/devices.md in bricks.
  @override
  Future<String> write(String input, PlaceInfo place) =>
      throw UnimplementedError('{{name.snakeCase()}} via {{id}}');
{{/write}}{{^write}}
  @override
  Future<String> run(String input, PlaceInfo place) =>
      throw UnimplementedError('{{name.snakeCase()}} via {{id}}');
{{/write}}}
{{/items}}
