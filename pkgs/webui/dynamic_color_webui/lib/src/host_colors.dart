// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

// The manager's colours reach the page as a virtual stylesheet,
// `/internal/colors.css`, holding `:root { --<name>: #rrggbb[aa]; }` with
// Compose ColorScheme names (`primary`, `secondary`, `surfaceVariant`, ...):
// - KernelSU (08a3b08) `SuFilePathHandler` + `MonetColorsProvider`: filled only
//   in Monet colour modes or the Material UI mode, otherwise empty;
//   `#rrggbb`, or `#rrggbbaa` when not opaque.
// - WebUI X (ed569e1) `InternalPathHandler` + `WebColors`: always filled, from
//   its own colour scheme; always `#rrggbbaa`.

// The plugin answers with the same CorePalette shape the Android plugin does.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webui_client/flutter_webui_client.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Reads `/internal/colors.css`; null when it cannot be fetched.
typedef ColorsCssFetcher = Future<String?> Function();

/// The dynamic_color method channel (`DynamicColorPlugin.channel`).
const String dynamicColorChannel = 'io.material.plugins/dynamic_color';

/// Parses `--name: #rrggbb` / `#rrggbbaa` declarations into ARGB ints.
/// Other values (`rgb()`, variables, keywords) are skipped.
Map<String, int> parseColorsCss(String css) {
  final colors = <String, int>{};
  final declaration = RegExp(
    r'--([A-Za-z0-9_-]+)\s*:\s*#([0-9a-fA-F]{8}|[0-9a-fA-F]{6})\s*[;}]',
  );
  for (final m in declaration.allMatches(css)) {
    final hex = m.group(2)!;
    final rgb = int.parse(hex.substring(0, 6), radix: 16);
    final alpha = hex.length == 8
        ? int.parse(hex.substring(6), radix: 16)
        : 0xff;
    colors[m.group(1)!] = (alpha << 24) | rgb;
  }
  return colors;
}

/// Roles KernelSU's MIUIX UI mode fills with colours of other roles
/// (`MonetColorsProvider.UpdateCssMiuix`: `tertiary` is a container variant,
/// `onTertiary` the tertiary container, `inverseSurface` a disabled text
/// colour, `surfaceBright` / `surfaceDim` the surface, ...). They are dropped
/// when [isMiuixShaped].
const Set<String> miuixMislabelledRoles = {
  'tertiary',
  'onTertiary',
  'inversePrimary',
  'inverseSurface',
  'inverseOnSurface',
  'surfaceBright',
  'surfaceDim',
  'surfaceContainerLow',
  'surfaceContainerLowest',
  'onSurfaceVariant',
  'outlineVariant',
  'scrim',
};

/// Whether [colors] has MIUIX's shape: `surfaceBright`, `surfaceDim` and
/// `surface` equal, and `surfaceContainerLow` equal to
/// `surfaceContainerLowest`. A Material 3 scheme never has both.
bool isMiuixShaped(Map<String, int> colors) {
  final surface = colors['surface'];
  return surface != null &&
      colors['surfaceBright'] == surface &&
      colors['surfaceDim'] == surface &&
      colors['surfaceContainerLow'] != null &&
      colors['surfaceContainerLow'] == colors['surfaceContainerLowest'];
}

/// [colors] without the roles a MIUIX-shaped stylesheet mislabels.
Map<String, int> trustedHostRoles(Map<String, int> colors) =>
    isMiuixShaped(colors)
    ? {
        for (final e in colors.entries)
          if (!miuixMislabelledRoles.contains(e.key)) e.key: e.value,
      }
    : colors;

/// Whether the host's stylesheet is its dark scheme: the tone of
/// `background` (or `surface`) is below 50. Null without either.
Brightness? hostBrightness(Map<String, int> colors) {
  final base = colors['background'] ?? colors['surface'];
  if (base == null) return null;
  return Hct.fromInt(base).tone < 50 ? Brightness.dark : Brightness.light;
}

/// A tonal palette from the roles of one family: hue from the first role
/// present (the key role), chroma the highest among them (light and dark
/// tones lose chroma to the gamut, so one role alone underestimates it).
TonalPalette? _family(
  Map<String, int> colors,
  List<String> roles, {
  double minChroma = 0,
}) {
  final hcts = [
    for (final r in roles)
      if (colors[r] != null) Hct.fromInt(colors[r]!),
  ];
  if (hcts.isEmpty) return null;
  final chroma = hcts.map((h) => h.chroma).reduce(math.max);
  return TonalPalette.of(hcts.first.hue, math.max(minChroma, chroma));
}

