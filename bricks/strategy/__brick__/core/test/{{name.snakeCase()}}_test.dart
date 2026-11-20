import 'package:test/test.dart';
import 'package:{{app}}_core/{{app}}_core.dart';

void main() {
  const place = PlaceInfo('test', Facts.none());

  test('every strategy says whether it fits', () {
    for (final s in {{name.camelCase()}}.strategies) {
      expect(s.available(const Facts.none()).strategy, s.name);
    }
  });

  test('the first available strategy, in order, is chosen', () {
    final selection = {{name.camelCase()}}.{{#write}}selectWrite{{/write}}{{^write}}selectRead{{/write}}(place);
    final firstOk = selection.considered.where((c) => c.$2.ok).firstOrNull;
    expect(selection.chosen, firstOk?.$1);
  });
{{#write}}
  test('a write needs the confirmation for its own plan', () async {
    final selection = {{name.camelCase()}}.selectWrite(place);
    if (selection.chosen == null) return;
    final a = await {{name.camelCase()}}.plan('a', place);
    final b = await {{name.camelCase()}}.plan('b', place);
    expect(
      () => {{name.camelCase()}}.apply(b, Confirmation.of(a)),
      throwsStateError,
    );
  });
{{/write}}}
