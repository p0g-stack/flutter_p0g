import 'package:args/command_runner.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/runner/flutter_command_runner.dart';

/// Top-level runner. Like flutterpi_tool's, it implements
/// [FlutterCommandRunner] so flutter_tools commands find the global options
/// they read, without inheriting the `flutter` command's own setup.
class P0gCommandRunner extends CommandRunner<void> implements FlutterCommandRunner {
  P0gCommandRunner({bool verboseHelp = false})
    : super(
        'flutter_p0g',
        'Builds a Flutter app for WebUI (KernelSU-style module) and AERA.',
        usageLineLength: 100,
      ) {
    argParser
      ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Verbose logging.')
      ..addOption(FlutterGlobalOptions.kPackagesOption, hide: true)
      ..addOption(FlutterGlobalOptions.kDeviceIdOption, abbr: 'd', hide: true)
      ..addOption(
        FlutterGlobalOptions.kLocalWebSDKOption,
        hide: !verboseHelp,
        help: 'Use a locally built web SDK (engine out directory name).',
      )
      ..addFlag(FlutterGlobalOptions.kPrintDtd, negatable: false, hide: true)
      ..addFlag(FlutterGlobalOptions.kContinuousIntegrationFlag, negatable: false, hide: true)
      ..addOption(FlutterGlobalOptions.kDebugLogsDirectoryFlag, hide: true);
  }

  @override
  String get usageFooter => '';

  @override
  List<Directory> getRepoPackages() => throw UnimplementedError();

  @override
  List<String> getRepoRoots() => throw UnimplementedError();
}
