import 'facts.dart';

/// Where code runs, and what it checked it can do there.
///
/// Names in use: `isolate` and `web_worker` (Squadron), `process` (the app's
/// CLI in serve mode, through squadron_process), `cli` (the CLI running a
/// command itself), `main` (the UI isolate or page).
final class Place {
  const Place(this.name, [this.facts = Facts.none]);

  final String name;
  final Facts facts;

  @override
  String toString() => name;
}
