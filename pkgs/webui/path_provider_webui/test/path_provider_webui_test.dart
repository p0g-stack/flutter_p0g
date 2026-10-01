// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_webui/src/path_provider_webui_impl.dart';
import 'package:webui_app_plane/testing.dart';

class Stock extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() =>
      throw MissingPluginException('no web path_provider');

  @override
  Future<String?> getApplicationSupportPath() =>
      throw MissingPluginException('no web path_provider');
}

void main() {
  test('module paths, state outside the module dir, created once', () async {
    final fake = FakeRootChannel();
    final p = PathProviderWebUiImpl(stock: Stock(), root: fake.root());
    expect(await p.getTemporaryPath(), '/data/local/tmp');
    expect(await p.getApplicationSupportPath(), '/data/adb/demo');
    expect(await p.getApplicationCachePath(), '/data/adb/demo/cache');
    expect(await p.getApplicationSupportPath(), '/data/adb/demo');
    expect(
      await p.getApplicationDocumentsPath(),
      '/storage/emulated/0/Documents',
    );
    expect(await p.getDownloadsPath(), '/storage/emulated/0/Download');
    expect(fake.runs.map((r) => r.argv.last), [
      '/data/adb/demo',
      '/data/adb/demo/cache',
    ]);
    expect(fake.runs.first.argv, [
      '/system/bin/mkdir',
      '-p',
      '-m',
      '700',
      '/data/adb/demo',
    ]);
    expect(() => p.getLibraryPath(), throwsUnimplementedError);
    expect(() => p.getExternalStoragePath(), throwsUnimplementedError);
  });

  test('WebUI X module id comes from moduleInfo', () async {
    final fake = FakeRootChannel();
    final p = PathProviderWebUiImpl(
      stock: Stock(),
      root: fake.root(FakeBridge.webuix()),
    );
    expect(await p.getApplicationSupportPath(), '/data/adb/demo-mod');
  });

  test('a failed mkdir is a PlatformException and is retried', () async {
    var fail = true;
    final fake = FakeRootChannel(
      handler: (_) => fail
          ? const FakeProcessResult(
              exitCode: 1,
              stderr: 'Read-only file system',
            )
          : const FakeProcessResult(),
    );
    final p = PathProviderWebUiImpl(stock: Stock(), root: fake.root());
    await expectLater(
      p.getApplicationSupportPath(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          contains('Read-only'),
        ),
      ),
    );
    fail = false;
    expect(await p.getApplicationSupportPath(), '/data/adb/demo');
  });

  test('a browser tab behaves as stock web (no implementation)', () async {
    final fake = FakeRootChannel();
    final p = PathProviderWebUiImpl(
      stock: Stock(),
      root: fake.root(FakeBridge.browser()),
    );
    expect(p.getTemporaryPath(), throwsA(isA<MissingPluginException>()));
    expect(
      p.getApplicationSupportPath(),
      throwsA(isA<MissingPluginException>()),
    );
    expect(fake.runs, isEmpty);
  });
}
