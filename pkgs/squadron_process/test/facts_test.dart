import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';

void main() {
  test('absent and non-true facts read as false', () {
    final f = PlaceFacts({Fact.root: true, Fact.net: false, 'x': 'yes'});
    expect(f.has(Fact.root), isTrue);
    expect(f.has(Fact.net), isFalse);
    expect(f.has(Fact.usbWeb), isFalse);
    expect(f.has('x'), isFalse);
    expect(f['x'], 'yes');
  });

  test('merge overrides and round-trips through a map', () {
    final f = PlaceFacts({Fact.root: false}).merge({Fact.root: true, 'a': 1});
    expect(f, PlaceFacts.fromMap({'root': true, 'a': 1}));
    expect(PlaceFacts.fromMap(f.toMap()), f);
  });

  test('facts are immutable', () {
    final f = PlaceFacts({Fact.root: true});
    expect(() => f.toMap()['root'] = false, throwsUnsupportedError);
  });

  test('the local place checks every initial fact', () async {
    final facts = await const LocalPlace().facts();
    for (final key in Fact.all) {
      expect(facts[key], isA<bool>(), reason: key);
    }
    // Checked here, on the VM: no WebUSB in a Dart VM process.
    expect(facts.has(Fact.usbWeb), isFalse);
    expect(const LocalPlace().kind, PlaceKind.isolate);
  }, testOn: 'vm');
}
