import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/core_imports_flutter.dart';
import 'src/strategy_reads_platform.dart';

/// The analyzer plugin. A p0g_app workspace turns it on in
/// `analysis_options.yaml`; `dart analyze` and the IDE then report both rules
/// as warnings.
final plugin = P0gLints();

class P0gLints extends Plugin {
  @override
  String get name => 'p0g_lints';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(CoreImportsFlutter())
      ..registerWarningRule(StrategyReadsPlatform());
  }
}
