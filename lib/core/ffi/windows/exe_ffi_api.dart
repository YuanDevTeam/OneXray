import 'dart:io';

import 'package:onexray/core/ffi/base_ffi_api.dart';
import 'package:onexray/core/ffi/core_process_monitor.dart';
import 'package:onexray/core/ffi/windows/core_process.dart';
import 'package:onexray/core/ffi/windows/ffi_api.dart';
import 'package:onexray/core/ffi/windows/model.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/pigeon/model_reader.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:path/path.dart' as p;

class WindowsExeFfiApi extends WindowsFfiApi {
  final WindowsCoreProcess _process;
  final String? _filesDirectory;
  final String _corePath;
  final Future<StartVpnRequest> Function() _readRequest;
  final Future<void> Function(VpnStatus) _notify;
  final void Function(Object) _notifyError;
  late final _monitor = CoreProcessMonitor(
    discoverPids: _process.findPids,
    watchExit: _process.watchExit,
    canPublish: () => _transition == null,
    notify: _notify,
    notifyError: _notifyError,
  );
  VpnStatus? _transition;

  WindowsExeFfiApi({
    WindowsCoreProcess? process,
    this._filesDirectory,
    String? executable,
    Future<StartVpnRequest> Function()? readRequest,
    Future<void> Function(VpnStatus)? notify,
    void Function(Object)? notifyError,
  }) : _process = process ?? WindowsCoreProcess(),
       _corePath =
           executable ??
           p.join(p.dirname(Platform.resolvedExecutable), 'OneXrayCore.exe'),
       _readRequest = readRequest ?? StartVpnRequestReader.readFromStartFile,
       _notify = notify ?? AppFlutterApi().vpnStatusChanged,
       _notifyError =
           notifyError ?? AppFlutterApi().vpnStatusController.addError,
       super.base();

  @override
  Future<String> getTunFilesDir() async =>
      _filesDirectory ?? await super.getTunFilesDir();

  @override
  Future<void> ensureRuntime() =>
      checkRuntimeFiles(const ['libXray.dll', 'OneXrayCore.exe', 'wintun.dll']);

  @override
  Future<void> observeVpnStatus() => _monitor.observe();

  @override
  void disposeVpnStatus() => _monitor.dispose();

  Future<bool> _running() async => (await _monitor.readPids()).isNotEmpty;

  @override
  Future<NativeVpnCommandResult> readVpnStatus() async {
    try {
      final running = await _running();
      return commandSuccess(
        status:
            _transition ??
            (running ? VpnStatus.connected : VpnStatus.disconnected),
      );
    } catch (error, stackTrace) {
      return _failed('read', error, stackTrace);
    }
  }

  @override
  Future<bool?> cleanupStaleCore() async {
    // Discover existing named processes; legacy PID files are not consulted.
    final status = await readVpnStatus();
    return status.state == NativeVpnCommandState.success;
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
    _transition = VpnStatus.connecting;
    var launchAttempted = false;
    try {
      await _notify(VpnStatus.connecting);
      await _stop();
      final request = await _readRequest();
      final config = await materializeRunXrayConfig(
        readRunXrayRequest(request),
      );
      if (config == null) {
        throw const FormatException('xrayJson is empty');
      }
      // Create as the App user before Windows starts an elevated Core.
      final errorFile = desktopCoreErrorFile(config);
      await errorFile.writeAsString('', flush: true);
      final arguments = desktopCoreRunArguments(
        setDns: false,
        dns: request.tun?.tunDnsIPv4 ?? '',
        interfaceName: request.tun?.autoOutboundsInterface ?? '',
        configPath: config,
        errorFile: errorFile.path,
      );
      await clearRuntimeLogs();
      launchAttempted = true;
      final pid = await _process.start(_corePath, arguments);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!(await _monitor.readPids()).contains(pid)) {
        throw StateError(
          await readDesktopCoreStartError(
            config,
            'Windows Core exited during start',
          ),
        );
      }
      await _notify(VpnStatus.connected);
      return commandSuccess(status: VpnStatus.connected);
    } catch (error, stackTrace) {
      try {
        if (launchAttempted) await _stop();
        if (!await _running()) await _notify(VpnStatus.disconnected);
      } catch (cleanupError) {
        ygLogger('clean up failed Windows Core start: $cleanupError');
      }
      return _failed('start', error, stackTrace);
    } finally {
      _transition = null;
    }
  }

  @override
  Future<NativeVpnCommandResult> stopVpn() async {
    _transition = VpnStatus.disconnecting;
    try {
      await _notify(VpnStatus.disconnecting);
      await _stop();
      await _notify(VpnStatus.disconnected);
      return commandSuccess(status: VpnStatus.disconnected);
    } catch (error, stackTrace) {
      return _failed('stop', error, stackTrace);
    } finally {
      _transition = null;
    }
  }

  Future<void> _stop() async {
    // A denied stop must still retire older queries, but keep live exit watches.
    _monitor.invalidateQueries();
    await _process.stopAll();
    _monitor.clearWatches();
  }

  NativeVpnCommandResult _failed(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    ygLogger('$operation Windows Core failed: $error\n$stackTrace');
    return commandFailed(error.toString());
  }
}
