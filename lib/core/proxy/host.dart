import 'dart:async';
import 'dart:io';

import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/proxy/core_session.dart';
import 'package:onexray/core/proxy/gnome_proxy.dart';
import 'package:onexray/core/proxy/journal.dart';
import 'package:onexray/core/proxy/system_proxy.dart';
import 'package:onexray/core/proxy/windows_proxy.dart';
import 'package:path_provider/path_provider.dart';

export 'package:onexray/core/proxy/system_proxy.dart'
    show DesktopSystemProxyCapability;

/// Owns a local Core and, optionally, the current user's OS proxy write set.
/// Runtime mode selection/compilation remains in Services, not in this host.
final class DesktopProxyHost {
  static final _instance = DesktopProxyHost._();
  factory DesktopProxyHost() => _instance;
  DesktopProxyHost._()
    : _coreOverride = null,
      _adapterOverride = null,
      _storeOverride = null,
      _notifyOverride = null,
      _readyOverride = null,
      _portCheckOverride = null,
      _desktopOverride = null,
      _systemProxyPollInterval = const Duration(seconds: 2);

  DesktopProxyHost.forTesting({
    required ProxyCoreSession core,
    required SystemProxyAdapter adapter,
    required ProxyJournalStore store,
    Future<void> Function(VpnStatus)? notify,
    Future<void> Function(int, Future<bool> Function())? waitReady,
    Future<void> Function(int)? checkPort,
    bool desktop = true,
    Duration systemProxyPollInterval = const Duration(seconds: 2),
  }) : _coreOverride = core,
       _adapterOverride = adapter,
       _storeOverride = store,
       _notifyOverride = notify,
       _readyOverride = waitReady,
       _portCheckOverride = checkPort,
       _desktopOverride = desktop,
       // Keep the testing argument public and its implementation detail private.
       // ignore: prefer_initializing_formals
       _systemProxyPollInterval = systemProxyPollInterval;

  final ProxyCoreSession? _coreOverride;
  final SystemProxyAdapter? _adapterOverride;
  final ProxyJournalStore? _storeOverride;
  final Future<void> Function(VpnStatus)? _notifyOverride;
  final Future<void> Function(int, Future<bool> Function())? _readyOverride;
  final Future<void> Function(int)? _portCheckOverride;
  final bool? _desktopOverride;
  final Duration _systemProxyPollInterval;
  bool get _desktop =>
      _desktopOverride ??
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  static Future<String> _directory() async =>
      (await getApplicationSupportDirectory()).path;
  late final _core =
      _coreOverride ??
      (Platform.isMacOS
          ? MacProxyCoreSession()
          : ProcessProxyCoreSession(directory: _directory));
  late final _adapter =
      _adapterOverride ??
      (Platform.isWindows
          ? WindowsSystemProxyAdapter()
          : Platform.isLinux
          ? GnomeSystemProxyAdapter()
          : const UnsupportedSystemProxyAdapter(
              'Configure the HTTP/SOCKS endpoint in macOS or your app.',
            ));
  late final _store = _storeOverride ?? FileProxyJournalStore(_directory);
  Future<void> _tail = Future.value();
  bool _loaded = false;
  bool _watching = false;
  Map<String, dynamic>? _record;
  String? _recoveryError;
  bool _systemProxyActive = false;
  Timer? _settingsMonitor;
  bool _settingsReadQueued = false;
  int _settingsGeneration = 0;

  bool get systemProxyActive => _systemProxyActive;

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<DesktopSystemProxyCapability> capability() async {
    if (!_desktop) {
      return const DesktopSystemProxyCapability(
        supported: false,
        reason: 'Local proxy mode is available on desktop.',
      );
    }
    return _adapter.capability();
  }

  Future<void> ensureRuntime() async {
    if (!_desktop) {
      throw UnsupportedError('Local proxy mode is available on desktop.');
    }
    await _core.ensureRuntime();
  }

  /// Called on ordinary App startup too, even if the saved mode is now TUN.
  Future<void> recover() async {
    if (!_desktop) return;
    await _serial(_load);
  }

