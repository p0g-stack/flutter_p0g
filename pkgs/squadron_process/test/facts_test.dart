import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';

void main() {
  test('absent and non-true facts read as false', () {
    final f = PlaceFacts({'root': true, 'net': false, 'x': 'yes'});
    expect(f.has('root'), isTrue);
    expect(f.has('net'), isFalse);
    expect(f.has('usb.web'), isFalse);
    expect(f.has('x'), isFalse);
    expect(f['x'], 'yes');
  });

  test('merge overrides and round-trips through a map', () {
    final f = PlaceFacts({'root': false}).merge({'root': true, 'a': 1});
    expect(f, PlaceFacts.fromMap({'root': true, 'a': 1}));
    expect(PlaceFacts.fromMap(f.toMap()), f);
  });

  test('facts are immutable', () {
    final f = PlaceFacts({'root': true});
    expect(() => f.toMap()['root'] = false, throwsUnsupportedError);
  });

  test('the local place runs the app\'s check, or reports nothing', () async {
    expect(await const LocalPlace().facts(), const PlaceFacts.none());
    final place = LocalPlace(check: () async => {'gpu': true});
    expect((await place.facts()).has('gpu'), isTrue);
  });
}
