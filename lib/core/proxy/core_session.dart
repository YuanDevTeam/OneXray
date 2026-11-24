import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:onexray/core/ffi/base_ffi_api.dart';
import 'package:onexray/core/ffi/linux_ffi_api.dart';
import 'package:onexray/core/pigeon/desktop_proxy_api.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/proxy/system_proxy.dart';
import 'package:onexray/core/proxy/linux_process_identity.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

abstract interface class ProxyCoreSession {
  Stream<void> get exits;
  Map<String, dynamic>? get identity;
  Future<void> ensureRuntime();
  Future<void> start(StartVpnRequest request);
  Future<bool> isRunning();
  Future<void> stop();
  Future<void> recover(Map<String, dynamic>? identity);
}

final class MacProxyCoreSession implements ProxyCoreSession {
  final _api = DesktopProxyApi();

  @override
  Stream<void> get exits => const Stream.empty();
  @override
  Map<String, dynamic>? get identity => null;

  @override
  Future<void> ensureRuntime() async {
    final helper = File(
      p.normalize(
        p.join(
          p.dirname(Platform.resolvedExecutable),
          '..',
          'Helpers',
          'OneXrayProxyHelper.app',
          'Contents',
          'MacOS',
          'OneXrayProxyHelper',
        ),
      ),
    );
    if (!await helper.exists()) {
      throw StateError('The local proxy helper is missing.');
    }
  }

  void _check(NativeVpnCommandResult result, VpnStatus expected) {
    if (result.state != NativeVpnCommandState.success ||
        result.status != expected) {
      throw StateError(
        result.message ?? 'The local proxy helper command failed.',
      );
    }
  }

  @override
  Future<void> start(StartVpnRequest request) async => _check(
    await _api.start(jsonEncode(request.toJson())),
    VpnStatus.connected,
  );
  @override
  Future<bool> isRunning() async {
    final result = await _api.readStatus();
    if (result.state != NativeVpnCommandState.success) {
      throw StateError(
        result.message ?? 'Unable to read the local proxy helper state.',
      );
    }
    return result.status != VpnStatus.disconnected;
  }

  @override
  Future<void> stop() async =>
      _check(await _api.stop(), VpnStatus.disconnected);
  @override
  Future<void> recover(Map<String, dynamic>? identity) async {
    // The native host owns its child and shuts it down on control-channel EOF.
    // A Dart recovery record must never stop another Runner's helper.
  }
}

/// A normal child process for EXE/MSIX/Linux. No ShellExecute/runas, sudo,
/// system DNS setter, VPN provider, TUN or named-process cleanup is involved.
final class ProcessProxyCoreSession implements ProxyCoreSession {
  ProcessProxyCoreSession({
    Future<String> Function()? directory,
    String? executable,
    Future<Process> Function(String, List<String>)? startProcess,
    Future<Map<String, dynamic>?> Function(int)? readProcessIdentity,
  }) : directory = directory ?? _runtimeDataDirectory,
       executable =
           executable ??
           (Platform.isWindows
               ? p.join(
                   p.dirname(Platform.resolvedExecutable),
                   'OneXrayCore.exe',
                 )
               : LinuxFfiApi().corePath),
       _startProcess = startProcess ?? Process.start,
       _readProcessIdentityOverride = readProcessIdentity;

  static Future<String> _runtimeDataDirectory() async {
    final directory = AppHostApi().tunFilesDir;
    if (directory.isEmpty || !p.isAbsolute(directory)) {
      throw StateError('The proxy runtime data directory is unavailable.');
    }
    return directory;
  }

  final Future<String> Function() directory;
  final String executable;
  final Future<Process> Function(String, List<String>) _startProcess;
  final Future<Map<String, dynamic>?> Function(int)?
  _readProcessIdentityOverride;
  final _exits = StreamController<void>.broadcast();
  Process? _process;
  Map<String, dynamic>? _identity;
  Directory? _inputs;
  bool _stopping = false;

  @override
  Stream<void> get exits => _exits.stream;
  @override
  Map<String, dynamic>? get identity => _identity;