/// A CorePalette from the host's scheme colours, or null without `primary`.
///
/// Both managers serve one scheme, light or dark, as Compose `ColorScheme`
/// role names; a CorePalette is brightness-free, so it is rebuilt from the
/// roles of each family (hue of the key role, highest chroma of the family):
/// - primary: `primary`, `primaryContainer`, `onPrimaryContainer`,
///   `inversePrimary`, `surfaceTint` (chroma at least 48 when only `primary`
///   is known, as Material's `CorePalette.of`);
/// - secondary, tertiary: the same roles of that family;
/// - neutral: `inverseSurface`, `onSurface`, `inverseOnSurface` (mid and
///   extreme tones), default chroma 4;
/// - neutral variant: `onSurfaceVariant`, `outline`, `outlineVariant`,
///   `surfaceVariant`, default chroma 8.
/// Missing families fall back to `CorePalette.of(primary)`. Roles a
/// MIUIX-shaped stylesheet mislabels are ignored ([trustedHostRoles]).
CorePalette? corePaletteFromHost(Map<String, int> hostColors) {
  final colors = trustedHostRoles(hostColors);
  final primary = colors['primary'];
  if (primary == null) return null;
  final base = CorePalette.of(primary);
  const primaryRoles = [
    'primary',
    'primaryContainer',
    'onPrimaryContainer',
    'inversePrimary',
  ];
  final known = primaryRoles.where(colors.containsKey).length;
  List<String> family(String name) {
    final cap = name[0].toUpperCase() + name.substring(1);
    return [name, '${name}Container', 'on${cap}Container'];
  }

  final neutralRoles = ['inverseSurface', 'onSurface', 'inverseOnSurface'];
  final neutralVariantRoles = [
    'onSurfaceVariant',
    'outline',
    'outlineVariant',
    'surfaceVariant',
  ];
  final neutralKnown = neutralRoles.any(colors.containsKey);
  final variantKnown = neutralVariantRoles.any(colors.containsKey);
  return CorePalette.fromList([
    ..._family(colors, primaryRoles, minChroma: known < 2 ? 48 : 0)!.asList,
    ...(_family(colors, family('secondary')) ?? base.secondary).asList,
    ...(_family(colors, family('tertiary')) ?? base.tertiary).asList,
    ...(neutralKnown
            ? _family(colors, neutralRoles)!
            : TonalPalette.of(Hct.fromInt(primary).hue, 4))
        .asList,
    ...(variantKnown
            ? _family(colors, neutralVariantRoles)!
            : TonalPalette.of(Hct.fromInt(primary).hue, 8))
        .asList,
  ]);
}

