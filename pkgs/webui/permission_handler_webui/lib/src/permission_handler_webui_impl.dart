// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

/// permission_handler on a WebUI host. Runtime permissions belong to the
/// module's own app (`com.webui.api.<seg>`, named after the module), so
/// Android's own dialog asks and names the module. The fork's `Permission`
/// method passes Android's answer back unchanged; nothing is stored here.
/// What to show after a denial, and when to call [openAppSettings], is the
/// app's, as on Android.
///
/// | Permission | Android permissions of the app |
/// |---|---|
/// | camera | `CAMERA` |
/// | microphone, speech | `RECORD_AUDIO` |
/// | location, locationWhenInUse | `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` |
/// | locationAlways | `ACCESS_BACKGROUND_LOCATION` |
/// | sensors | `BODY_SENSORS` |
/// | storage | `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE` |
///
/// Other permissions are not declared by the app: they report and request
/// as `denied`. `permanentlyDenied` comes only from a request (Android does
/// not tell it apart before asking).
///
/// Without the app, or in a browser tab, [stock] (the browser's own
/// prompts) answers.
final class PermissionHandlerWebUiImpl extends PermissionHandlerPlatform {
  PermissionHandlerWebUiImpl({required this.stock, required this.plane});

  final PermissionHandlerPlatform stock;
  final AppPlane plane;

  /// How long a request may wait on the user at Android's dialog.
  static const Duration requestWait = Duration(minutes: 5);

  static final Map<Permission, List<String>> androidPermissions = {
    Permission.camera: ['android.permission.CAMERA'],
    Permission.microphone: ['android.permission.RECORD_AUDIO'],
    Permission.speech: ['android.permission.RECORD_AUDIO'],
    Permission.location: [
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
    ],
    Permission.locationWhenInUse: [
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
    ],
    Permission.locationAlways: [
      'android.permission.ACCESS_BACKGROUND_LOCATION',
    ],
    Permission.sensors: ['android.permission.BODY_SENSORS'],
    Permission.storage: [
      'android.permission.READ_EXTERNAL_STORAGE',
      'android.permission.WRITE_EXTERNAL_STORAGE',
    ],
  };

  Future<bool> _useApp() async =>
      plane.root.available && await plane.isAvailable();

  /// Calls the app's `Permission` method for [names].
  Future<Map<String, String>> _call(
    List<String> names, {
    required bool request,
  }) async {
    final RootResult r;
    try {
      r = await plane.call(
        'Permission',
        extras: [
          '--esa',
          'permissions',
          names.join(','),
          if (request) ...['--ez', 'request', 'true'],
        ],
        wait: request ? requestWait : null,
      );
    } on AppPlaneException catch (e) {
      throw PlatformException(code: 'webui-${e.code}', message: e.message);
    }
    final text = r.text.trim();
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw PlatformException(
        code: 'webui-permission-failed',
        message: text.isEmpty ? 'Permission gave no answer' : text,
      );
    }
    if (decoded is! Map) {
      throw PlatformException(code: 'webui-permission-failed', message: text);
    }
    return decoded.map((k, v) => MapEntry('$k', '$v'));
  }

  static PermissionStatus _status(String? answer) => switch (answer) {
    'granted' => PermissionStatus.granted,
    'permanentlyDenied' => PermissionStatus.permanentlyDenied,
    _ => PermissionStatus.denied,
  };

  /// One status for [p] from the answers of its Android permissions: granted
  /// when any is (coarse location is enough for location, as on Android),
  /// else the strongest denial.
  static PermissionStatus _combine(Permission p, Map<String, String> answers) {
    final statuses = [
      for (final name in androidPermissions[p]!) _status(answers[name]),
    ];
    if (statuses.contains(PermissionStatus.granted)) {
      return PermissionStatus.granted;
    }
    return statuses.contains(PermissionStatus.permanentlyDenied)
        ? PermissionStatus.permanentlyDenied
        : PermissionStatus.denied;
  }

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    if (!await _useApp()) return stock.checkPermissionStatus(permission);
    final names = androidPermissions[permission];
    if (names == null) return PermissionStatus.denied;
    return _combine(permission, await _call(names, request: false));
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    if (!await _useApp()) return stock.requestPermissions(permissions);
    final names = {for (final p in permissions) ...?androidPermissions[p]}
        .toList();
    final answers = names.isEmpty
        ? const <String, String>{}
        : await _call(names, request: true);
    return {
      for (final p in permissions)
        p: androidPermissions.containsKey(p)
            ? _combine(p, answers)
            : PermissionStatus.denied,
    };
  }

  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async {
    if (!await _useApp()) {
      return stock.shouldShowRequestPermissionRationale(permission);
    }
    // Android answers this only to an activity on screen; the app has none
    // until it asks.
    return false;
  }

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async {
    if (!plane.root.available) return stock.checkServiceStatus(permission);
    if (permission is! PermissionWithService ||
        !(permission == Permission.location ||
            permission == Permission.locationWhenInUse ||
            permission == Permission.locationAlways)) {
      return ServiceStatus.notApplicable;
    }
    final r = await plane.root.run([
      '/system/bin/settings',
      'get',
      'secure',
      'location_mode',
    ]);
    final mode = int.tryParse(r.text.trim());
    if (!r.ok || mode == null) return ServiceStatus.notApplicable;
    return mode == 0 ? ServiceStatus.disabled : ServiceStatus.enabled;
  }

  /// Opens the module's app page in Android's Settings, where its
  /// permissions are switched.
  @override
  Future<bool> openAppSettings() async {
    if (!plane.root.available) return stock.openAppSettings();
    final r = await plane.root.run([
      '/system/bin/am',
      'start',
      '--user',
      'current',
      '-a',
      'android.settings.APPLICATION_DETAILS_SETTINGS',
      '-d',
      'package:${plane.package}',
    ]);
    return r.ok && !r.text.contains('Error');
  }
}