  @override
  Future<void> ensureRuntime() async {
    final file = File(executable);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size == 0 ||
        (!Platform.isWindows && (stat.mode & 0x49) == 0)) {
      throw StateError(
        'The local proxy Core executable is missing or not executable.',
      );
    }
  }

  @override
  Future<void> start(StartVpnRequest request) async {
    if (_process != null) {
      throw StateError('The local proxy Core is already running.');
    }
    await ensureRuntime();
    final invoke = request.coreInvokeText;
    if (invoke == null || invoke.isEmpty) {
      throw const FormatException('Missing proxy Core configuration');
    }
    final run = LibXrayRunConfig.fromInvokeText(invoke);
    if (run.invoke.apiVersion != 3 ||
        run.invoke.method != LibXrayMethod.runXray ||
        run.request.xrayJson?.isNotEmpty != true) {
      throw const FormatException('Invalid proxy Core start request');
    }
    final runDirectory = Directory(p.join(await directory(), 'run'));
    await runDirectory.create(recursive: true);
    final inputsRoot = Directory(p.join(runDirectory.path, 'proxy-inputs'));
    final inputType = await FileSystemEntity.type(
      inputsRoot.path,
      followLinks: false,
    );
    if (inputType != FileSystemEntityType.notFound &&
        inputType != FileSystemEntityType.directory) {
      throw const FormatException('Invalid proxy Core input directory');
    }
    await inputsRoot.create();
    if (!Platform.isWindows) {
      final protected = await Process.run('/bin/chmod', [
        '700',
        inputsRoot.path,
      ]);
      if (protected.exitCode != 0) {
        throw StateError('Unable to protect proxy Core inputs.');
      }
    }
    final inputs = await inputsRoot.createTemp('input-');
    _inputs = inputs;
    try {
      final config = File(p.join(inputs.path, 'xray.json'));
      await config.writeAsString(run.request.xrayJson!, flush: true);
      final logs = [
        for (final name in ['access.log', 'error.log'])
          File(p.join(runDirectory.path, name)),
      ];
      for (final file in logs) {
        final type = await FileSystemEntity.type(file.path, followLinks: false);
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.file) {
          throw const FormatException('Invalid runtime log file');
        }
      }
      for (final file in logs) {
        if (await file.exists()) await file.delete();
      }
      final errorFile = desktopCoreErrorFile(config.path);
      await errorFile.writeAsString('', flush: true);
      final process = await _startProcess(
        executable,
        desktopCoreRunArguments(
          dns: '',
          interfaceName: '',
          configPath: config.path,
          errorFile: errorFile.path,
          setDns: false,
        ),
      );
      _process = process;
      process.stdout.listen((_) {}, onError: (Object _) {});
      process.stderr.listen((_) {}, onError: (Object _) {});
      unawaited(
        process.exitCode.then((_) {
          if (identical(_process, process)) {
            _process = null;
            if (!_stopping) _exits.add(null);
          }
        }),
      );
      _identity = Platform.isLinux
          ? await LinuxProxyProcessIdentity().captureSpawned(
              process.pid,
              await File(executable).resolveSymbolicLinks(),
            )
          : await _processIdentity(process.pid);
      if (_identity == null || _process == null) {
        throw StateError(
          await readDesktopCoreStartError(
            config.path,
            'The local proxy Core exited during startup.',
          ),
        );
      }
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  @override
  Future<bool> isRunning() async => _process != null;

  @override
  Future<void> stop() async {
    _stopping = true;
    try {
      final process = _process;
      if (process != null) {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(seconds: 3));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode.timeout(const Duration(seconds: 2));
        }
        if (identical(_process, process)) _process = null;
      }
      _identity = null;
      final inputs = _inputs;
      if (inputs != null && await inputs.exists()) {
        await inputs.delete(recursive: true);
      }
      _inputs = null;
    } finally {
      _stopping = false;
    }
  }

  @override
  Future<void> recover(Map<String, dynamic>? identity) async {
    if (identity == null) return;
    final processId = identity['pid'];
    if (processId is! int ||
        processId <= 0 ||
        identity['executable'] is! String ||
        identity['created'] is! String ||
        identity['platform'] != Platform.operatingSystem) {
      throw const FormatException('Invalid proxy Core recovery identity');
    }
    // A package update can move/remove the installed image. A gone or reused PID
    // needs no cleanup, so do not block ordinary startup on its former path.
    final actual = await _processIdentity(processId);
    if (actual == null || !proxyValuesEqual(actual, identity)) return;
    final installedImage = await File(executable).resolveSymbolicLinks();
    final expectedImage = Platform.isWindows
        ? p.windows.normalize(installedImage).toLowerCase()
        : installedImage;
    if (identity['executable'] != expectedImage) {
      throw const FormatException(
        'The previous proxy Core belongs to another installation',
      );
    }
    if (Platform.isWindows) {
      _WindowsProcessIdentity().terminate(identity);
    } else {
      await LinuxProxyProcessIdentity().signalIfMatches(identity, 15);
    }
    var deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final current = await _processIdentity(processId);
      if (!proxyValuesEqual(current, identity)) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!Platform.isWindows) {
      await LinuxProxyProcessIdentity().signalIfMatches(identity, 9);
    }
    deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (!proxyValuesEqual(await _processIdentity(processId), identity)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('The previous local proxy Core did not stop.');
  }

  Future<Map<String, dynamic>?> _processIdentity(int processId) async {
    if (_readProcessIdentityOverride != null) {
      return _readProcessIdentityOverride(processId);
    }
    if (Platform.isWindows) return _WindowsProcessIdentity().read(processId);
    return LinuxProxyProcessIdentity().read(processId);
  }
}

