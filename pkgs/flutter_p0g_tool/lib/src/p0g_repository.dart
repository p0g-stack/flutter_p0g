import 'dart:isolate';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

/// The p0g repository this tool runs from, at the tool's own commit.
///
/// Pub checks out the full repository at the git ref. Its `--git-path`
/// option selects the launcher package inside that checkout; the tool,
/// plugins and web SDK sources are siblings in the same revision.
///
/// Read only: a pub git cache belongs to pub (`pub cache repair` resets it
/// with `git clean -dfx`), so nothing the tool resolves or builds is written
/// under this directory.
Future<Directory> p0gRepository() async {
  final lib = await Isolate.resolvePackageUri(Uri.parse('package:flutter_p0g_tool/'));
  if (lib == null) throwToolExit('Cannot locate package:flutter_p0g_tool.');
  final package = globals.fs.directory(lib.toFilePath()).parent;
  final pkgs = package.parent;
  if (pkgs.basename != 'pkgs') {
    throwToolExit(
      '${package.path} is not inside the p0g repository (pkgs/${package.basename}). '
      'Activate it from the repository: dart pub global activate --source git '
      'https://github.com/p0g-stack/p0g --git-path pkgs/flutter_p0g',
    );
  }
  return pkgs.parent;
}
