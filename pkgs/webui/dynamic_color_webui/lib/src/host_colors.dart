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

/// A CorePalette from the host's scheme colours, or null without `primary`.
///
/// Hue and chroma come from the host's own roles, so a palette the manager
/// derived differently (MIUIX, a custom accent) keeps its secondary and
/// tertiary: primary (chroma at least 48, as Material's CorePalette),
/// secondary, tertiary, and the neutrals from `surfaceVariant`'s hue with
/// Material's neutral chromas (4 and 8). Missing roles fall back to
/// `CorePalette.of(primary)`.
CorePalette? corePaletteFromHost(Map<String, int> colors) {
  final primary = colors['primary'];
  if (primary == null) return null;
  final base = CorePalette.of(primary);
  final p = Hct.fromInt(primary);
  TonalPalette from(String role, TonalPalette fallback) {
    final argb = colors[role];
    if (argb == null) return fallback;
    final hct = Hct.fromInt(argb);
    return TonalPalette.of(hct.hue, hct.chroma);
  }

  final neutralHue = colors['surfaceVariant'] == null
      ? p.hue
      : Hct.fromInt(colors['surfaceVariant']!).hue;
  final palette = CorePalette.fromList([
    ...TonalPalette.of(p.hue, math.max(48, p.chroma)).asList,
    ...from('secondary', base.secondary).asList,
    ...from('tertiary', base.tertiary).asList,
    ...TonalPalette.of(neutralHue, 4).asList,
    ...TonalPalette.of(neutralHue, 8).asList,
  ]);
  return palette;
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

  Future<Map<String, int>> _hostColors() => _colors ??= () async {
    if (!host.isWebUi) return const <String, int>{};
    try {
      final css = await fetch();
      return css == null ? const <String, int>{} : parseColorsCss(css);
    } on Object {
      return const <String, int>{};
    }
  }();

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'getCorePalette':
        final palette = corePaletteFromHost(await _hostColors());
        return palette == null ? null : Int32List.fromList(palette.asList());
      case 'getAccentColor':
        // Signed 32-bit like the palette; Color masks it back.
        return (await _hostColors())['primary']?.toSigned(32);
      default:
        throw MissingPluginException(
          '${call.method} is not implemented by dynamic_color_webui',
        );
    }
  }
}
