// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_webui/src/url_launcher_webui_impl.dart';
import 'package:webui_app_plane/testing.dart';

class Stock extends UrlLauncherPlatform {
  final List<String> calls = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    calls.add('canLaunch $url');
    return true;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add('launchUrl $url');
    return true;
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async =>
      mode == PreferredLaunchMode.platformDefault;
}

void main() {
  late Stock stock;
  setUp(() => stock = Stock());

  test('launchUrl starts a VIEW activity as root', () async {
    final fake = FakeRootChannel(
      handler: (_) => const FakeProcessResult(
        stdout: 'Starting: Intent { act=android.intent.action.VIEW dat=https://example.com/... }',
      ),
    );
    final l = UrlLauncherWebUiImpl(stock: stock, root: fake.root());
    expect(
      await l.launchUrl('https://example.com/a?b=c d', const LaunchOptions()),
      isTrue,
    );
    expect(fake.runs.single.argv, [
      '/system/bin/am',
      'start',
      '--user',
      'current',
      '-a',
      'android.intent.action.VIEW',
      '-d',
      'https://example.com/a?b=c d',
    ]);
    expect(stock.calls, isEmpty);
  });

  test('an unresolvable intent is false even when am exits 0', () async {
    final fake = FakeRootChannel(
      handler: (_) => const FakeProcessResult(
        stderr: 'Error: Activity not started, unable to resolve Intent',
      ),
    );
    final l = UrlLauncherWebUiImpl(stock: stock, root: fake.root());
    expect(await l.launchUrl('foo:bar', const LaunchOptions()), isFalse);
  });

  test('javascript: is refused without running anything', () async {
    final fake = FakeRootChannel();
    final l = UrlLauncherWebUiImpl(stock: stock, root: fake.root());
    expect(
      await l.launchUrl('javascript:alert(1)', const LaunchOptions()),
      isFalse,
    );
    expect(await l.canLaunch('javascript:alert(1)'), isFalse);
    expect(fake.runs, isEmpty);
  });

  test('canLaunch asks the package manager', () async {
    final fake = FakeRootChannel(
      handler: (run) => run.argv.last == 'https://x.org'
          ? const FakeProcessResult(stdout: 'com.android.chrome/.Main\n')
          : const FakeProcessResult(stdout: 'No activities found\n'),
    );
    final l = UrlLauncherWebUiImpl(stock: stock, root: fake.root());
    expect(await l.canLaunch('https://x.org'), isTrue);
    expect(await l.canLaunch('nope:x'), isFalse);
    expect(fake.runs.first.argv.take(4), [
      '/system/bin/cmd',
      'package',
      'query-activities',
      '--brief',
    ]);
  });

  test('modes: default and external app on WebUI', () async {
    final l = UrlLauncherWebUiImpl(
      stock: stock,
      root: FakeRootChannel().root(),
    );
    expect(
      await l.supportsMode(PreferredLaunchMode.externalApplication),
      isTrue,
    );
    expect(await l.supportsMode(PreferredLaunchMode.inAppWebView), isFalse);
    expect(
      await l.supportsCloseForMode(PreferredLaunchMode.platformDefault),
      isFalse,
    );
  });

  test('a browser tab is stock web', () async {
    final fake = FakeRootChannel();
    final l = UrlLauncherWebUiImpl(
      stock: stock,
      root: fake.root(FakeBridge.browser()),
    );
    expect(await l.launchUrl('https://x.org', const LaunchOptions()), isTrue);
    expect(await l.canLaunch('https://x.org'), isTrue);
    expect(
      await l.supportsMode(PreferredLaunchMode.externalApplication),
      isFalse,
    );
    expect(stock.calls, ['launchUrl https://x.org', 'canLaunch https://x.org']);
    expect(fake.runs, isEmpty);
  });
}
