import '../facts.dart';

/// No checks are possible on an unknown platform; nothing is claimed.
Future<PlaceFacts> checkFacts() async => const PlaceFacts.none();
