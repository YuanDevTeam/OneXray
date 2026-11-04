import 'dart:async';

import 'package:onexray/core/ffi/base_ffi_api.dart';
import 'package:onexray/core/ffi/windows/ffi_api.dart';
import 'package:onexray/core/ffi/windows/core_process.dart';
import 'package:onexray/core/ffi/windows/model.dart';
import 'package:onexray/core/ffi/windows/native_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/pigeon/model_reader.dart';
import 'package:onexray/core/pigeon/model_writer.dart';
import 'package:onexray/core/tools/logger.dart';

class WindowsMsixFfiApi extends WindowsFfiApi {
  WindowsMsixFfiApi({
    WindowsNativeApi? native,
    WindowsCoreProcess? coreProcess,
    Future<StartVpnRequest> Function()? readRequest,
    Future<void> Function(VpnStatus)? notify,
    void Function(Object)? notifyError,
    this.monitorInterval = const Duration(seconds: 5),
    this.confirmInterval = const Duration(milliseconds: 200),
    this.startTimeout = const Duration(seconds: 30),
    this.stopTimeout = const Duration(seconds: 15),
  }) : _native = native ?? WindowsNativeApi(),
       _coreProcess = coreProcess ?? WindowsCoreProcess(),
       _readRequest = readRequest ?? StartVpnRequestReader.readFromStartFile,
       _notify = notify ?? AppFlutterApi().vpnStatusChanged,
       _notifyError =
           notifyError ?? AppFlutterApi().vpnStatusController.addError,
       super.base();

  static const _coreRelativePath = 'OneXrayCore.exe';

  final WindowsNativeApi _native;
  final WindowsCoreProcess _coreProcess;
  final Future<StartVpnRequest> Function() _readRequest;
  final Future<void> Function(VpnStatus) _notify;
  final void Function(Object) _notifyError;
  final Duration monitorInterval, confirmInterval, startTimeout, stopTimeout;
  Timer? _monitor;
  Future<void>? _checking;
  bool _commandActive = false;
  VpnStatus? _lastNotified;
  String? _packageLocalDataDir;

  @override
  Future<String> getTunFilesDir() async => _packageLocalDataDir ??=
      (await _native.getEnvironment()).packageLocalDataDir;

  @override
  Future<void> ensureRuntime() async {
    await getTunFilesDir();
    await checkRuntimeFiles(const [
      'libXray.dll',
      _coreRelativePath,
      'vole.dll',
      'vole-windows-vpn-host.exe',
      'vole-windows-session-host.exe',
    ]);
  }

  @override
  Future<NativeVpnCommandResult> readVpnStatus() async {
    try {
      final state = await _native.getVpnStatus();
      return commandSuccess(status: _status(state.status));
    } catch (error) {
      ygLogger('read Windows VPN status failed: $error');
      return commandFailed(error.toString());
    }
  }

  @override
  Future<void> observeVpnStatus() async {
    _monitor ??= Timer.periodic(monitorInterval, (_) => unawaited(_check()));
    await _check();
  }

  @override
  void disposeVpnStatus() {
    _monitor?.cancel();
    _monitor = null;
    _lastNotified = null;
  }

  Future<void> _check() =>
      _checking ??= _reconcile().whenComplete(() => _checking = null);

  Future<void> _reconcile() async {
    if (_commandActive || _monitor == null) return;
    try {
      final state = await _native.getVpnStatus();
      if (_commandActive || _monitor == null) return;
      final active =
          state.status == WindowsVpnStatus.connected ||
          state.status == WindowsVpnStatus.connecting;
      final stale = active && !await _hasValidSession(state.snapshotToken);
      if (_commandActive || _monitor == null) return;
      if (stale) {
        // Reconcile a restored provider session here, never inside a read.
        final result = await stopVpn();
        if (result.state != NativeVpnCommandState.success) {
          throw StateError(
            result.message ?? 'Could not stop stale Windows VPN',
          );
        }
      } else {
        await _emitWindowsStatus(state.status);
      }
    } catch (error) {
      if (_monitor != null) {
        _lastNotified = null;
        _notifyError(error);
      }
    }
  }

  Future<void> _confirm(
    WindowsVpnStatus wanted,
    WindowsVpnStatus initial,
  ) async {
    var status = initial;
    final deadline = DateTime.now().add(
      wanted == WindowsVpnStatus.connected ? startTimeout : stopTimeout,
    );
    while (true) {
      await _emitWindowsStatus(status);
      if (status == wanted) return;
      if (wanted == WindowsVpnStatus.connected &&
          status == WindowsVpnStatus.disconnected) {
        throw StateError('Windows VPN disconnected during start');
      }
      if (!DateTime.now().isBefore(deadline)) {
        throw TimeoutException('Windows VPN did not reach ${wanted.name}');
      }
      await Future<void>.delayed(confirmInterval);
      status = (await _native.getVpnStatus()).status;
    }
  }

