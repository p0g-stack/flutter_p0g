// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:permission_handler_webui/src/permission_handler_webui_impl.dart';
import 'package:webui_app_plane/testing.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

class Stock extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      PermissionStatus.restricted;
}

/// A fake app: `pm path` finds it, `Permission` answers from [answer].
FakeRootChannel app(String Function(FakeRun run) answer) => FakeRootChannel(
  handler: (run) {
    if (run.argv.contains('path')) {
      return const FakeProcessResult(stdout: 'package:/x.apk');
    }
    if (run.argv.contains('Permission')) {
      return FakeProcessResult(stdout: '${answer(run)}\n');
    }
    return const FakeProcessResult();
  },
);

PermissionHandlerWebUiImpl handler(FakeRootChannel fake, [FakeBridge? b]) =>
    PermissionHandlerWebUiImpl(stock: Stock(), plane: AppPlane(fake.root(b)));

FakeRun permissionRun(FakeRootChannel fake) =>
    fake.runs.lastWhere((r) => r.argv.contains('Permission'));

void main() {
  test('status asks the app without a dialog', () async {
    final fake = app((_) => '{"android.permission.CAMERA":"denied"}');
    expect(
      await handler(fake).checkPermissionStatus(Permission.camera),
      PermissionStatus.denied,
    );
    final run = permissionRun(fake);
    expect(run.argv.sublist(2), [
      '--package',
      'com.webui.api.demo',
      'Permission',
      '--esa',
      'permissions',
      'android.permission.CAMERA',
    ]);
  });

  test('a request shows the dialog and passes Android\'s answer', () async {
    final fake = app(
      (_) =>
          '{"android.permission.CAMERA":"permanentlyDenied",'
          '"android.permission.RECORD_AUDIO":"granted"}',
    );
    final result = await handler(fake).requestPermissions([
      Permission.camera,
      Permission.microphone,
      Permission.sms,
    ]);
    expect(result, {
      Permission.camera: PermissionStatus.permanentlyDenied,
      Permission.microphone: PermissionStatus.granted,
      Permission.sms: PermissionStatus.denied,
    });
    final run = permissionRun(fake);
    expect(run.argv.sublist(4, 6), ['--wait', '300']);
    expect(run.argv.sublist(6), [
      'Permission',
      '--esa',
      'permissions',
      'android.permission.CAMERA,android.permission.RECORD_AUDIO',
      '--ez',
      'request',
      'true',
    ]);
  });

  test('coarse location is enough for location', () async {
    final fake = app(
      (_) =>
          '{"android.permission.ACCESS_FINE_LOCATION":"denied",'
          '"android.permission.ACCESS_COARSE_LOCATION":"granted"}',
    );
    expect(
      await handler(fake).checkPermissionStatus(Permission.location),
      PermissionStatus.granted,
    );
  });

  test('an undeclared permission is denied without asking', () async {
    final fake = app((_) => '{}');
    expect(
      await handler(fake).checkPermissionStatus(Permission.contacts),
      PermissionStatus.denied,
    );
    expect(fake.runs.where((r) => r.argv.contains('Permission')), isEmpty);
  });

  test('an error answer is a PlatformException', () async {
    final fake = app((_) => 'Unknown api_method: Permission');
    await expectLater(
      handler(fake).checkPermissionStatus(Permission.camera),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          contains('Unknown api_method'),
        ),
      ),
    );
  });

  test('openAppSettings opens the module app\'s Settings page', () async {
    final fake = app((_) => '{}');
    expect(await handler(fake).openAppSettings(), isTrue);
    expect(fake.runs.last.argv, [
      '/system/bin/am',
      'start',
      '--user',
      'current',
      '-a',
      'android.settings.APPLICATION_DETAILS_SETTINGS',
      '-d',
      'package:com.webui.api.demo',
    ]);
  });

  test('location service from location_mode', () async {
    final fake = FakeRootChannel(
      handler: (run) => const FakeProcessResult(stdout: '3\n'),
    );
    expect(
      await handler(fake).checkServiceStatus(Permission.location),
      ServiceStatus.enabled,
    );
    expect(
      await handler(fake).checkServiceStatus(Permission.camera),
      ServiceStatus.notApplicable,
    );
  });

  test('without the app, or in a browser tab, stock answers', () async {
    final noApp = FakeRootChannel(
      handler: (run) => const FakeProcessResult(exitCode: 1),
    );
    expect(
      await handler(noApp).checkPermissionStatus(Permission.camera),
      PermissionStatus.restricted,
    );
    final tab = FakeRootChannel();
    expect(
      await handler(
        tab,
        FakeBridge.browser(),
      ).checkPermissionStatus(Permission.camera),
      PermissionStatus.restricted,
    );
    expect(tab.runs, isEmpty);
  });
}