final class _WindowsProcessIdentity {
  win32.HANDLE? _handle(int pid, {bool terminate = false}) {
    var access = win32.PROCESS_QUERY_LIMITED_INFORMATION;
    if (terminate) access |= win32.PROCESS_TERMINATE;
    // The Win32 wrapper resolves GetLastError before opening the process, then
    // captures the error immediately so FFI lookup cannot overwrite it.
    final opened = win32.OpenProcess(access, false, pid);
    if (opened.value.isValid) return opened.value;
    if (opened.error == win32.ERROR_INVALID_PARAMETER ||
        opened.error == win32.ERROR_NOT_FOUND) {
      return null;
    }
    throw StateError(
      'Unable to verify the previous local proxy Core (${opened.error.code}).',
    );
  }

  Map<String, dynamic>? read(int pid) {
    final handle = _handle(pid);
    if (handle == null) return null;
    try {
      return _readHandle(handle, pid);
    } finally {
      win32.CloseHandle(handle);
    }
  }

  Map<String, dynamic> _readHandle(win32.HANDLE handle, int pid) =>
      using((arena) {
        final created = arena<win32.FILETIME>();
        final times = win32.GetProcessTimes(
          handle,
          created,
          arena<win32.FILETIME>(),
          arena<win32.FILETIME>(),
          arena<win32.FILETIME>(),
        );
        if (!times.value) {
          throw StateError(
            'Unable to verify proxy Core creation time (${times.error.code}).',
          );
        }
        const pathCapacity = 32768;
        final image = win32.PWSTR(arena<Uint16>(pathCapacity).cast());
        final length = arena<Uint32>()..value = pathCapacity;
        final queried = win32.QueryFullProcessImageName(
          handle,
          win32.PROCESS_NAME_WIN32,
          image,
          length,
        );
        if (!queried.value) {
          throw StateError(
            'Unable to verify proxy Core image (${queried.error.code}).',
          );
        }
        // Keep the original decimal FILETIME value for persisted identities.
        final createdTicks =
            (created.ref.dwHighDateTime << 32) | created.ref.dwLowDateTime;
        return {
          'platform': 'windows',
          'pid': pid,
          'executable': p.windows
              .normalize(image.toDartString(length: length.value))
              .toLowerCase(),
          'created': createdTicks.toString(),
        };
      });

  void terminate(Map<String, dynamic> identity) {
    final pid = identity['pid'] as int;
    final handle = _handle(pid, terminate: true);
    if (handle == null) return;
    try {
      if (!proxyValuesEqual(_readHandle(handle, pid), identity)) return;
      final terminated = win32.TerminateProcess(handle, 0);
      if (!terminated.value) {
        throw StateError(
          'Unable to stop the previous local proxy Core (${terminated.error.code}).',
        );
      }
    } finally {
      win32.CloseHandle(handle);
    }
  }
}

/// SOCKS greeting only: no external network request or node-speed prerequisite.
Future<void> waitForProxyListener(
  int port,
  Future<bool> Function() running,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    if (!await running()) {
      throw StateError('The local proxy Core exited during startup.');
    }
    Socket? socket;
    StreamIterator<List<int>>? input;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 300),
      );
      input = StreamIterator(socket);
      socket.add([5, 1, 0]);
      await socket.flush();
      final response = <int>[];
      while (response.length < 2 &&
          await input.moveNext().timeout(const Duration(milliseconds: 300))) {
        response.addAll(input.current);
      }
      if (response.length >= 2 &&
          response[0] == 5 &&
          response[1] == 0 &&
          await running()) {
        return;
      }
    } on SocketException {
      // Core construction may still be finishing; the bound listener is checked.
    } on TimeoutException {
      // A different/half-initialized protocol is not a successful proxy startup.
    } finally {
      socket?.destroy();
      await input?.cancel();
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('The local HTTP/SOCKS proxy did not become ready.');
}
