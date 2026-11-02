import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/ffi/base_ffi_api.dart';
import 'package:onexray/core/ffi/core_process_monitor.dart';
import 'package:onexray/core/ffi/desktop_core_exit.dart';
import 'package:onexray/core/ffi/linux_core_exit.dart';
import 'package:onexray/core/model/tun_json.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/pigeon/model_reader.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:path/path.dart' as p;

class LinuxFfiApi extends BaseFfiApi {
  static final LinuxFfiApi _singleton = LinuxFfiApi._internal();

  factory LinuxFfiApi() => _singleton;

  LinuxFfiApi._internal()
    : _filesDirectory = null,
      _executablePath = null,
      _runCommand = Process.run,
      _startProcess = Process.start,
      _readRequest = StartVpnRequestReader.readFromStartFile,
      _watchExit = watchLinuxCoreExit,
      _notify = AppFlutterApi().vpnStatusChanged,
      _notifyError = AppFlutterApi().vpnStatusController.addError;

  @visibleForTesting
  LinuxFfiApi.forTesting({
    required String this._filesDirectory,
    required this._executablePath,
    required this._runCommand,
    required this._watchExit,
    Future<Process> Function(String, List<String>)? startProcess,
    Future<StartVpnRequest> Function()? readRequest,
    Future<void> Function(VpnStatus)? notify,
    void Function(Object)? notifyError,
  }) : _startProcess = startProcess ?? Process.start,
       _readRequest = readRequest ?? StartVpnRequestReader.readFromStartFile,
       _notify = notify ?? AppFlutterApi().vpnStatusChanged,
       _notifyError =
           notifyError ?? AppFlutterApi().vpnStatusController.addError;

  static const _coreBin = 'OneXrayCore';
  final String? _filesDirectory;
  final String? _executablePath;
  final Future<ProcessResult> Function(String, List<String>) _runCommand;
  final Future<Process> Function(String, List<String>) _startProcess;
  final Future<StartVpnRequest> Function() _readRequest;
  final DesktopCoreExitWatch Function(int) _watchExit;
  final Future<void> Function(VpnStatus) _notify;
  final void Function(Object) _notifyError;
  late final _monitor = CoreProcessMonitor(
    discoverPids: _queryCorePids,
    watchExit: _watchProcessExit,
    canPublish: () => !_stopping && _transition == null,
    notify: _notify,
    notifyError: _notifyError,
  );
  Process? _coreProcess;
  VpnStatus? _transition;
  bool _stopping = false;
  String? _lastCoreError;

  @override
  Future<NativeVpnCommandResult> readVpnStatus() async {
    final running = await queryCoreRunning();
    if (running == null) {
      return commandFailed('Unable to read Linux Core process state.');
    }
    return commandSuccess(
      status:
          _transition ??
          (running ? VpnStatus.connected : VpnStatus.disconnected),
    );
  }

  @override
  Future<NativeVpnCommandResult> startVpn() async {
    _transition = VpnStatus.connecting;
    try {
      await _notify(VpnStatus.connecting);
      final request = await _readRequest();
      if (!await startCore(readRunXrayRequest(request), request.tun)) {
        final error = _lastCoreError;
        await stopVpn();
        return commandFailed(error);
      }
      await _notify(VpnStatus.connected);
      return commandSuccess(status: VpnStatus.connected);
    } catch (error) {
      return commandFailed(failureDetails(error));
    } finally {
      _transition = null;
    }
  }

  @override
  Future<NativeVpnCommandResult> stopVpn() async {
    _transition = VpnStatus.disconnecting;
    try {
      await _notify(VpnStatus.disconnecting);
      if (!await stopCore()) {
        return commandFailed('Unable to stop the current Core process.');
      }
      await _notify(VpnStatus.disconnected);
      return commandSuccess(status: VpnStatus.disconnected);
    } finally {
      _transition = null;
    }
  }

  @override
  Future<String> getTunFilesDir() async =>
      _filesDirectory ?? await super.getTunFilesDir();

  @override
  Future<void> observeVpnStatus() => _monitor.observe();

  @override
  void disposeVpnStatus() => _monitor.dispose();

  DesktopCoreExitWatch _watchProcessExit(int pid) {
    final process = _coreProcess;
    if (process?.pid != pid) return _watchExit(pid);
    var retired = false;
    return DesktopCoreExitWatch(
      process!.exitCode.then((_) {
        if (retired) return false;
        if (identical(_coreProcess, process)) _coreProcess = null;
        return true;
      }),
      () => retired = true,
    );
  }

