import 'package:test/test.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

void main() {
  test('a missing fact means not checked, which reads as no', () {
    final facts = Facts({Fact.root: true, Fact.net: false});
    expect(facts.has(Fact.root), isTrue);
    expect(facts.has(Fact.net), isFalse);
    expect(facts.has(Fact.usbWeb), isFalse);
    expect(facts.present, [Fact.root]);
    expect(facts.missing({Fact.root, Fact.usbWeb}), {Fact.usbWeb});
    expect(const Facts.none().present, isEmpty);
  });

  test('the current place checks its own facts', () async {
    final here = await PlaceInfo.current();
    expect(here.kind, anyOf('isolate', 'web_worker'));
    expect(here.facts[Fact.root], isA<bool>());
  });
}
