// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

/// url_launcher on a WebUI host.
///
/// Stock web calls `window.open`. Without multiple-window support a manager
/// WebView loads that URL in place: KernelSU and Next navigate the module
/// page away, WebUI X hands non-module URLs to another app
/// (`WXClient.shouldOverrideUrlLoading`). So on a WebUI host the URL goes to
/// Android instead: `am start -a android.intent.action.VIEW -d <url>` as root
/// (root is exempt from background activity start limits), which opens the
/// default app for it, as a browser tab opening a link would.
///
/// In a browser tab everything is [stock]. [linkDelegate] stays stock
/// (`Link` widgets: see docs/plugins.md).
final class UrlLauncherWebUiImpl extends UrlLauncherPlatform {
  UrlLauncherWebUiImpl({required this.stock, required this.root});

  final UrlLauncherPlatform stock;
  final WebUiRoot root;

  /// As stock web.
  static const Set<String> disallowedSchemes = {'javascript'};

  @override
  LinkDelegate? get linkDelegate => stock.linkDelegate;

  static String? _scheme(String url) => Uri.tryParse(url)?.scheme;

  @override
  Future<bool> canLaunch(String url) async {
    if (!root.available) return stock.canLaunch(url);
    final scheme = _scheme(url);
    if (scheme == null ||
        scheme.isEmpty ||
        disallowedSchemes.contains(scheme)) {
      return false;
    }
    // `cmd package query-activities` prints one block per resolved activity
    // and "No activities found" otherwise.
    final r = await root.run([
      '/system/bin/cmd',
      'package',
      'query-activities',
      '--brief',
      '-a',
      'android.intent.action.VIEW',
      '-d',
      url,
    ]);
    return r.ok &&
        r.text.trim().isNotEmpty &&
        !r.text.contains('No activities found');
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) => launchUrl(url, LaunchOptions(webOnlyWindowName: webOnlyWindowName));

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    if (!root.available) return stock.launchUrl(url, options);
    final scheme = _scheme(url);
    if (scheme == null ||
        scheme.isEmpty ||
        disallowedSchemes.contains(scheme)) {
      return false;
    }
    final r = await root.run([
      '/system/bin/am',
      'start',
      '--user',
      'current',
      '-a',
      'android.intent.action.VIEW',
      '-d',
      url,
    ]);
    // `am start` reports an unresolvable intent on stderr ("Error: Activity
    // not started, unable to resolve Intent") and may still exit 0.
    return r.ok && !'${r.text}\n${r.errorText}'.contains('Error:');
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async {
    if (!root.available) return stock.supportsMode(mode);
    return mode == PreferredLaunchMode.platformDefault ||
        mode == PreferredLaunchMode.externalApplication;
  }

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => false;
}
