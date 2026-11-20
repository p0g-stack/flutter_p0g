// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:convert';

import 'package:flutter_local_notifications_web/flutter_local_notifications_web.dart';
import 'package:flutter_local_notifications_webui/src/flutter_local_notifications_webui_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webui_app_plane/testing.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

class Stock extends WebFlutterLocalNotificationsPlugin {
  final List<String> calls = [];

  @override
  Future<bool?> initialize({onDidReceiveNotificationResponse}) async {
    calls.add('initialize');
    return false;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
    WebNotificationDetails? notificationDetails,
  }) async => calls.add('show $id');
}

const launcher = '/data/adb/modules/demo/webui_app_plane/termux-api';
const perm = 'android.permission.POST_NOTIFICATIONS';

/// A fake app whose notification permission answers [status] until a
/// request, then [afterRequest].
FakeRootChannel app({
  String status = 'denied',
  String afterRequest = 'granted',
  bool installed = true,
}) {
  var answer = status;
  return FakeRootChannel(
    handler: (run) {
      if (run.argv[0] == '/system/bin/pm') {
        return installed
            ? const FakeProcessResult(stdout: 'package:/data/app/x/base.apk')
            : const FakeProcessResult(exitCode: 1);
      }
      if (run.argv.length > 1 && run.argv[1] == launcher) {
        if (run.argv.contains('Permission')) {
          if (run.argv.contains('request')) answer = afterRequest;
          return FakeProcessResult(stdout: '{"$perm":"$answer"}\n');
        }
        return const FakeProcessResult();
      }
      return const FakeProcessResult();
    },
  );
}

List<List<String>> appCalls(FakeRootChannel fake) => [
  for (final r in fake.runs)
    if (r.argv.length > 1 && r.argv[1] == launcher)
      r.argv.sublist(4).where((a) => a != '--wait' && a != '300').toList(),
];

void main() {
  late Stock stock;
  setUp(() => stock = Stock());

  FlutterLocalNotificationsWebUiImpl plugin(
    FakeRootChannel fake, [
    FakeBridge? bridge,
  ]) => FlutterLocalNotificationsWebUiImpl(
    stock: stock,
    plane: AppPlane(fake.root(bridge)),
  );

  test('allow: Android\'s prompt through the app, then show', () async {
    final fake = app();
    final p = plugin(fake);
    expect(await p.initialize(), isTrue);
    expect(p.permissionStatus, WebNotificationPermission.defaultPermissions);
    expect(await p.requestNotificationsPermission(), isTrue);
    expect(p.permissionStatus, WebNotificationPermission.granted);
    await p.show(id: 7, title: 'Done', body: 'Flashed\nboot_a');
    final calls = appCalls(fake);
    expect(calls.firstWhere((c) => c.contains('request')), [
      'Permission',
      '--esa',
      'permissions',
      perm,
      '--ez',
      'request',
      'true',
    ]);
    expect(calls.last, [
      'Notification',
      '--es',
      'id',
      '7',
      '--es',
      'title',
      'Done',
    ]);
    expect(fake.runs.last.stdin, utf8.encode('Flashed\nboot_a'));
    expect(stock.calls, isEmpty);
  });

  test('a settled denial is not asked again and blocks show', () async {
    final fake = app(
      status: 'permanentlyDenied',
      afterRequest: 'permanentlyDenied',
    );
    final p = plugin(fake);
    await p.initialize();
    expect(p.permissionStatus, WebNotificationPermission.denied);
    expect(await p.requestNotificationsPermission(), isFalse);
    await expectLater(p.show(id: 1, title: 't'), throwsStateError);
  });

  test('silent posts at low priority; cancel and cancelAll remove', () async {
    final fake = app(status: 'granted');
    final p = plugin(fake);
    await p.show(
      id: 1,
      title: 'a',
      notificationDetails: const WebNotificationDetails(isSilent: true),
    );
    await p.show(id: 2, title: 'b');
    expect(appCalls(fake).firstWhere((c) => c.first == 'Notification'), [
      'Notification',
      '--es',
      'id',
      '1',
      '--es',
      'title',
      'a',
      '--es',
      'priority',
      'low',
    ]);
    await p.cancelAll();
    expect(appCalls(fake).where((c) => c.first == 'NotificationRemove'), [
      ['NotificationRemove', '--es', 'id', '1'],
      ['NotificationRemove', '--es', 'id', '2'],
    ]);
  });

  test('without the app, or in a browser tab, stock answers', () async {
    final none = plugin(app(installed: false));
    expect(await none.initialize(), isFalse);
    await none.show(id: 3, title: 'x');
    final fake = app();
    final tab = plugin(fake, FakeBridge.browser());
    await tab.show(id: 4);
    expect(stock.calls, ['initialize', 'show 3', 'show 4']);
    expect(fake.runs, isEmpty);
  });
}
