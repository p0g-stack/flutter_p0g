import 'dart:async';

import 'package:flutter/material.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

/// The last log lines, for the log panel.
class LogLines extends ValueNotifier<List<String>> {
  LogLines() : super(const []);

  static const _keep = 200;

  void add(String line) {
    final next = [...value, line];
    value = next.length > _keep ? next.sublist(next.length - _keep) : next;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.place,
    required this.hello,
    required this.lines,
  });

  final Place place;
  final HelloService hello;
  final LogLines lines;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Records logged inside a worker stay in that worker; log at the call site
  // so the page shows what ran where.
  static final _log = Logger('ui.home');
  final _who = TextEditingController(text: 'world');
  String? _greeting;
  final _counted = <int>[];
  StreamSubscription<int>? _count;

  Future<void> _sayHello() async {
    final greeting = await widget.hello.hello(_who.text);
    _log.info('hello ran in ${widget.place}');
    if (mounted) setState(() => _greeting = greeting);
  }

  void _countToFive() {
    _count?.cancel();
    setState(_counted.clear);
    _count = widget.hello
        .count(5)
        .listen((i) => setState(() => _counted.add(i)));
  }

  @override
  void dispose() {
    _count?.cancel();
    _who.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = widget.place.facts.present;
    return Scaffold(
      appBar: AppBar(title: const Text('{{name.titleCase()}}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Services run in: ${widget.place.name}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (facts.isEmpty) const Chip(label: Text('no facts checked')),
              for (final f in facts) Chip(label: Text(f)),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _who,
            decoration: const InputDecoration(labelText: 'Who'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _sayHello,
                child: const Text('Say hello'),
              ),
              OutlinedButton(
                onPressed: _countToFive,
                child: const Text('Count to 5'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_greeting != null) Text(_greeting!),
          if (_counted.isNotEmpty) Text('Counted: ${_counted.join(', ')}'),
          const SizedBox(height: 24),
          Text('Log', style: theme.textTheme.titleMedium),
          ValueListenableBuilder(
            valueListenable: widget.lines,
            builder: (context, lines, _) => SelectionArea(
              child: Text(
                lines.isEmpty ? '(empty)' : lines.join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
