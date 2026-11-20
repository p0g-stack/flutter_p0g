import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' as mui;

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
) => DynamicColorBuilder(
  builder: (light, dark) => builder(light?.material, dark?.material),
);

/// dynamic_color 2.1.0 builds package:material_ui's ColorScheme, a twin of
/// Flutter's with the same fields.
extension on mui.ColorScheme {
  ColorScheme get material => ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    primaryFixed: primaryFixed,
    primaryFixedDim: primaryFixedDim,
    onPrimaryFixed: onPrimaryFixed,
    onPrimaryFixedVariant: onPrimaryFixedVariant,
    secondary: secondary,
    onSecondary: onSecondary,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: onSecondaryContainer,
    secondaryFixed: secondaryFixed,
    secondaryFixedDim: secondaryFixedDim,
    onSecondaryFixed: onSecondaryFixed,
    onSecondaryFixedVariant: onSecondaryFixedVariant,
    tertiary: tertiary,
    onTertiary: onTertiary,
    tertiaryContainer: tertiaryContainer,
    onTertiaryContainer: onTertiaryContainer,
    tertiaryFixed: tertiaryFixed,
    tertiaryFixedDim: tertiaryFixedDim,
    onTertiaryFixed: onTertiaryFixed,
    onTertiaryFixedVariant: onTertiaryFixedVariant,
    error: error,
    onError: onError,
    errorContainer: errorContainer,
    onErrorContainer: onErrorContainer,
    surface: surface,
    onSurface: onSurface,
    surfaceDim: surfaceDim,
    surfaceBright: surfaceBright,
    surfaceContainerLowest: surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outlineVariant,
    shadow: shadow,
    scrim: scrim,
    inverseSurface: inverseSurface,
    onInverseSurface: onInverseSurface,
    inversePrimary: inversePrimary,
    surfaceTint: surfaceTint,
  );
}
