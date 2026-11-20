import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../launcher.dart';

/// Starts a program; [Process.start] by default. Tests pass a fake.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});

Future<Process> _start(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode = ProcessStartMode.normal,
}) => Process.start(executable, arguments, mode: mode);

/// Starts a place host with administrator rights through the OS's own
/// elevation front-end, the way installers and disk writers do (balenaEtcher's
/// `sudo-prompt`, for one): the person sees the system's own prompt.
///
/// Siblings, one per front-end, all plain [ProcessLauncher]s; a platform with
/// its own way in (a privileged helper it already runs, for instance) supplies its own
/// launcher instead:
///
/// | Launcher | Front-end | Host's stdout |
/// |---|---|---|
/// | [PkexecLauncher] | polkit (`pkexec`), Linux desktops | seen |
/// | [SuLauncher] | `su -c`, rooted Android and other `su` setups | seen |
/// | [MacAdminLauncher] | `osascript ... with administrator privileges` (Authorization Services prompt), macOS | not seen |
/// | [WindowsRunAsLauncher] | `Start-Process -Verb RunAs` (UAC), Windows | not seen |
///
/// Where stdout is not seen, `ProcessPlace` finds the host through its
/// `EndpointStore` instead, matching the launch id; give the host a
/// `--session-file` in a directory only this user can open (POSIX: a 0700
/// directory such as `$XDG_RUNTIME_DIR` or one made by
/// `Directory.systemTemp.createTemp`), because the file holds the token.
///
/// The token never travels through the command line: the host generates it.
abstract class ElevatedLauncher implements ProcessLauncher {
  const ElevatedLauncher({this.starter});

  /// Starts the front-end; [Process.start] when null.
  final ProcessStarter? starter;

  /// The elevation launcher for the OS this runs on, or null if there is
  /// none (iOS, Fuchsia).
  static ElevatedLauncher? forHost() {
    if (Platform.isAndroid) return const SuLauncher();
    if (Platform.isLinux) return const PkexecLauncher();
    if (Platform.isMacOS) return const MacAdminLauncher();
    if (Platform.isWindows) return const WindowsRunAsLauncher();
    return null;
  }

  /// Whether the host's stdout reaches this process.
  bool get seesStdout;

  /// The program and arguments that start [command] elevated.
  (String, List<String>) wrap(ProcessCommand command);

  @override
  Future<LaunchedProcess> launch(ProcessCommand command) async {
    final (exe, args) = wrap(command);
    final p = await (starter ?? _start)(
      exe,
      args,
      mode: ProcessStartMode.detachedWithStdio,
    );
    p.stderr.drain<void>().ignore();
    if (!seesStdout) {
      p.stdout.drain<void>().ignore();
      return _Launched(p.pid, const Stream<String>.empty());
    }
    return _Launched(
      p.pid,
      p.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream(),
    );
  }
}

class _Launched implements LaunchedProcess {
  _Launched(this.pid, this.stdoutLines);

  @override
  final int? pid;

  @override
  final Stream<String> stdoutLines;

  /// A detached front-end cannot be waited on.
  @override
  Future<int> get exitCode => Completer<int>().future;
}

/// Linux desktops: polkit's `pkexec`. Environment and working directory go
/// through `env` (coreutils), since pkexec resets both.
class PkexecLauncher extends ElevatedLauncher {
  const PkexecLauncher({
    this.pkexec = 'pkexec',
    this.env = '/usr/bin/env',
    super.starter,
  });

  final String pkexec;
  final String env;

  @override
  bool get seesStdout => true;

  @override
  (String, List<String>) wrap(ProcessCommand c) {
    final needsEnv = c.environment.isNotEmpty || c.workingDirectory != null;
    return (
      pkexec,
      [
        if (needsEnv) ...[
          env,
          if (c.workingDirectory != null) ...['-C', c.workingDirectory!],
          for (final e in c.environment.entries) '${e.key}=${e.value}',
        ],
        c.executable,
        ...c.arguments,
      ],
    );
  }
}

/// `su -c '<command>'`: rooted Android (Magisk, KernelSU, APatch all accept
/// it) and other systems where `su` is the way in.
class SuLauncher extends ElevatedLauncher {
  const SuLauncher({this.su = 'su', super.starter});

