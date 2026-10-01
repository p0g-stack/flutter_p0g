import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{name.snakeCase()}}/home.dart';
import 'package:{{name.snakeCase()}}/panels/hello_panel.dart';
import 'package:{{name.snakeCase()}}/places/places.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

void main() {
  testWidgets('the hello panel shows its place and calls the service', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          places: Places(process: () => null),
          lines: LogLines(),
          panels: [
            (places, kind) => HelloPanel(
              kind: 'isolate',
              facts: () async => Facts({Fact.root: true}),
              connect: HelloService.new,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Runs in: isolate'), findsOneWidget);
    expect(find.text(Fact.root), findsOneWidget);

    await tester.tap(find.text('Say hello'));
    await tester.pumpAndSettle();
    expect(find.text('Hello, world!'), findsOneWidget);

    await tester.tap(find.text('Count to 5'));
    await tester.pumpAndSettle();
    expect(find.text('Counted: 1, 2, 3, 4, 5'), findsOneWidget);
  });

  testWidgets('the process place is off without a launcher', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          places: Places(process: () => null),
          lines: LogLines(),
          panels: const [],
        ),
      ),
    );
    final process = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(process.segments.last.enabled, isFalse);
  });
}
