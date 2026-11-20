import 'package:flutter/material.dart';
import 'package:squadron/squadron.dart';
import 'package:{{app}}_core/{{app}}_core.dart';

import '../places/places.dart';
import 'place_header.dart';

/// The {{name.snakeCase()}} service, in the place the user picked.
class {{name.pascalCase()}}Panel extends StatefulWidget {
  const {{name.pascalCase()}}Panel({
    super.key,
    required this.kind,
    required this.facts,
    required this.connect,
  });

  static Widget inPlace(Places places, String kind) {
    final place = places.forKind(kind);
    return {{name.pascalCase()}}Panel(
      kind: place.kind,
      facts: place.facts,
      connect: () => place.bind<{{name.pascalCase()}}ServiceWorker>(
        withLogs({{name.pascalCase()}}ServiceWorker()),
        service: '{{name.snakeCase()}}',
      ),
    );
  }

  final String kind;
  final Future<Facts> Function() facts;
  final {{name.pascalCase()}}Service Function() connect;

  @override
  State<{{name.pascalCase()}}Panel> createState() => _{{name.pascalCase()}}PanelState();
}

class _{{name.pascalCase()}}PanelState extends State<{{name.pascalCase()}}Panel> {
  static final _log = Logger('ui.{{name.snakeCase()}}');

  late final {{name.pascalCase()}}Service _service = widget.connect();
  late final Future<Facts> _facts = widget.facts();
  final _input = TextEditingController();
  String? _result;

  Future<void> _call() async {
    try {
      final result = await _service.echo(_input.text);
      _log.info('{{name.snakeCase()}} ran in ${widget.kind}');
      if (mounted) setState(() => _result = result);
    } catch (e) {
      _log.warning('{{name.snakeCase()}} failed in ${widget.kind}', e);
      if (mounted) setState(() => _result = '$e');
    }
  }

  @override
  void dispose() {
    _input.dispose();
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
            Text(
              '{{name.titleCase()}}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            PlaceHeader(kind: widget.kind, facts: _facts),
            const SizedBox(height: 16),
            TextField(
              controller: _input,
              decoration: const InputDecoration(labelText: 'Input'),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _call, child: const Text('Echo')),
            if (_result != null) Text(_result!),
          ],
        ),
      ),
    );
  }
}
