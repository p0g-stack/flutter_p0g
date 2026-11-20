import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{name.snakeCase()}}/theme.dart';

void main() {
  Future<ColorScheme> schemeWith(WidgetTester tester, Object? accent) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      DynamicColorPlugin.channel,
      (call) async =>
          call.method == DynamicColorPlugin.accentColorMethodName ? accent : null,
    );
    late ColorScheme scheme;
    await tester.pumpWidget(
      hostColors(
        (light, dark) => MaterialApp(
          theme: themeFor(Brightness.light, light),
          home: Builder(
            builder: (context) {
              scheme = Theme.of(context).colorScheme;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return scheme;
  }

  testWidgets('the app keeps its own colours when the host has none', (
    tester,
  ) async {
    final scheme = await schemeWith(tester, null);
    expect(scheme, ColorScheme.fromSeed(seedColor: seed));
  });

  testWidgets('the host colours win when it has some', (tester) async {
    const purple = Color(0xFF6750A4);
    final scheme = await schemeWith(tester, purple.toARGB32());
    expect(scheme.primary, ColorScheme.fromSeed(seedColor: purple).primary);
    expect(scheme, isNot(ColorScheme.fromSeed(seedColor: seed)));
  });
}
