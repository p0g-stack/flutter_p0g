import 'dart:async';

import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/build_system/build_targets.dart';
import 'package:flutter_tools/src/build_system/targets/hook_runner_native.dart';
import 'package:flutter_tools/src/context_runner.dart' as fl;
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/hook_runner.dart';
import 'package:flutter_tools/src/isolated/build_targets.dart';
import 'package:flutter_tools/src/isolated/mustache_template.dart';
import 'package:flutter_tools/src/isolated/resident_web_runner.dart';
import 'package:flutter_tools/src/web/web_runner.dart';
import 'package:unified_analytics/unified_analytics.dart';

import 'webui/flutter_webui.dart';

/// flutter_tools' own context, with the overrides its executable.dart makes
/// for what the base context leaves out (build targets, hook runner, mustache)
/// plus, as flutterpi_tool does, no analytics and a verbose logger on `-v`.
Future<V> runInP0gContext<V>(FutureOr<V> Function() fn, {bool verbose = false}) {
  return fl.runInContext(
    fn,
    overrides: {
      Analytics: () => const NoOpAnalytics(),
      TemplateRenderer: () => const MustacheTemplateRenderer(),
      BuildTargets: () => const BuildTargetsImpl(),
      // The patched web SDK, once precached, without touching bin/cache.
      Artifacts: () => P0gArtifacts(
        CachedArtifacts(
          fileSystem: globals.fs,
          platform: globals.platform,
          cache: globals.cache,
          operatingSystemUtils: globals.os,
        ),
        stockWebSdk: globals.cache.getWebSdkDirectory().path,
        patchedWebSdk: patchedWebSdk(),
      ),
      FlutterHookRunner: () => FlutterHookRunnerNative(),
      WebRunnerFactory: () => DwdsWebRunnerFactory(),
      Logger: () {
        final Logger base = StdoutLogger(
          terminal: globals.terminal,
          stdio: globals.stdio,
          outputPreferences: globals.outputPreferences,
        );
        return verbose ? VerboseLogger(base) : base;
      },
    },
  );
}
