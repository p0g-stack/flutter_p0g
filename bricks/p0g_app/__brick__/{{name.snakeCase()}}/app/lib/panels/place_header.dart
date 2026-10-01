import 'package:flutter/material.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

/// Where a panel's service runs, and the facts that place checked.
class PlaceHeader extends StatelessWidget {
  const PlaceHeader({super.key, required this.kind, required this.facts});

  final String kind;
  final Future<Facts> facts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Runs in: $kind'),
        const SizedBox(height: 8),
        FutureBuilder(
          future: facts,
          builder: (context, snap) {
            if (snap.hasError) return Text('Facts: ${snap.error}');
            final present = snap.data?.present;
            if (present == null) return const Text('Checking facts...');
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (present.isEmpty) const Chip(label: Text('no facts hold')),
                for (final f in present) Chip(label: Text(f)),
              ],
            );
          },
        ),
      ],
    );
  }
}
