import 'dart:async';

import 'package:flutter/material.dart';
import 'package:squadron/squadron.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

import '../places/places.dart';
import 'place_header.dart';

/// The hello service, in the place the user picked.
class HelloPanel extends StatefulWidget {
  const HelloPanel({
    super.key,
    required this.kind,
    required this.facts,
    required this.connect,
  });

  /// The hello service's worker, bound to the picked place.
  static Widget inPlace(Places places, String kind) {
    final place = places.forKind(kind);
    return HelloPanel(
      kind: place.kind,
      facts: place.facts,
      connect: () => place.bind<HelloServiceWorker>(
        HelloServiceWorker(),
        service: 'hello',
      ),
    );
  }

  final String kind;
  final Future<Facts> Function() facts;
  final HelloService Function() connect;

  @override
  State<HelloPanel> createState() => _HelloPanelState();
}

class _HelloPanelState extends State<HelloPanel> {
  // Records logged inside a worker stay in that worker (or the CLI's stderr);
  // log at the call site so the page shows what ran where.
  static final _log = Logger('ui.hello');

  late final HelloService _service = widget.connect();
  late final Future<Facts> _facts = widget.facts();
  final _who = TextEditingController(text: 'world');
  String? _greeting;
{{#rust}}  String? _digest;
{{/rust}}  final _counted = <int>[];
  StreamSubscription<int>? _count;

  Future<void> _sayHello() async {
    try {
      final greeting = await _service.hello(_who.text);
      _log.info('hello ran in ${widget.kind}');
      if (mounted) setState(() => _greeting = greeting);
    } catch (e) {
      _log.warning('hello failed in ${widget.kind}', e);
      if (mounted) setState(() => _greeting = '$e');
    }
  }

{{#rust}}  Future<void> _hash() async {
    try {
      final r = await _service.sha256(_who.text);
      _log.info('digest ran ${r['strategy']} in ${widget.kind}');
      final line = '${r['sha256']} (${r['strategy']})';
      if (mounted) setState(() => _digest = line);
    } catch (e) {
      _log.warning('digest failed in ${widget.kind}', e);
      if (mounted) setState(() => _digest = '$e');
    }
  }

{{/rust}}  void _countToFive() {
    _count?.cancel();
    setState(_counted.clear);
    _count = _service.count(5).listen((i) => setState(() => _counted.add(i)));
  }

  @override
  void dispose() {
    _count?.cancel();
    _who.dispose();
    final Object service = _service;
    if (service is Worker) service.terminate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hello', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            PlaceHeader(kind: widget.kind, facts: _facts),
            const SizedBox(height: 16),
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
{{#rust}}                OutlinedButton(
                  onPressed: _hash,
                  child: const Text('SHA-256'),
                ),
{{/rust}}              ],
            ),
            if (_greeting != null) Text(_greeting!),
            if (_counted.isNotEmpty) Text('Counted: ${_counted.join(', ')}'),
{{#rust}}            if (_digest != null) Text('SHA-256: $_digest'),
{{/rust}}          ],
        ),
      ),
    );
  }
}