/// The host's scheme as a Flutter [ColorScheme] for [brightness], or null
/// without `primary`.
///
/// Every role comes from [corePaletteFromHost], the way dynamic_color builds
/// its schemes on Android (legacy `Scheme` roles, newer roles from
/// `ColorScheme.fromSeed`). When the stylesheet is the [brightness] scheme
/// ([hostBrightness]), the host's own colours then replace the derived ones
/// role by role, so the app matches the manager exactly; roles the host does
/// not serve (the fixed roles, `shadow`) stay derived. The other brightness
/// is all derived.
ColorScheme? colorSchemeFromHost(
  Map<String, int> hostColors,
  Brightness brightness,
) {
  final palette = corePaletteFromHost(hostColors);
  if (palette == null) return null;
  final s = brightness == Brightness.light
      ? Scheme.lightFromCorePalette(palette)
      : Scheme.darkFromCorePalette(palette);
  final derived =
      ColorScheme.fromSeed(
        seedColor: Color(s.primary),
        brightness: brightness,
      ).copyWith(
        primary: Color(s.primary),
        onPrimary: Color(s.onPrimary),
        primaryContainer: Color(s.primaryContainer),
        onPrimaryContainer: Color(s.onPrimaryContainer),
        secondary: Color(s.secondary),
        onSecondary: Color(s.onSecondary),
        secondaryContainer: Color(s.secondaryContainer),
        onSecondaryContainer: Color(s.onSecondaryContainer),
        tertiary: Color(s.tertiary),
        onTertiary: Color(s.onTertiary),
        tertiaryContainer: Color(s.tertiaryContainer),
        onTertiaryContainer: Color(s.onTertiaryContainer),
        error: Color(s.error),
        onError: Color(s.onError),
        errorContainer: Color(s.errorContainer),
        onErrorContainer: Color(s.onErrorContainer),
        outline: Color(s.outline),
        outlineVariant: Color(s.outlineVariant),
        surface: Color(s.surface),
        onSurface: Color(s.onSurface),
        onSurfaceVariant: Color(s.onSurfaceVariant),
        inverseSurface: Color(s.inverseSurface),
        onInverseSurface: Color(s.inverseOnSurface),
        inversePrimary: Color(s.inversePrimary),
        shadow: Color(s.shadow),
        surfaceTint: Color(s.primary),
        scrim: Color(s.scrim),
      );
  if (hostBrightness(hostColors) != brightness) return derived;
  final c = trustedHostRoles(hostColors);
  Color? h(String role) => c[role] == null ? null : Color(c[role]!);
  return derived.copyWith(
    primary: h('primary'),
    onPrimary: h('onPrimary'),
    primaryContainer: h('primaryContainer'),
    onPrimaryContainer: h('onPrimaryContainer'),
    inversePrimary: h('inversePrimary'),
    secondary: h('secondary'),
    onSecondary: h('onSecondary'),
    secondaryContainer: h('secondaryContainer'),
    onSecondaryContainer: h('onSecondaryContainer'),
    tertiary: h('tertiary'),
    onTertiary: h('onTertiary'),
    tertiaryContainer: h('tertiaryContainer'),
    onTertiaryContainer: h('onTertiaryContainer'),
    error: h('error'),
    onError: h('onError'),
    errorContainer: h('errorContainer'),
    onErrorContainer: h('onErrorContainer'),
    surface: h('surface'),
    onSurface: h('onSurface'),
    onSurfaceVariant: h('onSurfaceVariant'),
    surfaceTint: h('surfaceTint'),
    inverseSurface: h('inverseSurface'),
    onInverseSurface: h('inverseOnSurface'),
    outline: h('outline'),
    outlineVariant: h('outlineVariant'),
    scrim: h('scrim'),
    surfaceBright: h('surfaceBright'),
    surfaceDim: h('surfaceDim'),
    surfaceContainerLowest: h('surfaceContainerLowest'),
    surfaceContainerLow: h('surfaceContainerLow'),
    surfaceContainer: h('surfaceContainer'),
    surfaceContainerHigh: h('surfaceContainerHigh'),
    // Compose's surfaceVariant is Flutter's surfaceContainerHighest
    // (ColorScheme.surfaceVariant is deprecated in its favour).
    surfaceContainerHighest:
        h('surfaceContainerHighest') ?? h('surfaceVariant'),
  );
}

/// Answers dynamic_color's channel on a WebUI host.
///
/// - `getCorePalette`: the palette from [corePaletteFromHost], as the Android
///   plugin's `Int32List` of 5 x 13 tones.
/// - `getAccentColor`: the host's `primary`.
///
/// Both answer null (the plugin's "no dynamic colour") in a browser tab, when
/// the manager serves no colours (KernelSU outside Monet mode, or a
/// manager with no stylesheet), or when the stylesheet cannot be read; the app then keeps
/// its own scheme, as on a platform without dynamic colour.
final class DynamicColorWebUiHandler {
  DynamicColorWebUiHandler({required this.host, required this.fetch});

  final WebUiHost host;
  final ColorsCssFetcher fetch;

  Future<Map<String, int>>? _colors;

  /// The host's colours, read once; empty in a browser tab, without colours
  /// or on error.
  Future<Map<String, int>> hostColors() => _colors ??= () async {
    if (!host.isWebUi) return const <String, int>{};
    try {
      final css = await fetch();
      return css == null ? const <String, int>{} : parseColorsCss(css);
    } on Object {
      return const <String, int>{};
    }
  }();

  /// The host's scheme for [brightness] ([colorSchemeFromHost]), or null.
  Future<ColorScheme?> colorScheme(Brightness brightness) async =>
      colorSchemeFromHost(await hostColors(), brightness);

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'getCorePalette':
        final palette = corePaletteFromHost(await hostColors());
        return palette == null ? null : Int32List.fromList(palette.asList());
      case 'getAccentColor':
        // Signed 32-bit like the palette; Color masks it back.
        return (await hostColors())['primary']?.toSigned(32);
      default:
        throw MissingPluginException(
          '${call.method} is not implemented by dynamic_color_webui',
        );
    }
  }
}
