import 'package:test/test.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

void main() {
  test('a missing fact means not checked, which reads as no', () {
    const facts = Facts({Fact.root: true, Fact.net: false});
    expect(facts.has(Fact.root), isTrue);
    expect(facts.has(Fact.net), isFalse);
    expect(facts.has(Fact.usbWeb), isFalse);
    expect(facts.present, [Fact.root]);
    expect(Facts.none.present, isEmpty);
  });
}