  @override
  Future<NativeVpnCommandResult> startVpn({
    String? configYaml,
    WindowsVpnNetworkSettings? networkSettings,
    WindowsVpnPolicy policy = const WindowsVpnPolicy(
      alwaysOn: false,
      allowLocalNetwork: true,
      excludedCidrs: [],
    ),
  }) async {
    if (configYaml == null || configYaml.isEmpty || networkSettings == null) {
      return commandFailed('Windows VPN settings are missing');
    }

    _commandActive = true;
    var providerStartInvoked = false;
    var previousStopped = false;
    String? coreConfig;
    try {
      final request = await _readRequest();
      final stopped = await _native.stopVpn();
      await _confirm(WindowsVpnStatus.disconnected, stopped.status);
      if ((await _coreProcess.findPids()).isNotEmpty) {
        throw StateError('The previous Windows Core process is still running.');
      }
      previousStopped = true;
      coreConfig = await _publishCoreConfig(readRunXrayRequest(request));
      final errorFile = desktopCoreErrorFile(coreConfig);
      await errorFile.writeAsString('', flush: true);
      final backend = WindowsSessionBackend(
        processes: [
          WindowsManagedProcess(
            executableRelativePath: _coreRelativePath,
            arguments: desktopCoreRunArguments(
              dns: networkSettings.dnsIpv4Address,
              interfaceName: request.tun?.autoOutboundsInterface ?? '',
              configPath: coreConfig,
              errorFile: errorFile.path,
            ),
          ),
        ],
      );

      await clearRuntimeLogs();
      await _emitWindowsStatus(WindowsVpnStatus.connecting);
      providerStartInvoked = true;
      final state = await _native.startVpn(
        configYaml,
        networkSettings,
        policy: policy,
        sessionBackend: backend,
      );
      final token = state.snapshotToken;
      if (token == null) {
        throw const FormatException('Windows VPN start returned no token');
      }
      request.snapshotToken = token;
      await request.writeToStartFile();
      await _confirm(WindowsVpnStatus.connected, state.status);
      return commandSuccess(status: VpnStatus.connected);
    } catch (error, stackTrace) {
      ygLogger('start Windows VPN failed: $error\n$stackTrace');
      if (previousStopped) await _cleanupFailedStart(providerStartInvoked);
      return commandFailed(
        providerStartInvoked && coreConfig != null
            ? await readDesktopCoreStartError(coreConfig, error.toString())
            : error.toString(),
      );
    } finally {
      _commandActive = false;
    }
  }

  @override
  Future<NativeVpnCommandResult> stopVpn() async {
    _commandActive = true;
    try {
      await _emitWindowsStatus(WindowsVpnStatus.disconnecting);
      final state = await _native.stopVpn();
      await _confirm(WindowsVpnStatus.disconnected, state.status);
      return commandSuccess(status: VpnStatus.disconnected);
    } catch (error, stackTrace) {
      ygLogger('stop Windows VPN failed: $error\n$stackTrace');
      return commandFailed(error.toString());
    } finally {
      _commandActive = false;
    }
  }

  Future<void> _cleanupFailedStart(bool providerStartInvoked) async {
    if (!providerStartInvoked) {
      await _emitWindowsStatus(WindowsVpnStatus.disconnected);
      return;
    }
    try {
      final state = await _native.stopVpn();
      await _confirm(WindowsVpnStatus.disconnected, state.status);
    } catch (error) {
      ygLogger('failed to clean up Windows VPN start: $error');
    }
  }

  Future<bool> _hasValidSession(String? snapshotToken) async {
    if (snapshotToken == null) {
      return false;
    }
    try {
      final request = await _readRequest();
      return request.snapshotToken == snapshotToken;
    } catch (_) {
      return false;
    }
  }

  Future<String> _publishCoreConfig(LibXrayRunConfig request) async {
    final paths = await materializeRunXrayConfig(request);
    if (paths == null) throw const FormatException('xrayJson is empty');
    return paths;
  }

  Future<void> _emitWindowsStatus(WindowsVpnStatus status) async {
    final value = _status(status);
    if (value == _lastNotified) return;
    _lastNotified = value;
    await _notify(value);
  }

  static VpnStatus _status(WindowsVpnStatus status) => switch (status) {
    WindowsVpnStatus.disconnecting => VpnStatus.disconnecting,
    WindowsVpnStatus.disconnected => VpnStatus.disconnected,
    WindowsVpnStatus.connecting => VpnStatus.connecting,
    WindowsVpnStatus.connected => VpnStatus.connected,
  };
}
