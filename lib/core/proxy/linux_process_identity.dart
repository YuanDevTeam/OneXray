import 'dart:ffi';
import 'dart:io';

import 'package:onexray/core/proxy/system_proxy.dart';

/// /proc/pid/exe is ptrace-gated and may be unreadable after exec of a binary
/// with file capabilities, even to its same-UID parent. A newly spawned Process
/// already establishes the executable; do not make readlink a launch condition.
final class LinuxProxyProcessIdentity {
  LinuxProxyProcessIdentity({
    Future<String> Function(String)? readText,
    Future<String> Function(String)? resolveImage,
  }) : _readText = readText ?? ((path) => File(path).readAsString()),
       _resolveImage =
           resolveImage ?? ((path) => Link(path).resolveSymbolicLinks());

  final Future<String> Function(String) _readText;
  final Future<String> Function(String) _resolveImage;

  Future<Map<String, dynamic>?> captureSpawned(
    int pid,
    String executable,
  ) async {
    final metadata = await _metadata(pid);
    return metadata == null ? null : {...metadata, 'executable': executable};
  }

  /// Recovery has no live Process handle. It needs independent image identity;
  /// unreadable privileged processes are left for the user rather than guessed.
  Future<Map<String, dynamic>?> read(int pid) async {
    try {
      final before = await _metadata(pid);
      if (before == null) return null;
      final image = await _resolveImage('/proc/$pid/exe');
      if (!proxyValuesEqual(await _metadata(pid), before)) return null;
      return {...before, 'executable': image};
    } on FileSystemException catch (error) {
      if (_gone(error)) return null;
      if (error.osError?.errorCode == 13 || error.osError?.errorCode == 1) {
        throw StateError(
          'The previous local proxy Core image cannot be verified. Stop that process manually and retry.',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _metadata(int pid) async {
    try {
      final stat = await _readText('/proc/$pid/stat');
      final end = stat.lastIndexOf(')');
      if (end < 0) {
        throw const FormatException('Invalid Linux proxy Core identity');
      }
      final fields = stat.substring(end + 2).trim().split(RegExp(r'\s+'));
      if (fields.length <= 19) {
        throw const FormatException('Invalid Linux proxy Core identity');
      }
      if (fields[0] == 'Z' || fields[0] == 'X') return null;
      final status = await _readText('/proc/$pid/status');
      final uid = RegExp(
        r'^Uid:\s+(\d+)\s+(\d+)',
        multiLine: true,
      ).firstMatch(status);
      final boot = (await _readText('/proc/sys/kernel/random/boot_id')).trim();
      if (uid == null ||
          !RegExp(r'^\d+$').hasMatch(fields[19]) ||
          !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(boot)) {
        throw const FormatException('Invalid Linux proxy Core identity');
      }
      return {
        'platform': 'linux',
        'pid': pid,
        'created': fields[19],
        'uid': uid.group(1),
        'effectiveUid': uid.group(2),
        'bootId': boot,
      };
    } on FileSystemException catch (error) {
      if (_gone(error)) return null;
      rethrow;
    }
  }

  static bool _gone(FileSystemException error) =>
      error.osError?.errorCode == 2 || error.osError?.errorCode == 3;

  /// Pin the process with a pidfd before the last identity check, so PID reuse
  /// between checking /proc and signalling cannot terminate a different process.
  Future<void> signalIfMatches(
    Map<String, dynamic> identity,
    int signal,
  ) async {
    final native = _LinuxPidfd();
    final descriptor = native.open(identity['pid'] as int, 0);
    if (descriptor < 0) {
      if (native.error() == 3) return;
      throw OSError(
        'Unable to pin the previous local proxy Core',
        native.error(),
      );
    }
    try {
      if (!proxyValuesEqual(await read(identity['pid'] as int), identity)) {
        return;
      }
      if (native.signal(descriptor, signal, nullptr, 0) != 0 &&
          native.error() != 3) {
        throw OSError(
          'Unable to stop the previous local proxy Core',
          native.error(),
        );
      }
    } finally {
      native.close(descriptor);
    }
  }
}

final class _LinuxPidfd {
  final _libc = DynamicLibrary.open('libc.so.6');
  late final open = _libc
      .lookupFunction<Int32 Function(Int32, Uint32), int Function(int, int)>(
        'pidfd_open',
      );
  late final signal = _libc
      .lookupFunction<
        Int32 Function(Int32, Int32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)
      >('pidfd_send_signal');
  late final close = _libc
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final _errno = _libc
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        '__errno_location',
      );
  int error() => _errno().value;
}
