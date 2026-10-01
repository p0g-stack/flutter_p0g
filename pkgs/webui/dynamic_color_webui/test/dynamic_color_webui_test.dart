// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

// ignore_for_file: deprecated_member_use

import 'dart:math' as math;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:dynamic_color_webui/src/host_colors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webui_client/flutter_webui_client.dart';
import 'package:flutter_webui_client/testing.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

// Shapes copied from the two generators (see host_colors.dart).
const ksuCss = '''
:root {
  --primary: #4a6800;
  --onPrimary: #ffffff;
  --secondary: #586249;
  --tertiary: #386663;
  --surfaceVariant: #e1e4d5;
  --scrim: #00000052;
}
''';

const wxCss = '''
:root {
\t/* App Base Colors */
\t--primary: #9a4058ff;
\t--secondary: #75565cff;
\t--tertiary: #7b5733ff;
\t--surfaceVariant: #f3dde0ff;
\t--surface: #fff8f8ff;
\t--tonalSurface: #fcf0f2ff;
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses both managers\' formats, alpha included', () {
    final ksu = parseColorsCss(ksuCss);
    expect(ksu['primary'], 0xff4a6800);
    expect(ksu['scrim'], 0x52000000);
    expect(parseColorsCss(wxCss)['primary'], 0xff9a4058);
    expect(parseColorsCss('--x: rgb(1,2,3); --y: var(--z);'), isEmpty);
    expect(parseColorsCss(''), isEmpty);
  });

  test('palette keeps the host hues per role', () {
    final palette = corePaletteFromHost(parseColorsCss(ksuCss))!;
    final hue = Hct.fromInt(0xff4a6800).hue;
    expect(Hct.fromInt(palette.primary.get(40)).hue, closeTo(hue, 3));
    expect(
      Hct.fromInt(palette.tertiary.get(40)).hue,
      closeTo(Hct.fromInt(0xff386663).hue, 3),
    );
    expect(palette.primary.chroma, greaterThanOrEqualTo(48));
    expect(palette.neutral.chroma, closeTo(4, 1));
  });

  test('no primary, no palette', () {
    expect(corePaletteFromHost(const {'secondary': 0xff112233}), isNull);
  });

  DynamicColorWebUiHandler handler(
    FakeBridge bridge,
    String? css, {
    void Function()? onFetch,
  }) => DynamicColorWebUiHandler(
    host: WebUiHost.detect(bridge),
    fetch: () async {
      onFetch?.call();
      return css;
    },
  );

  test('the stock plugin API gets a scheme from the host', () async {
    final h = handler(FakeBridge.webuix(), wxCss);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DynamicColorPlugin.channel, h.handle);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DynamicColorPlugin.channel, null),
    );
    final palette = await DynamicColorPlugin.getCorePalette();
    final scheme = palette!.toColorScheme();
    expect(
      Hct.fromInt(scheme.primary.toARGB32()).hue,
      closeTo(Hct.fromInt(0xff9a4058).hue, 3),
    );
    expect((await DynamicColorPlugin.getAccentColor())!.toARGB32(), 0xff9a4058);
  });

  test('KernelSU outside Monet mode serves nothing: null', () async {
    final h = handler(FakeBridge.kernelsu(), '');
    expect(await h.handle(const MethodCall('getCorePalette')), isNull);
    expect(await h.handle(const MethodCall('getAccentColor')), isNull);
  });

  test('a browser tab never fetches', () async {
    var fetched = 0;
    final h = handler(FakeBridge.browser(), ksuCss, onFetch: () => fetched++);
    expect(await h.handle(const MethodCall('getCorePalette')), isNull);
    expect(fetched, 0);
  });

  test('a failed fetch is null, and the stylesheet is read once', () async {
    var fetched = 0;
    final failing = DynamicColorWebUiHandler(
      host: WebUiHost.detect(FakeBridge.kernelsu()),
      fetch: () async {
        fetched++;
        throw StateError('offline');
      },
    );
    expect(await failing.handle(const MethodCall('getCorePalette')), isNull);
    expect(await failing.handle(const MethodCall('getAccentColor')), isNull);
    expect(fetched, 1);
  });

  test('unknown methods are MissingPluginException', () {
    final h = handler(FakeBridge.kernelsu(), ksuCss);
    expect(
      h.handle(const MethodCall('nope')),
      throwsA(isA<MissingPluginException>()),
    );
  });

  // A full Material 3 scheme as KernelSU's Material UI mode serves it
  // (`UpdateCssMaterial`): Compose role names, one brightness.
  Map<String, int> tonalSpot(int seed, {required bool dark}) {
    final scheme = SchemeTonalSpot(
      sourceColorHct: Hct.fromInt(seed),
      isDark: dark,
      contrastLevel: 0,
    );
    int a(DynamicColor d) => d.getArgb(scheme);
    return {
      'primary': a(MaterialDynamicColors.primary),
      'onPrimary': a(MaterialDynamicColors.onPrimary),
      'primaryContainer': a(MaterialDynamicColors.primaryContainer),
      'onPrimaryContainer': a(MaterialDynamicColors.onPrimaryContainer),
      'inversePrimary': a(MaterialDynamicColors.inversePrimary),
      'secondary': a(MaterialDynamicColors.secondary),
      'onSecondary': a(MaterialDynamicColors.onSecondary),
      'secondaryContainer': a(MaterialDynamicColors.secondaryContainer),
      'onSecondaryContainer': a(MaterialDynamicColors.onSecondaryContainer),
      'tertiary': a(MaterialDynamicColors.tertiary),
      'onTertiary': a(MaterialDynamicColors.onTertiary),
      'tertiaryContainer': a(MaterialDynamicColors.tertiaryContainer),
      'onTertiaryContainer': a(MaterialDynamicColors.onTertiaryContainer),
      'background': a(MaterialDynamicColors.background),
      'onBackground': a(MaterialDynamicColors.onBackground),
      'surface': a(MaterialDynamicColors.surface),
      'onSurface': a(MaterialDynamicColors.onSurface),
      'surfaceVariant': a(MaterialDynamicColors.surfaceVariant),
      'onSurfaceVariant': a(MaterialDynamicColors.onSurfaceVariant),
      'surfaceTint': a(MaterialDynamicColors.surfaceTint),
      'inverseSurface': a(MaterialDynamicColors.inverseSurface),
      'inverseOnSurface': a(MaterialDynamicColors.inverseOnSurface),
      'error': a(MaterialDynamicColors.error),
      'onError': a(MaterialDynamicColors.onError),
      'errorContainer': a(MaterialDynamicColors.errorContainer),
      'onErrorContainer': a(MaterialDynamicColors.onErrorContainer),
      'outline': a(MaterialDynamicColors.outline),
      'outlineVariant': a(MaterialDynamicColors.outlineVariant),
      'scrim': a(MaterialDynamicColors.scrim),
      'surfaceBright': a(MaterialDynamicColors.surfaceBright),
      'surfaceDim': a(MaterialDynamicColors.surfaceDim),
      'surfaceContainer': a(MaterialDynamicColors.surfaceContainer),
      'surfaceContainerHigh': a(MaterialDynamicColors.surfaceContainerHigh),
      'surfaceContainerHighest': a(
        MaterialDynamicColors.surfaceContainerHighest,
      ),
      'surfaceContainerLow': a(MaterialDynamicColors.surfaceContainerLow),
      'surfaceContainerLowest': a(MaterialDynamicColors.surfaceContainerLowest),
    };
  }

  // Distance in HCT between two colours, hue weighted by chroma.
  double distance(int a, int b) {
    final x = Hct.fromInt(a), y = Hct.fromInt(b);
    final dh = ((x.hue - y.hue + 540) % 360) - 180;
    final hueTerm = dh.abs() * math.min(x.chroma, y.chroma) / 60;
    return (x.tone - y.tone).abs() + (x.chroma - y.chroma).abs() + hueTerm;
  }

  for (final seed in [0xff6750a4, 0xff4a6800, 0xffd32f2f, 0xff0061a4]) {
    group('full scheme from ${seed.toRadixString(16)}', () {
      final light = tonalSpot(seed, dark: false);
      final dark = tonalSpot(seed, dark: true);

      test('the brightness of the served set', () {
        expect(hostBrightness(light), Brightness.light);
        expect(hostBrightness(dark), Brightness.dark);
        expect(hostBrightness(const {'primary': 1}), isNull);
      });

      test('the matching brightness gets the host roles exactly', () {
        final scheme = colorSchemeFromHost(light, Brightness.light)!;
        expect(scheme.primary.toARGB32(), light['primary']);
        expect(
          scheme.onTertiaryContainer.toARGB32(),
          light['onTertiaryContainer'],
        );
        expect(
          scheme.surfaceContainerLowest.toARGB32(),
          light['surfaceContainerLowest'],
        );
        expect(
          scheme.surfaceContainerHighest.toARGB32(),
          light['surfaceContainerHighest'],
        );
        expect(scheme.onInverseSurface.toARGB32(), light['inverseOnSurface']);
        expect(scheme.brightness, Brightness.light);
      });

      test('the other brightness is derived and close to the real one', () {
        for (final (served, other, b) in [
          (light, dark, Brightness.dark),
          (dark, light, Brightness.light),
        ]) {
          final scheme = colorSchemeFromHost(served, b)!;
          expect(scheme.brightness, b);
          for (final (role, value) in [
            ('primary', scheme.primary),
            ('primaryContainer', scheme.primaryContainer),
            ('secondary', scheme.secondary),
            ('tertiary', scheme.tertiary),
            ('surface', scheme.surface),
            ('onSurfaceVariant', scheme.onSurfaceVariant),
            ('outline', scheme.outline),
          ]) {
            expect(
              distance(value.toARGB32(), other[role]!),
              lessThan(6),
              reason: '$role for $b',
            );
          }
        }
      });

      test('a MIUIX-shaped set drops the roles it mislabels', () {
        final miuix = {
          ...light,
          'tertiary': light['tertiaryContainer']!,
          'onTertiary': light['tertiaryContainer']!,
          'surfaceBright': light['surface']!,
          'surfaceDim': light['surface']!,
          'surfaceContainerLow': light['surfaceContainer']!,
          'surfaceContainerLowest': light['surfaceContainer']!,
        };
        expect(isMiuixShaped(miuix), isTrue);
        expect(isMiuixShaped(light), isFalse);
        final scheme = colorSchemeFromHost(miuix, Brightness.light)!;
        expect(scheme.primary.toARGB32(), light['primary']);
        expect(scheme.onTertiary.toARGB32(), isNot(light['tertiaryContainer']));
        expect(scheme.surfaceDim.toARGB32(), isNot(light['surface']));
      });
    });
  }
}
