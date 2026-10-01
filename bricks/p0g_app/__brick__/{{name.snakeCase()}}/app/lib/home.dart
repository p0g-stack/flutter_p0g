import 'package:flutter/material.dart';
import 'package:squadron_process/squadron_process.dart' show PlaceKind;

import 'panels/panels.dart';
import 'places/places.dart';

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
    required this.places,
    required this.lines,
    this.panels = defaultPanels,
  });

  final Places places;
  final LogLines lines;
  final List<PanelBuilder> panels;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _local = 'local';
  var _kind = _local;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canLaunch = widget.places.process != null;
    return Scaffold(
      appBar: AppBar(title: const Text('{{name.titleCase()}}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(value: _local, label: Text('Squadron')),
              ButtonSegment(
                value: PlaceKind.process,
                label: const Text('Process'),
                enabled: canLaunch,
                tooltip: canLaunch ? null : 'No launcher on this platform',
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.single),
          ),
          for (final build in widget.panels)
            KeyedSubtree(
              key: ValueKey('$_kind-${widget.panels.indexOf(build)}'),
              child: build(widget.places, _kind),
            ),
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