  Future<bool> startCore(LibXrayRunConfig request, TunJson? tun) async {
    _lastCoreError = null;
    try {
      if (!await _stopCoreProcess()) {
        _lastCoreError = 'The previous Core process is still running.';
        return false;
      }
      final inputs = await materializeRunXrayConfig(request);
      if (inputs == null) {
        _lastCoreError = 'The Xray configuration is empty.';
        return false;
      }
      final errorFile = desktopCoreErrorFile(inputs);
      await errorFile.writeAsString('', flush: true);
      final process = await _startProcess(
        corePath,
        desktopCoreRunArguments(
          dns: tun?.tunDnsIPv4 ?? '',
          interfaceName: tun?.autoOutboundsInterface ?? '',
          configPath: inputs,
          errorFile: errorFile.path,
        ),
      );
      _coreProcess = process;
      _bindProcess(process);
      unawaited(_monitor.waitForExit(process.pid));
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!(await _monitor.readPids()).contains(process.pid)) {
        _lastCoreError = await readDesktopCoreStartError(
          inputs,
          'The Core process exited during startup.',
        );
        return false;
      }
      return true;
    } catch (error) {
      _lastCoreError = failureDetails(error);
      ygLogger('start core failed: $_lastCoreError');
      await _stopCoreProcess();
      return false;
    }
  }

  // Existing named processes are discovered directly; old PID files are unused.
  Future<bool> cleanupStaleCore() async => await queryCoreRunning() != null;

  Future<bool> stopCore() => _stopCoreProcess();

  Future<bool> _stopCoreProcess() async {
    _stopping = true;
    _monitor.clearWatches();
    try {
      var pids = await _monitor.readPids();
      for (final (signal, timeout) in const [
        ('-TERM', Duration(seconds: 3)),
        ('-KILL', Duration(seconds: 2)),
      ]) {
        if (pids.isEmpty) break;
        final exits = [for (final pid in pids) _monitor.waitForExit(pid)];
        final arguments = [signal, '-x', _coreBin];
        final result = await _runCommand('pkill', arguments);
        if (result.exitCode != 0 && result.exitCode != 1) {
          throw ProcessException(
            'pkill',
            arguments,
            'Core stop command failed',
            result.exitCode,
          );
        }
        if (result.exitCode == 0) {
          await Future.wait(exits).timeout(timeout, onTimeout: () => []);
        }
        // pkill 0 means at least one signal was sent, not that every Core exited.
        // Exit 1 can mean either no matches or a permission failure.
        pids = await _monitor.readPids();
        if (result.exitCode == 1 && pids.isNotEmpty) return false;
      }
      final stopped = pids.isEmpty;
      if (stopped) {
        _coreProcess = null;
        _monitor.clearWatches();
      }
      return stopped;
    } catch (error) {
      ygLogger('stop desktop Core failed (${error.runtimeType})');
      return false;
    } finally {
      _stopping = false;
    }
  }

  Future<bool?> queryCoreRunning() async {
    try {
      final pids = await _monitor.readPids();
      return pids.isNotEmpty;
    } catch (_) {
      return null;
    }
  }

  Future<Set<int>> _queryCorePids() async {
    // procps does the name/state scan natively. Do not match full command lines
    // or include zombies/dead processes when reporting a running VPN.
    const arguments = ['-x', '-r', 'R,S,D,T,t,I', _coreBin];
    final result = await _runCommand('pgrep', arguments);
    if (result.exitCode != 0 && result.exitCode != 1) {
      throw ProcessException(
        'pgrep',
        arguments,
        'Core process query failed',
        result.exitCode,
      );
    }
    final pids = result.exitCode == 1
        ? <int>{}
        : {
            for (final value in '${result.stdout}'.trim().split(RegExp(r'\s+')))
              int.parse(value),
          };
    if (pids.any((pid) => pid <= 0)) {
      throw const FormatException('Invalid Core PID returned by pgrep');
    }
    return pids;
  }

  String get corePath {
    if (_executablePath != null) return _executablePath;
    if (kReleaseMode) {
      return p.join(p.dirname(Platform.resolvedExecutable), _coreBin);
    }
    final homeDir = Platform.environment['HOME'];
    return homeDir == null
        ? _coreBin
        : p.join(homeDir, 'work', 'vpn', 'OneXray', _coreBin);
  }

  void _bindProcess(Process process) {
    process.stdout.listen((data) {
      if (!kReleaseMode) ygLogger(utf8.decode(data));
    });
    process.stderr.listen((data) {
      if (!kReleaseMode) ygLogger(utf8.decode(data));
    });
  }
}
