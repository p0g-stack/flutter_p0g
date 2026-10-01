import 'package:flutter_test/flutter_test.dart';
import 'package:{{name.snakeCase()}}_app/home.dart';
import 'package:{{name.snakeCase()}}_app/main.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

void main() {
  testWidgets('shows the place and calls the service', (tester) async {
    await tester.pumpWidget(
      App(
        place: const Place('main', Facts({Fact.root: true})),
        hello: HelloService(),
        lines: LogLines(),
      ),
    );

    expect(find.text('Services run in: main'), findsOneWidget);
    expect(find.text(Fact.root), findsOneWidget);

    await tester.tap(find.text('Say hello'));
    await tester.pumpAndSettle();
    expect(find.text('Hello, world!'), findsOneWidget);

    await tester.tap(find.text('Count to 5'));
    await tester.pumpAndSettle();
    expect(find.text('Counted: 1, 2, 3, 4, 5'), findsOneWidget);
  });
}
