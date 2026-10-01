// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

/// A module's preferences: one JSON object stored as one value in KernelSU's
/// module config (`ksud module config`, persist.config). ksud keeps it until
/// the module is uninstalled, across updates and while the module is
/// disabled. Values are what the stock web plugin stores: bool, int, double,
/// String and `List<String>`.
///
/// Every operation reads the stored object fresh and a change writes it
/// whole, one operation at a time on this page.
final class ModuleConfigPrefs {
  ModuleConfigPrefs(this.root);

  final WebUiRoot root;

  /// The module config key holding the object.
  static const String configKey = 'webui.shared_preferences';

  /// ksud's link in KernelSU's bin dir (KernelSU and KernelSU Next).
  static const String ksud = '/data/adb/ksu/bin/ksud';

  /// ksud's limit for one value.
  static const int maxBytes = 1024 * 1024;

  /// Whether the module's preferences are used: a WebUI host with the root
  /// channel and a module id. Otherwise the stock web plugin answers.
  bool get available => root.available && root.moduleId != null;

  Future<void> _last = Future.value();

  /// Runs [op] after every earlier operation of this page has finished.
  Future<T> _serial<T>(Future<T> Function() op) {
    final next = _last.then((_) => op());
    _last = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<RootResult> _ksud(List<String> args, {List<int>? stdin}) => root.sh(
    r'KSU_MODULE=$1; export KSU_MODULE; shift; exec "$@"',
    args: [root.moduleId!, ksud, 'module', 'config', ...args],
    stdin: stdin,
  );

  Future<Map<String, Object>> _read() async {
    final r = await _ksud(['get', configKey]);
    if (!r.ok) {
      if (r.errorText.contains('not found')) return {};
      throw PlatformException(
        code: 'webui-prefs-read-failed',
        message: 'ksud module config get: ${r.errorText.trim()}',
      );
    }
    var text = r.text;
    if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
    if (text.isEmpty) return {};
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw PlatformException(
        code: 'webui-prefs-corrupt',
        message: '$configKey is not JSON: ${e.message}',
      );
    }
    if (decoded is! Map<String, Object?>) return {};
    final out = <String, Object>{};
    decoded.forEach((key, value) {
      final v = _fromJson(value);
      if (v != null) out[key] = v;
    });
    return out;
  }

  static Object? _fromJson(Object? value) => switch (value) {
    bool() || int() || double() || String() => value,
    List() when value.every((e) => e is String) => value.cast<String>(),
    _ => null,
  };

  Future<void> _write(Map<String, Object> prefs) async {
    final bytes = utf8.encode(jsonEncode(prefs));
    if (bytes.length > maxBytes) {
      throw PlatformException(
        code: 'webui-prefs-too-large',
        message:
            'preferences are ${bytes.length} bytes; ksud keeps at most '
            '$maxBytes per value',
      );
    }
    final r = await _ksud(['set', configKey, '--stdin'], stdin: bytes);
    if (!r.ok) {
      throw PlatformException(
        code: 'webui-prefs-write-failed',
        message: 'ksud module config set: ${r.errorText.trim()}',
      );
    }
  }

  /// All stored preferences.
  Future<Map<String, Object>> read() => _serial(_read);

  /// Reads, applies [change] and writes the result back if it changed.
  Future<void> update(void Function(Map<String, Object> prefs) change) =>
      _serial(() async {
        final prefs = await _read();
        final before = jsonEncode(prefs);
        change(prefs);
        if (jsonEncode(prefs) != before) await _write(prefs);
      });
}

bool _matches(String key, String prefix, Set<String>? allowList) =>
    key.startsWith(prefix) && (allowList == null || allowList.contains(key));

/// `SharedPreferences` (the legacy API) on a WebUI host.
final class SharedPreferencesWebUiStore extends SharedPreferencesStorePlatform {
  SharedPreferencesWebUiStore({required this.stock, required this.prefs});

  final SharedPreferencesStorePlatform stock;
  final ModuleConfigPrefs prefs;

  static const String _defaultPrefix = 'flutter.';

  @override
  Future<bool> clear() => clearWithPrefix(_defaultPrefix);

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: prefix)),
  );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    if (!prefs.available) return stock.clearWithParameters(parameters);
    final f = parameters.filter;
    await prefs.update(
      (p) => p.removeWhere((k, _) => _matches(k, f.prefix, f.allowList)),
    );
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() => getAllWithPrefix(_defaultPrefix);

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    if (!prefs.available) return stock.getAllWithParameters(parameters);
    final f = parameters.filter;
    final all = await prefs.read();
    return all..removeWhere((k, _) => !_matches(k, f.prefix, f.allowList));
  }

  @override
  Future<bool> remove(String key) async {
    if (!prefs.available) return stock.remove(key);
    await prefs.update((p) => p.remove(key));
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (!prefs.available) return stock.setValue(valueType, key, value);
    await prefs.update((p) => p[key] = value);
    return true;
  }
}

/// `SharedPreferencesAsync` and `SharedPreferencesWithCache` on a WebUI host.
base class SharedPreferencesWebUiAsync extends SharedPreferencesAsyncPlatform {
  SharedPreferencesWebUiAsync({required this.stock, required this.prefs});

  final SharedPreferencesAsyncPlatform stock;
  final ModuleConfigPrefs prefs;

  Future<void> _set(String key, Object value) =>
      prefs.update((p) => p[key] = value);

  Future<T?> _get<T>(String key) async {
    final v = (await prefs.read())[key];
    return v is T ? v : null;
  }

  @override
  Future<void> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) =>
      prefs.available ? _set(key, value) : stock.setString(key, value, options);

  @override
  Future<void> setBool(
    String key,
    bool value,
    SharedPreferencesOptions options,
  ) => prefs.available ? _set(key, value) : stock.setBool(key, value, options);

  @override
  Future<void> setDouble(
    String key,
    double value,
    SharedPreferencesOptions options,
  ) =>
      prefs.available ? _set(key, value) : stock.setDouble(key, value, options);

  @override
  Future<void> setInt(
    String key,
    int value,
    SharedPreferencesOptions options,
  ) => prefs.available ? _set(key, value) : stock.setInt(key, value, options);

  @override
  Future<void> setStringList(
    String key,
    List<String> value,
    SharedPreferencesOptions options,
  ) => prefs.available
      ? _set(key, List<String>.of(value))
      : stock.setStringList(key, value, options);

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) =>
      prefs.available ? _get<String>(key) : stock.getString(key, options);

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) =>
      prefs.available ? _get<bool>(key) : stock.getBool(key, options);

  @override
  Future<double?> getDouble(String key, SharedPreferencesOptions options) =>
      prefs.available ? _get<double>(key) : stock.getDouble(key, options);

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) =>
      prefs.available ? _get<int>(key) : stock.getInt(key, options);

  @override
  Future<List<String>?> getStringList(
    String key,
    SharedPreferencesOptions options,
  ) => prefs.available
      ? _get<List<String>>(key)
      : stock.getStringList(key, options);

  @override
  Future<void> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    if (!prefs.available) return stock.clear(parameters, options);
    final allow = parameters.filter.allowList;
    await prefs.update(
      (p) => p.removeWhere((k, _) => allow == null || allow.contains(k)),
    );
  }

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    if (!prefs.available) return stock.getPreferences(parameters, options);
    final allow = parameters.filter.allowList;
    final all = await prefs.read();
    return all..removeWhere((k, _) => allow != null && !allow.contains(k));
  }

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async => (await getPreferences(parameters, options)).keys.toSet();
}
