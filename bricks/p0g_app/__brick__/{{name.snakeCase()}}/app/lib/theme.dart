import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

/// The app's own colours, used when the host offers none.
const seed = Colors.teal;

/// The theme for [brightness]: the host's scheme when it has one (Material
/// You on Android, the accent colour on desktop, the manager's colours in a
/// WebUI), else one made from [seed].
ThemeData themeFor(Brightness brightness, [ColorScheme? host]) => ThemeData(
  colorScheme:
      host ?? ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
);

/// Builds [builder] with the host's light and dark schemes, both null until
/// (or unless) the host answers. To use only [seed], call
/// `builder(null, null)` instead and drop dynamic_color from pubspec.yaml.
Widget hostColors(
  Widget Function(ColorScheme? light, ColorScheme? dark) builder,
) => DynamicColorBuilder(builder: builder);
