import 'dart:convert';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

/// The Rust target for an AERA target platform: the kit runs a glibc
/// userland (`usr/lib/ld-linux-*.so.1`), so the app's crate builds as plain
/// `*-unknown-linux-gnu`, not for Android.
String aeraRustTriple(String targetPlatform) => switch (targetPlatform) {
  'linux-arm64' => 'aarch64-unknown-linux-gnu',
  'linux-x64' => 'x86_64-unknown-linux-gnu',
  _ => throwToolExit('No Rust target for $targetPlatform.'),
};

/// The environment cargo needs to link for [triple]: the cross linker in
/// `CARGO_TARGET_<TRIPLE>_LINKER` unless already set. [onPath] says whether a
/// program is on PATH. An x86_64 target links with the host's own linker.
Map<String, String> aeraRustEnvironment(
  String triple,
  Map<String, String> env,
  bool Function(String program) onPath,
) {
  if (triple.startsWith('x86_64-')) return const {};
  final key = 'CARGO_TARGET_${triple.toUpperCase().replaceAll('-', '_')}_LINKER';
  if (env[key] != null && env[key]!.isNotEmpty) return const {};
  final gcc = '${triple.split('-').first}-linux-gnu-gcc';
  if (!onPath(gcc)) {
    throwToolExit(
      'Building rust/ for AERA needs a cross linker: $gcc on PATH '
      '(Debian/Ubuntu: apt install gcc-aarch64-linux-gnu) or $key set, and '
      '`rustup target add $triple`. Or pass --device-rust-libs=<dir> or --no-device-rust.',
    );
  }
  return {key: gcc};
}

/// cargo's target directory for the crate in [rustDir] (honours workspaces
/// and CARGO_TARGET_DIR).
Future<Directory> _cargoTargetDir(Directory rustDir) async {
  final r = await globals.processUtils.run([
    'cargo', 'metadata', '--format-version', '1', '--no-deps', //
  ], workingDirectory: rustDir.path);
  if (r.exitCode != 0) throwToolExit('cargo metadata failed (is cargo installed?):\n$r');
  final dir = (jsonDecode(r.stdout) as Map<String, Object?>)['target_directory'] as String;
  return globals.fs.directory(dir);
}

/// rust/ cross-built in release for [triple]; returns its `*.so` files.
Future<List<File>> buildRustForAera(Directory rustDir, String triple) async {
  final env = aeraRustEnvironment(
    triple,
    globals.platform.environment,
    (p) => globals.os.which(p) != null,
  );
  final code = await globals.processUtils.stream(
    ['cargo', 'build', '--release', '--target', triple],
    workingDirectory: rustDir.path,
    environment: env,
  );
  if (code != 0) {
    throwToolExit(
      'cargo build --target $triple failed (exit $code). '
      'The target needs `rustup target add $triple`.',
    );
  }
  final release = (await _cargoTargetDir(rustDir)).childDirectory(triple).childDirectory('release');
  final libs = _sharedLibs(release);
  if (libs.isEmpty) {
    throwToolExit('rust/ built no shared library in ${release.path} (crate-type cdylib?).');
  }
  return libs;
}

/// rust/ built elsewhere: `<dir>/<triple>/*.so` (per-target, like
/// `--device-rust-libs` for webui), else `<dir>/*.so`.
List<File> prebuiltAeraRustLibs(Directory dir, String triple) {
  final perTarget = dir.childDirectory(triple);
  final from = perTarget.existsSync() ? perTarget : dir;
  if (!from.existsSync()) throwToolExit('--device-rust-libs: no ${dir.path}');
  final libs = _sharedLibs(from);
  if (libs.isEmpty) throwToolExit('--device-rust-libs: no *.so in ${from.path}');
  return libs;
}

List<File> _sharedLibs(Directory dir) => dir.existsSync()
    ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.so')).toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
    : <File>[];
