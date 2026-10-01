import 'package:flutter/material.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

import 'home.dart';
import 'places.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final lines = LogLines();
  logTo((line) {
    debugPrint(line);
    lines.add(line);
  }, level: Level.ALL);

  final link = await openPlace();
  final hello = await link.start('hello', HelloServiceWorker.new);
  runApp(App(place: link.place, hello: hello, lines: lines));
}

class App extends StatelessWidget {
  const App({
    super.key,
    required this.place,
    required this.hello,
    required this.lines,
  });

  final Place place;
  final HelloService hello;
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
      home: HomePage(place: place, hello: hello, lines: lines),
    );
  }
}