  Future<void> _load() async {
    if (_loaded) return;
    await _store.lock();
    _record = await _store.read();
    if (_record != null) {
      final record = _record!;
      if (record['version'] != 1 ||
          record['automatic'] is! bool ||
          record['port'] is! int ||
          (record['port'] as int) < 1024 ||
          (record['port'] as int) > 65535 ||
          record['adapter'] is! String ||
          !{'prepared', 'applying', 'active'}.contains(record['phase'])) {
        throw const FormatException('Invalid local proxy recovery record');
      }
      await _restoreSettings();
      final identity = _record!['core'];
      if (identity != null && identity is! Map) {
        throw const FormatException('Invalid proxy Core recovery identity');
      }
      await _core.recover(
        identity == null ? null : Map<String, dynamic>.from(identity),
      );
      await _clear();
    }
    _loaded = true;
    if (!_watching) {
      _watching = true;
      _core.exits.listen((_) {
        unawaited(
          _serial(() async {
            var notify = false;
            try {
              // A delayed exit from an older generation must not retire a new
              // Core which has since completed a serialized start.
              if (await _core.isRunning()) return;
              notify = true;
              if (_record != null) await _finishEnded();
            } catch (error) {
              notify = true;
              _recoveryError = failureDetails(error);
            } finally {
              // The coordinator re-reads this host, including restoration errors.
              try {
                if (notify) {
                  await (_notifyOverride ?? AppFlutterApi().vpnStatusChanged)(
                    VpnStatus.disconnected,
                  );
                }
              } catch (_) {
                // State/recovery remain queryable even if an observer was disposed.
              }
            }
          }),
        );
      });
    }
  }

  Future<NativeVpnCommandResult> start(
    StartVpnRequest request, {
    required bool autoSetSystemProxy,
  }) => _serial(() async {
    if (!_desktop) return _failed('Local proxy mode is available on desktop.');
    var startedAttempt = false;
    try {
      await _load();
      if (_record != null || await _core.isRunning()) {
        return _failed('The previous local proxy session must stop first.');
      }
      final port = int.tryParse(request.socksPort ?? '');
      if (port == null ||
          port < 1024 ||
          port > 65535 ||
          request.metricsPort == '$port') {
        throw const FormatException('Invalid or conflicting local proxy port');
      }
      await ensureRuntime();
      SystemProxySnapshot? before;
      SystemProxySnapshot? expected;
      if (autoSetSystemProxy) {
        final available = await capability();
        if (!available.supported) {
          throw StateError(
            available.reason ?? 'Automatic system proxy is unavailable.',
          );
        }
        before = await _adapter.read();
        expected = _adapter.forEndpoint(before, port);
      }
      await (_portCheckOverride ?? _checkPort)(port);
      startedAttempt = true;
      await _core.start(request);
      await _save({
        'version': 1,
        'port': port,
        'automatic': autoSetSystemProxy,
        'adapter': _adapter.id,
        'phase': 'prepared',
        'core': _core.identity,
        'before': ?before,
        'expected': ?expected,
      });
      await (_readyOverride ?? waitForProxyListener)(port, _core.isRunning);
      if (autoSetSystemProxy) {
        if (!proxyValuesEqual(await _adapter.read(), before)) {
          throw StateError('System proxy settings changed during startup.');
        }
        await _save({..._record!, 'phase': 'applying'});
        await _adapter.write(expected!);
        if (!proxyValuesEqual(await _adapter.read(), expected)) {
          throw StateError('System proxy settings could not be confirmed.');
        }
      }
      await _save({..._record!, 'phase': 'active'});
      if (!await _core.isRunning()) {
        throw StateError('The local proxy Core exited during startup.');
      }
      _systemProxyActive = autoSetSystemProxy;
      _recoveryError = null;
      if (autoSetSystemProxy) _monitorSettings();
      return _success(VpnStatus.connected);
    } catch (error) {
      final original = failureDetails(error);
      // A failed lock/recovery/capability/preflight owns no new Core or journal.
      if (!startedAttempt) return _failed(original);
      try {
        if (_record != null) await _restoreSettings();
        await _core.stop();
        await _clear();
      } catch (rollbackError) {
        _recoveryError = failureDetails(rollbackError);
        return _failed('$original\n${_recoveryError!}');
      }
      return _failed(original);
    }
  });

  Future<NativeVpnCommandResult> stop() {
    _cancelSettingsMonitor();
    return _serial(() async {
      if (!_desktop) return _success(VpnStatus.disconnected);
      try {
        await _load();
        await _restoreSettings(); // Never close a listener before owned settings.
        await _core.stop();
        await _clear();
        return _success(VpnStatus.disconnected);
      } catch (error) {
        _recoveryError = failureDetails(error);
        return _failed(_recoveryError!);
      }
    });
  }

  Future<NativeVpnCommandResult> readStatus() => _serial(() async {
    if (!_desktop) return _success(VpnStatus.disconnected);
    try {
      await _load();
      final running = await _core.isRunning();
      if (!running && _record != null) await _finishEnded();
      _systemProxyActive =
          running &&
          _record?['automatic'] == true &&
          proxyValuesEqual(await _adapter.read(), _record!['expected']);
      if (_recoveryError != null) return _failed(_recoveryError!);
      return _success(running ? VpnStatus.connected : VpnStatus.disconnected);
    } catch (error) {
      _systemProxyActive = false;
      return _failed(failureDetails(error));
    }
  });

