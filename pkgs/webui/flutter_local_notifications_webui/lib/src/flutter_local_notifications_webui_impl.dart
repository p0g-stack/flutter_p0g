// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:convert';

import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_local_notifications_web/flutter_local_notifications_web.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:webui_app_plane/webui_app_plane.dart';

/// flutter_local_notifications' web platform on a WebUI host.
///
/// A site asks the browser to "allow notifications" and then posts; here
/// the module's own app (`com.webui.api.<seg>`, named after the module)
/// is the one Android allows, so:
///
/// | Web | WebUI host with the app |
/// |---|---|
/// | `requestNotificationsPermission` | fork `Permission` for `POST_NOTIFICATIONS`: Android's own prompt (shown once) |
/// | `permissionStatus` | the last answer: `granted`, `defaultPermissions` (not asked yet), `denied` (Android will not ask again) |
/// | `show` | fork `Notification --es id <id> --es title <title>`, body on stdin; `isSilent` posts quietly |
/// | `cancel`, `cancelAll` | fork `NotificationRemove --es id <id>` (all ids this page posted) |
///
/// Not carried over: a tap does not reach `onDidReceiveNotificationResponse`
/// (the fork's tap actions run Termux commands), actions, icons and images,
/// and `getActiveNotifications` is empty. Scheduling is unsupported, as on
/// web. Without the app, or in a browser tab, [stock] answers.
final class FlutterLocalNotificationsWebUiImpl
    extends WebFlutterLocalNotificationsPlugin {
  FlutterLocalNotificationsWebUiImpl({
    required this.stock,
    required this.plane,
  });

  final WebFlutterLocalNotificationsPlugin stock;
  final AppPlane plane;

  /// How long a request may wait on the user at Android's prompt.
  static const Duration requestWait = Duration(minutes: 5);

  static const String _permission = 'android.permission.POST_NOTIFICATIONS';

  bool? _app;
  String? _answer;
  final Set<int> _shown = {};

  Future<bool> _useApp() async =>
      _app ??= plane.root.available && await plane.isAvailable();

  @override
  Future<bool?> initialize({
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    if (!await _useApp()) {
      return stock.initialize(
        onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      );
    }
    await _status(request: false);
    return true;
  }

  @override
  Future<bool?> requestNotificationsPermission() async {
    if (!await _useApp()) return stock.requestNotificationsPermission();
    // As the browser, a settled answer is not asked again.
    if (await _status(request: false) == 'granted') return true;
    return await _status(request: true) == 'granted';
  }

  @override
  WebNotificationPermission get permissionStatus {
    if (_app != true) return stock.permissionStatus;
    return switch (_answer) {
      'granted' => WebNotificationPermission.granted,
      'permanentlyDenied' => WebNotificationPermission.denied,
      _ => WebNotificationPermission.defaultPermissions,
    };
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
    WebNotificationDetails? notificationDetails,
  }) async {
    if (!await _useApp()) {
      return stock.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: notificationDetails,
      );
    }
    // Android drops posts it does not allow; say so, as the web plugin does.
    if (await _status(request: false) != 'granted') {
      throw StateError(
        'FlutterLocalNotifications.show(): You must request notifications '
        'permissions first',
      );
    }
    final r = await _call(
      'Notification',
      extras: [
        '--es',
        'id',
        '$id',
        '--es',
        'title',
        title ?? '',
        if (notificationDetails?.isSilent ?? false) ...[
          '--es',
          'priority',
          'low',
        ],
      ],
      input: body == null || body.isEmpty ? null : utf8.encode(body),
    );
    final out = r.text.trim();
    if (out.isNotEmpty) throw StateError('Notification: $out');
    _shown.add(id);
  }

  @override
  Future<void> cancel({required int id}) async {
    if (!await _useApp()) return stock.cancel(id: id);
    await _call('NotificationRemove', extras: ['--es', 'id', '$id']);
    _shown.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    if (!await _useApp()) return stock.cancelAll();
    for (final id in _shown.toList()) {
      await cancel(id: id);
    }
  }

  @override
  Future<void> cancelAllPendingNotifications() =>
      stock.cancelAllPendingNotifications();

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() =>
      stock.pendingNotificationRequests();

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() =>
      stock.getNotificationAppLaunchDetails();

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async {
    if (!await _useApp()) return stock.getActiveNotifications();
    // Reading the shade needs notification-listener access, which the app
    // does not ask for.
    return const [];
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
    WebNotificationDetails? notificationDetails,
  }) => stock.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: scheduledDate,
    payload: payload,
    matchDateTimeComponents: matchDateTimeComponents,
    notificationDetails: notificationDetails,
  );

  @override
  Future<void> periodicallyShow({
    required int id,
    String? title,
    String? body,
    required RepeatInterval repeatInterval,
  }) => stock.periodicallyShow(
    id: id,
    title: title,
    body: body,
    repeatInterval: repeatInterval,
  );

  @override
  Future<void> periodicallyShowWithDuration({
    required int id,
    String? title,
    String? body,
    required Duration repeatDurationInterval,
  }) => stock.periodicallyShowWithDuration(
    id: id,
    title: title,
    body: body,
    repeatDurationInterval: repeatDurationInterval,
  );

  /// The app's answer for `POST_NOTIFICATIONS`; [request] shows Android's
  /// prompt when it may still ask.
  Future<String> _status({required bool request}) async {
    final r = await _call(
      'Permission',
      extras: [
        '--esa',
        'permissions',
        _permission,
        if (request) ...['--ez', 'request', 'true'],
      ],
      wait: request ? requestWait : null,
    );
    final text = r.text.trim();
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map || decoded[_permission] is! String) {
      throw StateError('Permission: ${text.isEmpty ? 'no answer' : text}');
    }
    return _answer = decoded[_permission] as String;
  }

  Future<RootResult> _call(
    String method, {
    List<String> extras = const [],
    List<int>? input,
    Duration? wait,
  }) async {
    try {
      return await plane.call(method, extras: extras, input: input, wait: wait);
    } on AppPlaneException catch (e) {
      throw StateError('$method via ${plane.package}: ${e.message}');
    }
  }
}
