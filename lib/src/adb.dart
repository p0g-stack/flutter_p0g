import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

/// POSIX single-quote quoting.
String shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// The adb flutter_tools found, else the one on PATH.
String? adbPath() => globals.androidSdk?.adbPath ?? globals.os.which('adb')?.path;

/// One adb device as `adb devices -l` lists it.
typedef AdbDevice = ({String serial, String state, String? model});

/// Parses `adb devices -l`.
List<AdbDevice> parseAdbDevices(String out) => [
  for (final line in out.split('\n').skip(1))
    if (line.trim().split(RegExp(r'\s+')) case [final serial, final state, ...final rest]
        when serial.isNotEmpty)
      (
        serial: serial,
        state: state,
        model: [
          for (final f in rest)
            if (f.startsWith('model:')) f.substring('model:'.length),
        ].firstOrNull,
      ),
];

/// adb bound to one device.
class Adb {
  Adb(this.path, this.serial);

  /// adb for [serial], or the only device when [serial] is null.
  static Adb find(String? serial) {
    final path = adbPath();
    if (path == null) throwToolExit('No adb found. Install the Android SDK platform-tools.');
    return Adb(path, serial);
  }

  final String path;
  final String? serial;

  List<String> command(List<String> args) => [
    path,
    if (serial != null) ...['-s', serial!],
    ...args,
  ];

  /// The device's state (`device`, `recovery`, ...), or null with none.
  Future<String?> state() async => (await run(['get-state'], check: false))?.trim();

  /// Runs adb with [args]: its stdout, or null (or a tool exit with [check])
  /// on failure.
  Future<String?> run(List<String> args, {bool check = true}) async {
    final cmd = command(args);
    final r = await globals.processUtils.run(cmd);
    if (r.exitCode != 0) {
      if (check) throwToolExit('${cmd.join(' ')} failed:\n${r.stderr}');
      return null;
    }
    return r.stdout;
  }

  /// Runs adb with [args], its output streamed to the terminal.
  Future<void> stream(List<String> args) async {
    final cmd = command(args);
    final code = await globals.processUtils.stream(cmd);
    if (code != 0) throwToolExit('${cmd.join(' ')} failed (exit $code).');
  }

  /// [script] in a root shell: `su -c` on Android, the shell itself in
  /// recovery (already root).
  List<String> rootShell(String script, {required bool recovery}) =>
      recovery ? ['shell', script] : ['shell', 'su -c ${shellQuote(script)}'];
}