  Future<void> _finishEnded() async {
    try {
      await _restoreSettings();
      await _core.stop();
      await _clear();
    } catch (error) {
      _recoveryError = failureDetails(error);
      rethrow;
    }
  }

  /// Only the OS adapter is read here. Core/VPN state and traffic are never
  /// polled; a changed write set triggers the existing coordinator event path.
  void _monitorSettings() {
    _cancelSettingsMonitor();
    final generation = _settingsGeneration;
    _settingsMonitor = Timer.periodic(_systemProxyPollInterval, (_) {
      if (_settingsReadQueued) return;
      _settingsReadQueued = true;
      unawaited(
        _serial(() async {
          if (generation != _settingsGeneration ||
              _record?['automatic'] != true ||
              _record?['phase'] != 'active') {
            return;
          }
          var active = false;
          try {
            active = proxyValuesEqual(
              await _adapter.read(),
              _record!['expected'],
            );
          } catch (_) {
            // An unavailable OS backend is not a confirmed automatic proxy.
          }
          if (generation != _settingsGeneration ||
              active == _systemProxyActive) {
            return;
          }
          _systemProxyActive = active;
          try {
            await (_notifyOverride ?? AppFlutterApi().vpnStatusChanged)(
              VpnStatus.connected,
            );
          } catch (_) {
            // The next explicit read still sees the actual automatic state.
          }
        }).whenComplete(() {
          _settingsReadQueued = false;
        }),
      );
    });
  }

  void _cancelSettingsMonitor() {
    _settingsGeneration++;
    _settingsMonitor?.cancel();
    _settingsMonitor = null;
  }

  Future<void> _save(Map<String, dynamic> record) async {
    await _store.write(record);
    _record = record;
  }

  Future<void> _clear() async {
    _cancelSettingsMonitor();
    await _store.clear();
    _record = null;
    _recoveryError = null;
    _systemProxyActive = false;
  }

  Future<void> _restoreSettings() async {
    _cancelSettingsMonitor();
    _systemProxyActive = false;
    final record = _record;
    if (record == null || record['automatic'] != true) return;
    if (record['adapter'] != _adapter.id ||
        record['port'] is! int ||
        record['before'] is! Map ||
        record['expected'] is! Map) {
      throw const FormatException(
        'The system proxy recovery record does not match this desktop.',
      );
    }
    final before = Map<String, dynamic>.from(record['before'] as Map);
    final expected = Map<String, dynamic>.from(record['expected'] as Map);
    final current = await _adapter.read();
    if (_adapter.restorationMatches(current, before)) return;
    if (record['phase'] == 'prepared') {
      // No system write was attempted. Preserve all external changes.
      if (_adapter.referencesEndpoint(current, record['port'] as int)) {
        throw StateError(
          'System proxy settings changed and still reference this local proxy. Restore them before stopping.',
        );
      }
      return;
    }
    final owned =
        proxyValuesEqual(current, expected) ||
        (record['phase'] == 'applying' &&
            proxyValuesAreBeforeOrExpected(current, before, expected));
    if (owned) {
      await _adapter.write(before);
      if (!_adapter.restorationMatches(await _adapter.read(), before)) {
        throw StateError(
          'Unable to confirm restored system proxy settings. The local proxy remains available.',
        );
      }
      return;
    }
    if (_adapter.referencesEndpoint(current, record['port'] as int)) {
      throw StateError(
        'System proxy settings were changed externally and still reference this local proxy. Restore them before stopping.',
      );
    }
    // The user/another app selected another endpoint/PAC. Leave it untouched.
  }

  static Future<void> _checkPort(int port) async {
    final socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    await socket.close();
    // This only rejects an already occupied port; Core bind/handshake is final.
  }

  static NativeVpnCommandResult _success(VpnStatus status) =>
      NativeVpnCommandResult(
        state: NativeVpnCommandState.success,
        status: status,
        permission: PlatformPermissionResult(
          kind: PlatformPermissionKind.none,
          state: PlatformPermissionState.notRequired,
        ),
      );
  static NativeVpnCommandResult _failed(String message) =>
      NativeVpnCommandResult(
        state: NativeVpnCommandState.failed,
        message: message,
        permission: PlatformPermissionResult(
          kind: PlatformPermissionKind.none,
          state: PlatformPermissionState.notRequired,
        ),
      );
}
