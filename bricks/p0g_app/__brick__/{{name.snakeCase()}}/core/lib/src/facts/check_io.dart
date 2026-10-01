import 'dart:io';

{{#rust}}import '../native/native.dart';
{{/rust}}import 'facts.dart';

/// Checks the facts of the current Dart VM process.
///
/// Every value is the result of a check made here, at call time; nothing is
/// inferred from `Platform`. A check that cannot run reports false.
Future<Map<String, Object?>> checkFacts() async {
  final root = await _isRoot();
  return {
    Fact.root: root,
    Fact.blockDevices: await _canReadBlockDevice(),
    Fact.usbNative: await _canOpenDir('/dev/bus/usb'),
    Fact.usbWeb: false,
    Fact.processSpawn: await _canSpawn(),
    Fact.fsPersistent: await _canWriteWorkingDir(),
    Fact.net: await _hasNetwork(),
{{#rust}}    Fact.native: await loadNative(),
{{/rust}}  };
}

Future<bool> _isRoot() async {
  // Linux and Android: effective uid is the second field of "Uid:".
  try {
    final status = await File('/proc/self/status').readAsLines();
    final line = status.firstWhere((l) => l.startsWith('Uid:'));
    final ids = line.split(RegExp(r'\s+'));
    return ids.length > 2 && ids[2] == '0';
  } catch (_) {}
  try {
    final r = await Process.run('id', ['-u']);
    return r.exitCode == 0 && '${r.stdout}'.trim() == '0';
  } catch (_) {
    return false;
  }
}

Future<bool> _canReadBlockDevice() async {
  // A block device listed by the kernel that this process can open for
  // reading.
  try {
    final names = await Directory('/sys/class/block')
        .list()
        .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
        .toList();
    for (final name in names) {
      for (final node in ['/dev/block/$name', '/dev/$name']) {
        RandomAccessFile? f;
        try {
          f = await File(node).open();
          return true;
        } catch (_) {
          // not present or not readable
        } finally {
          await f?.close();
        }
      }
    }
  } catch (_) {}
  return false;
}

Future<bool> _canOpenDir(String path) async {
  try {
    await Directory(path).list().first;
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _canSpawn() async {
  try {
    final shell = File('/system/bin/sh').existsSync() ? '/system/bin/sh' : 'sh';
    final r = await Process.run(shell, ['-c', 'exit 0']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<bool> _canWriteWorkingDir() async {
  // The working directory, not the temp dir: temp is often a tmpfs.
  try {
    final dir = await Directory.current.createTemp('.p0g_facts_');
    await dir.delete(recursive: true);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _hasNetwork() async {
  try {
    final ifs = await NetworkInterface.list(includeLoopback: false);
    return ifs.any((i) => i.addresses.isNotEmpty);
  } catch (_) {
    return false;
  }
}