  final String su;

  @override
  bool get seesStdout => true;

  @override
  (String, List<String>) wrap(ProcessCommand c) =>
      (su, ['-c', posixCommandLine(c)]);
}

/// macOS: `do shell script ... with administrator privileges`, which shows the
/// Authorization Services password prompt. The host is backgrounded with its
/// output discarded so osascript returns once it has started.
class MacAdminLauncher extends ElevatedLauncher {
  const MacAdminLauncher({
    this.osascript = '/usr/bin/osascript',
    this.prompt,
    super.starter,
  });

  final String osascript;

  /// Text shown in the password prompt.
  final String? prompt;

  @override
  bool get seesStdout => false;

  @override
  (String, List<String>) wrap(ProcessCommand c) {
    final shell = '${posixCommandLine(c)} </dev/null >/dev/null 2>&1 &';
    final withPrompt = prompt == null
        ? ''
        : ' with prompt ${appleScriptString(prompt!)}';
    return (
      osascript,
      [
        '-e',
        'do shell script ${appleScriptString(shell)}'
            '$withPrompt with administrator privileges',
      ],
    );
  }
}

/// Windows: PowerShell `Start-Process -Verb RunAs`, which shows the UAC
/// prompt. RunAs cannot pass an environment; a command with one is refused.
class WindowsRunAsLauncher extends ElevatedLauncher {
  const WindowsRunAsLauncher({
    this.powershell = 'powershell.exe',
    super.starter,
  });

  final String powershell;

  @override
  bool get seesStdout => false;

  @override
  (String, List<String>) wrap(ProcessCommand c) {
    if (c.environment.isNotEmpty) {
      throw ArgumentError.value(
        c.environment,
        'environment',
        'UAC elevation (RunAs) cannot pass environment variables',
      );
    }
    final script = StringBuffer(
      'Start-Process -FilePath ${powerShellString(c.executable)}',
    );
    if (c.arguments.isNotEmpty) {
      final line = c.arguments.map(windowsArgument).join(' ');
      script.write(' -ArgumentList ${powerShellString(line)}');
    }
    if (c.workingDirectory != null) {
      script.write(
        ' -WorkingDirectory ${powerShellString(c.workingDirectory!)}',
      );
    }
    script.write(' -Verb RunAs -WindowStyle Hidden');
    return (
      powershell,
      ['-NoProfile', '-NonInteractive', '-Command', script.toString()],
    );
  }
}

/// [c] as one POSIX `sh` command line, with its environment and working
/// directory applied.
String posixCommandLine(ProcessCommand c) {
  final b = StringBuffer();
  if (c.workingDirectory != null) {
    b.write('cd ${shellQuote(c.workingDirectory!)} && ');
  }
  b.write('exec ');
  if (c.environment.isNotEmpty) {
    b.write('env ');
    for (final e in c.environment.entries) {
      b.write('${shellQuote('${e.key}=${e.value}')} ');
    }
  }
  b.write([c.executable, ...c.arguments].map(shellQuote).join(' '));
  return b.toString();
}

/// Single-quotes [s] for POSIX `sh`.
String shellQuote(String s) {
  if (s.isNotEmpty && RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(s)) {
    return s;
  }
  return "'${s.replaceAll("'", r"'\''")}'";
}

/// [s] as an AppleScript string literal.
String appleScriptString(String s) =>
    '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

/// [s] as a PowerShell single-quoted string literal.
String powerShellString(String s) => "'${s.replaceAll("'", "''")}'";

/// Quotes one argument the way `CommandLineToArgvW` (and the MSVC runtime)
/// parses it back.
String windowsArgument(String s) {
  if (s.isNotEmpty && !RegExp(r'[\s"]').hasMatch(s)) return s;
  final b = StringBuffer('"');
  var backslashes = 0;
  for (final ch in s.split('')) {
    if (ch == r'\') {
      backslashes++;
    } else if (ch == '"') {
      b.write(r'\' * (backslashes * 2 + 1));
      b.write('"');
      backslashes = 0;
    } else {
      b.write(r'\' * backslashes);
      b.write(ch);
      backslashes = 0;
    }
  }
  b.write(r'\' * (backslashes * 2));
  b.write('"');
  return b.toString();
}
