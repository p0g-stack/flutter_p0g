import 'package:flutter/material.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

import 'home.dart';
import 'places/places.dart';

void main() {
  final lines = LogLines();
  logTo((line) {
    debugPrint(line);
    lines.add(line);
  }, level: Level.ALL);
  runApp(App(places: Places(), lines: lines));
}

class App extends StatelessWidget {
  const App({super.key, required this.places, required this.lines});

  final Places places;
  final LogLines lines;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '{{name.titleCase()}}',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: HomePage(places: places, lines: lines),
    );
  }
}
