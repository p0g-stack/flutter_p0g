import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _OpenC = Int32 Function(Pointer<Utf8> path, Int32 flags);
typedef _Open = int Function(Pointer<Utf8> path, int flags);
typedef _CloseC = Int32 Function(Int32 fd);
typedef _Close = int Function(int fd);

/// Whether `open(path, O_RDONLY)` succeeds, through libc.
///
/// `dart:io` cannot answer this for block devices: `File.open` accepts only
/// regular files, character devices and pipes, and reports a block device as
/// not found (its `FileSystemEntityType` is `notFound` too). So reading a
/// partition from Dart goes through libc, or through a tool such as `dd`.
bool canOpenForReading(String path) {
  final libc = DynamicLibrary.process();
  final open = libc.lookupFunction<_OpenC, _Open>('open');
  final close = libc.lookupFunction<_CloseC, _Close>('close');
  final cPath = path.toNativeUtf8();
  try {
    final fd = open(cPath, 0); // O_RDONLY
    if (fd < 0) return false;
    close(fd);
    return true;
  } finally {
    malloc.free(cPath);
  }
}
