import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/connect/failure.dart';
import 'package:onexray/service/connect/preparation.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/shared/app_lifecycle.dart';
import 'package:onexray/service/shared/command_serial_executor.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';

enum ConnectionPhase {
  disconnected,
  preparing,
  connecting,
  connected,
  disconnecting,
  failed,
}

class ConnectionView {
  final ConnectionPhase phase;
  final ConnectionRuntime? runtime;
  final ConnectionTraffic? traffic;
  final bool metricsAvailable;
  final int uploadSpeed;
  final int downloadSpeed;
  final String? issue;

  /// The command's cause (including resolver counts), kept only in memory.
  final Object? error;
  final PlatformPermissionResult? permission;
  const ConnectionView({
    this.phase = ConnectionPhase.disconnected,
    this.runtime,
    this.traffic,
    this.metricsAvailable = false,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.issue,
    this.error,
    this.permission,
  });
  bool get busy =>
      phase != ConnectionPhase.connected &&
      phase != ConnectionPhase.disconnected &&
      phase != ConnectionPhase.failed;
  bool get canDisconnect =>
      phase == ConnectionPhase.connected ||
      (phase == ConnectionPhase.failed &&
          (runtime != null || issue == 'stopFailed'));
  bool get failed =>
      phase == ConnectionPhase.failed ||
      (issue != null && !const {'cancelled', 'selectionReset'}.contains(issue));
}

typedef PrepareConnection = Future<ConnectionRuntime> Function(
  ConnectionConfiguration,
  Future<void>,
);

/// All user/system-entry commands share one serial queue. No SQLite transaction
/// remains open while awaiting a permission prompt, a probe or a native VPN.
class ConnectionCoordinator with WidgetsBindingObserver {
  static final instance = ConnectionCoordinator();
  final AppDatabase db;
  late final PrepareConnection _prepare;
  late final Future<HostConnection> Function(ConnectionRuntime, Future<void>)
  _start;
  late final Future<HostConnection> Function() _stop;
  late final InspectConnection _inspect;
  late final Future<ConnectionTraffic> Function(ConnectionRuntime) _readTraffic;
  late final Future<ConnectionRuntime?> Function() _readRuntime;
  final Stream<VpnStatus> _statusEvents;
  final Future<void> Function() _observeStatus;
  final void Function() _disposeStatus;
  final _commands = CommandSerialExecutor();
  final state = ValueNotifier(const ConnectionView());
  Future<void>? _initializing;
  Future<void>? _connectRequested;
  StreamSubscription<VpnStatus>? _statusSubscription;
  Timer? _trafficPoll;
  bool _refreshing = false;
  bool _readingTraffic = false;
  final Set<Object> _visibleTrafficPages = {};
  bool _ready = false;
  VpnStatus? _pendingStatus;
  int _commandGeneration = 0;
  int _cancellationGeneration = 0;
  int _trafficGeneration = 0;
  bool _commandActive = false;
  Completer<void>? _cancel;
  ConnectionRuntime? _pendingRuntime;
  Set<int> _preparingNodeIds = {};
  bool _closed = false;
  bool _observingLifecycle = false;
  bool _appVisible = true;
  bool _resetSpeed = true;
  bool _failureLatched = false;

  ConnectionCoordinator({
    AppDatabase? database,
    PrepareConnection? prepare,
    Future<HostConnection> Function(ConnectionRuntime)? start,
    Future<HostConnection> Function()? stop,
    InspectConnection? inspect,
    Future<ConnectionTraffic> Function(ConnectionRuntime)? readTraffic,
    Future<ConnectionRuntime?> Function()? readRuntime,
    Stream<VpnStatus>? statusEvents,
    Future<void> Function()? observeStatus,
    void Function()? disposeStatus,
  }) : db = database ?? AppDatabase(),
       _statusEvents =
           statusEvents ?? AppFlutterApi().vpnStatusController.stream,
       _observeStatus = observeStatus ?? AppHostApi().observeVpnStatus,
       _disposeStatus = disposeStatus ?? AppHostApi().disposeVpnStatus {
    final host = ConnectionRuntimeHost();
    _start = start == null
        ? (runtime, cancelled) => host.start(runtime, cancelled: cancelled)
        : (runtime, cancelled) => Future.any([
            start(runtime),
            cancelled.then<HostConnection>(
              (_) => throw const ConnectionHostException('cancelled'),
            ),
          ]);
    _stop = stop ?? host.stop;
    _inspect = inspect ?? host.inspect;
    _readTraffic = readTraffic ?? host.query;
    _readRuntime = readRuntime ?? host.readRuntime;
    _prepare =
        prepare ??
        ((configuration, cancelled) => ConnectionPreparation(db: db).prepare(
          configuration,
          cancelled: cancelled,
          onResolved: reportResolvedNodes,
        ));
  }

  Future<ConnectionConfiguration> get configuration async =>
      ConnectionConfiguration.fromJson(
        jsonDecode((await db.connectionConfigDao.read()).configurationJson)
            as Map<String, dynamic>,
      );

  Future<ConnectionRuntime?> readCurrentRuntime() => _readRuntime();

  /// Custom preparation (node/route drafts) shares the same temporary reference
  /// protection as the default path. apply clears it on success and failure.
  void reportResolvedNodes(Set<int> ids) {
    _preparingNodeIds.addAll(ids);
  }

  Future<void> initialize({
    bool observe = true,
    bool registerReferences = true,
    Future<PlatformPermissionResult> Function()? requestPermission,
  }) {
    return _initializing ??= _commands
        .run(() async {
          if (registerReferences) {
            SubscriptionService().referenceReader = readReferences;
          }
          if (observe) {
            _statusSubscription ??= _statusEvents.listen(
              _onNativeStatus,
              onError: _onStatusError,
            );
            await _observeStatus();
          }
          var current = await _inspect(await _currentRuntime());
          // Only normal startup supplies this action; passive refreshes never
          // request permission or repeat a dismissed prompt.
          if (requestPermission != null &&
              _permissionRequired(current.permission)) {
            await requestPermission();
            current = await _inspect(await _currentRuntime());
          }
          final permission = current.permission;
          final permissionRequired = _permissionRequired(permission);
          _failureLatched = false;
          _publish(
            current,
            issue: permissionRequired ? 'permissionRequired' : null,
            permission: permissionRequired ? permission : null,
          );
          _ready = true;
          if (observe) {
            WidgetsBinding.instance.addObserver(this);
            _observingLifecycle = true;
            _appVisible = isAppVisible(WidgetsBinding.instance.lifecycleState);
            _syncTrafficSampling();
            _drainNativeStatus();
          }
        })
        .catchError((Object error, StackTrace stack) {
          unawaited(_statusSubscription?.cancel());
          _statusSubscription = null;
          _initializing = null;
          _disposeStatus();
          state.value = ConnectionView(
            phase: ConnectionPhase.failed,
            issue: connectionFailureReason(
              error,
              fallback: 'runtimeUnavailable',
            ),
            error: error,
            permission: error is ConnectionHostException
                ? error.permission
                : null,
          );
          _failureLatched = true;
          Error.throwWithStackTrace(error, stack);
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasVisible = _appVisible;
    final hadDemand = _hasTrafficDemand;
    _appVisible = isAppVisible(state);
    if (hadDemand != _hasTrafficDemand) {
      _resetSpeed = true;
      _trafficGeneration++;
      _syncTrafficSampling();
    }
    if (_appVisible &&
        (!wasVisible || state == AppLifecycleState.resumed) &&
        _ready &&
        _observingLifecycle) {
      unawaited(refresh());
    }
  }

  /// Page visibility is demand, not ownership of the VPN.
  /// Each page reports independently, including secondary connection pages.
  void setTrafficVisible(Object page, bool visible) {
    if (_closed) return;
    final hadDemand = _hasTrafficDemand;
    if (visible) {
      _visibleTrafficPages.add(page);
    } else {
      _visibleTrafficPages.remove(page);
    }
    if (hadDemand == _hasTrafficDemand) return;
    _trafficGeneration++;
    _resetSpeed = true;
    _syncTrafficSampling();
  }

  bool get _hasTrafficDemand => _appVisible && _visibleTrafficPages.isNotEmpty;

  bool get _trafficWanted =>
      _ready &&
      !_closed &&
      _hasTrafficDemand &&
      !_commandActive &&
      (_pendingStatus == null || _pendingStatus == VpnStatus.connected) &&
      state.value.phase == ConnectionPhase.connected &&
      state.value.runtime != null;

  void _syncTrafficSampling() {
    if (!_trafficWanted) {
      if (_trafficPoll != null) {
        _trafficPoll!.cancel();
        _trafficPoll = null;
        _trafficGeneration++;
        _resetSpeed = true;
      }
    } else if (_trafficPoll == null) {
      _trafficPoll = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(refreshTraffic());
      });
      unawaited(refreshTraffic());
    }
  }

  void _onNativeStatus(VpnStatus status) {
    if (_closed || status == _pendingStatus) return;
    final phase = switch (status) {
      VpnStatus.connected => ConnectionPhase.connected,
      VpnStatus.connecting => ConnectionPhase.connecting,
      VpnStatus.disconnecting => ConnectionPhase.disconnecting,
      VpnStatus.disconnected => ConnectionPhase.disconnected,
    };
    if (!_commandActive &&
        !_refreshing &&
        _pendingStatus == null &&
        state.value.phase == phase &&
        state.value.issue != 'runtimeUnavailable') {
      return;
    }
    _pendingStatus = status;
    _trafficGeneration++;
    _resetSpeed = true;
    _syncTrafficSampling();
    _drainNativeStatus();
  }

  void _drainNativeStatus() {
    if (!_ready || _closed || _commandActive || _refreshing) return;
    final status = _pendingStatus;
    if (status == null) return;
    _pendingStatus = null;
    unawaited(refresh(observedStatus: status));
  }

  void _onStatusError(Object error) {
    if (_closed || _commandActive) return;
    final old = state.value;
    state.value = ConnectionView(
      phase: old.phase,
      runtime: old.runtime,
      traffic: old.traffic,
      issue: 'runtimeUnavailable',
      error: error,
      permission: old.permission,
    );
  }

  Future<SubscriptionNodeReferences> readReferences() async {
    final stored = await configuration;
    final current = await _inspect(await _currentRuntime());
    if (current.runtime == null &&
        _pendingRuntime == null &&
        _preparingNodeIds.isEmpty &&
        current.status != VpnStatus.disconnected) {
      throw const ConnectionHostException('runtimeMetadataUnavailable');
    }
    return SubscriptionNodeReferences(
      runningIds: {
        ...?current.runtime?.nodeIds,
        ...?_pendingRuntime?.nodeIds,
        ..._preparingNodeIds,
      },
      fixedId: stored.connection.selection.kind == SelectionKind.server
          ? stored.connection.selection.id
          : null,
      finalExitId: stored.connection.smart.finalExitId,
    );
  }

  Future<ConnectionRuntime?> _currentRuntime() async =>
      await _readRuntime() ?? state.value.runtime ?? _pendingRuntime;

  Future<void> refresh({VpnStatus? observedStatus}) async {
    if (_closed || (!_appVisible && observedStatus == null)) return;
    if (_commandActive || _refreshing) {
      if (observedStatus != null) _pendingStatus = observedStatus;
      return;
    }
    _refreshing = true;
    final commandGeneration = _commandGeneration;
    try {
      final current = await _inspect(
        await _currentRuntime(),
        observedStatus: observedStatus,
      );
      if (!_commandActive &&
          !_closed &&
          commandGeneration == _commandGeneration &&
          (_pendingStatus == null || _pendingStatus == current.status)) {
        _publish(current, keepResult: true);
      }
    } catch (_) {
      if (!_commandActive &&
          !_closed &&
          commandGeneration == _commandGeneration &&
          (_pendingStatus == null || _pendingStatus == observedStatus)) {
        final old = state.value;
        if (observedStatus != null) {
          // A confirmed native state remains true even if its runtime metadata
          // or counters cannot be read. Do not lose an external disconnect.
          _publish(
            HostConnection(
              observedStatus,
              runtime: old.runtime,
              traffic: old.traffic,
            ),
            issue: old.issue ?? 'runtimeUnavailable',
            error: old.error,
            permission: old.permission,
          );
        } else {
          state.value = ConnectionView(
            phase: old.phase,
            runtime: old.runtime,
            traffic: old.traffic,
            issue: old.issue ?? 'runtimeUnavailable',
            error: old.error,
            permission: old.permission,
          );
        }
      }
    } finally {
      _refreshing = false;
      _syncTrafficSampling();
      _drainNativeStatus();
    }
  }

  /// Live sampling never queries native VPN status. A failed HTTP request is
  /// only an unavailable sample, not a disconnection or a reason to reconnect.
  Future<void> refreshTraffic() async {
    if (!_trafficWanted || _readingTraffic || _pendingStatus != null) return;
    final runtime = state.value.runtime!;
    final generation = _trafficGeneration;
    _readingTraffic = true;
    bool stillCurrent() =>
        _trafficWanted &&
        generation == _trafficGeneration &&
        state.value.runtime?.identity == runtime.identity;
    try {
      final traffic = await _readTraffic(runtime);
      if (stillCurrent()) {
        _publish(
          HostConnection(
            VpnStatus.connected,
            runtime: runtime,
            traffic: traffic,
          ),
          keepResult: true,
          liveTraffic: true,
        );
      }
    } catch (_) {
      if (stillCurrent()) {
        final old = state.value;
        _resetSpeed = true;
        state.value = ConnectionView(
          phase: old.phase,
          runtime: old.runtime,
          traffic: old.traffic,
          issue: old.issue,
          error: old.error,
          permission: old.permission,
        );
      }
    } finally {
      _readingTraffic = false;
    }
  }

  Future<void> connect() =>
      _connectRequested ??= _connectOnce(_cancellationGeneration)
          .whenComplete(() => _connectRequested = null);

  Future<void> _connectOnce(int generation) async {
    await initialize();
    _checkConnectionRequest(generation);
    if (_commandActive) return;
    final current = await _inspect(await _currentRuntime());
    _checkConnectionRequest(generation);
    if (current.status != VpnStatus.disconnected) {
      _publish(current);
      return;
    }
    final next = await configuration;
    _checkConnectionRequest(generation);
    await apply(next, connect: true);
  }

  /// UI has already confirmed a disruptive change before calling this method.
  /// Metadata/unselected-asset edits use affectsRuntime:false and still commit
  /// asset plus connection values in one transaction.
  Future<void> apply(
    ConnectionConfiguration next, {
    bool connect = false,
    bool disconnect = false,
    bool affectsRuntime = true,
    bool allowReconnect = true,
    String? expectedConfiguration,
    Future<void> Function()? writeAssets,
    Future<void> Function()? validateAssets,
    ConfigurationImportDraft? imported,
    PrepareConnection? prepare,
  }) {
    // Capture before entering the queue: Stop also invalidates requests still
    // waiting for configuration, native inspection or the Geodata file queue.
    final generation = _cancellationGeneration;
    return _run(() async {
      if (connect && disconnect) {
        throw ArgumentError('Conflicting connection action');
      }
      if (connect) _checkConnectionRequest(generation);
      final stored = await configuration;
      if (expectedConfiguration != null &&
          stored.encode() != expectedConfiguration) {
        throw const ConnectionHostException('configurationChanged');
      }
      final current = await _inspect(await _currentRuntime());
      final shouldStart =
          !disconnect && (connect || (affectsRuntime && current.connected));
      final shouldStop = disconnect && current.status != VpnStatus.disconnected;
      if (shouldStart) _checkConnectionRequest(generation);
      // Recheck after preceding commands finish: a disconnected editor may have
      // queued behind Connect without ever asking the user to reconnect.
      if ((shouldStart || shouldStop) && current.connected && !allowReconnect) {
        throw const ConnectionHostException('reconnectRequired');
      }
      Future<void> save(Future<void> Function() writeMetadata) async {
        Future<void> write() async {
          await writeMetadata();
          await writeAssets?.call();
        }

        if (!shouldStart && !shouldStop) {
          await validateAssets?.call();
          await db.connectionConfigDao.commit(
            configurationJson: next.encode(),
            writeAssets: write,
          );
          _publish(current);
          return;
        }
        if (shouldStart) _checkConnectionRequest(generation);
        final cancellation = Completer<void>();
        _cancel = cancellation;
        final old = current.connected ? current.runtime : null;
        if (current.connected && old == null) {
          throw const ConnectionHostException('runtimeMetadataUnavailable');
        }
        bool touchedHost = false;
        try {
          _preparingNodeIds = {...?old?.nodeIds};
          _checkCancelled(cancellation);
          var running = current;
          if (current.status != VpnStatus.disconnected) {
            touchedHost = true;
            state.value = ConnectionView(
              phase: ConnectionPhase.disconnecting,
              runtime: old,
              traffic: current.traffic,
            );
            running = await _stop();
            if (running.status != VpnStatus.disconnected) {
              throw const ConnectionHostException('stopNotConfirmed');
            }
          }
          _checkCancelled(cancellation);
          if (!disconnect) {
            state.value = ConnectionView(
              phase: ConnectionPhase.preparing,
              traffic: running.traffic,
            );
          }
          await validateAssets?.call();
          _checkCancelled(cancellation);
          final runtime = disconnect
              ? null
              : await (prepare ?? _prepare)(next, cancellation.future);
          _checkCancelled(cancellation);
          _pendingRuntime = runtime;
          if (runtime != null) {
            touchedHost = true;
            state.value = ConnectionView(
              phase: ConnectionPhase.connecting,
              traffic: running.traffic,
            );
            running = await _start(runtime, cancellation.future);
            _checkCancelled(cancellation);
            if (!running.connected ||
                running.runtime?.identity != runtime.identity) {
              throw const ConnectionHostException('startNotConfirmed');
            }
          }
          await db.connectionConfigDao.commit(
            configurationJson: (runtime?.configuration ?? next).encode(),
            writeAssets: () async {
              await write();
              _checkCancelled(cancellation);
            },
          );
          _publish(running, issue: runtime?.notice);
        } catch (error, stack) {
          HostConnection? failed;
          if (touchedHost) {
            try {
              failed = await _stop();
            } catch (_) {
              try {
                failed = await _inspect(await _currentRuntime());
              } catch (_) {
                // The failed state remains explicit when native state is unavailable.
              }
            }
          }
          final permission = error is ConnectionHostException
              ? error.permission
              : null;
          final issue = cancellation.isCompleted
              ? 'cancelled'
              : connectionFailureReason(error);
          if (touchedHost) {
            final status = failed?.status;
            _failureLatched = true;
            state.value = ConnectionView(
              phase: ConnectionPhase.failed,
              runtime: status == VpnStatus.disconnected
                  ? null
                  : failed?.runtime ??
                        _pendingRuntime ??
                        state.value.runtime ??
                        current.runtime,
              traffic: failed?.traffic ?? current.traffic,
              issue: issue,
              error: error,
              permission: permission,
            );
            _syncTrafficSampling();
          } else {
            _publish(
              current,
              issue: issue,
              error: error,
              permission: permission,
            );
          }
          Error.throwWithStackTrace(error, stack);
        } finally {
          _pendingRuntime = null;
          _preparingNodeIds = {};
          _cancel = null;
        }
      }

      if (!shouldStart &&
          !shouldStop &&
          writeAssets == null &&
          validateAssets == null &&
          imported == null) {
        return save(() async {});
      }
      return GeoDataService().withFiles(
        () => imported?.save(save) ?? save(() async {}),
      );
    });
  }

  void cancel() {
    _cancellationGeneration++;
    if (_cancel?.isCompleted == false) _cancel!.complete();
  }

  void _checkConnectionRequest(int generation) {
    if (generation != _cancellationGeneration) {
      throw const ConnectionHostException('cancelled');
    }
  }

  void _checkCancelled(Completer<void> cancellation) {
    if (cancellation.isCompleted) {
      throw const ConnectionHostException('cancelled');
    }
  }

  Future<void> disconnect() {
    cancel();
    return _run(_stopForMaintenance);
  }

  Future<void> pauseForDataClear() {
    cancel();
    return _commands.pause();
  }

  void resumeAfterDataClear() => _commands.resume();

  /// Clear-data already drained the connection queue. Do not take it again
  /// from inside the Geodata file queue.
  Future<void> stopForMaintenance() => _executeCommand(_stopForMaintenance);

  Future<void> _stopForMaintenance() async {
    try {
      final current = await _inspect(await _currentRuntime());
      state.value = ConnectionView(
        phase: ConnectionPhase.disconnecting,
        runtime: current.runtime,
        traffic: current.traffic,
      );
      _publish(await _stop());
    } catch (error) {
      await _publishHostFailure('stopFailed', error: error);
      rethrow;
    }
  }

  Future<void> _publishHostFailure(
    String issue, {
    required Object error,
    PlatformPermissionResult? permission,
  }) async {
    ConnectionRuntime? runtime;
    var traffic = state.value.traffic;
    try {
      final current = await _inspect(await _currentRuntime());
      traffic = current.traffic ?? traffic;
      // The actual runtime can differ from saved settings after a failed change.
      // Keep it visible and protect its nodes without committing it.
      if (current.status != VpnStatus.disconnected) {
        runtime = current.runtime;
      }
    } catch (_) {
      // Unknown host state stays an explicit failure; retry inspects it again.
    }
    state.value = ConnectionView(
      phase: ConnectionPhase.failed,
      runtime: runtime,
      traffic: traffic,
      issue: issue,
      error: error,
      permission:
          permission ??
          (error is ConnectionHostException ? error.permission : null),
    );
    _failureLatched = true;
  }

  Future<void> _run(Future<void> Function() action) => _commands.run(() async {
    await initialize();
    return _executeCommand(action);
  });

  Future<void> _executeCommand(Future<void> Function() action) async {
    _failureLatched = false;
    _commandActive = true;
    _commandGeneration++;
    _trafficGeneration++;
    _resetSpeed = true;
    _syncTrafficSampling();
    try {
      await action();
    } finally {
      _commandActive = false;
      _syncTrafficSampling();
      _drainNativeStatus();
    }
  }

  void _publish(
    HostConnection current, {
    String? issue,
    Object? error,
    PlatformPermissionResult? permission,
    bool keepResult = false,
    bool liveTraffic = false,
  }) {
    final old = state.value;
    final checkedPermission = current.permission;
    final permissionRequired = _permissionRequired(checkedPermission);
    if (permissionRequired) {
      issue = 'permissionRequired';
      error = null;
      permission = checkedPermission;
    }
    // A newer, different native notification must still be reconciled.
    if (_pendingStatus == current.status) _pendingStatus = null;
    if (keepResult) {
      // Reconciliation/sampling does not replace the last command's result.
      // A newly successful system connection resolves an old disconnected error.
      final permissionResolved =
          checkedPermission != null &&
          !permissionRequired &&
          old.issue == 'permissionRequired';
      if (!(current.connected && old.phase != ConnectionPhase.connected) &&
          !permissionResolved) {
        if (old.issue != 'runtimeUnavailable') issue ??= old.issue;
        if (issue == old.issue) error ??= old.error;
        permission ??= old.permission;
      }
    }
    final previous = old.traffic;
    final next = current.traffic;
    final sameSession =
        current.connected &&
        old.phase == ConnectionPhase.connected &&
        current.runtime != null &&
        current.runtime?.identity == old.runtime?.identity;
    final retainLive = !liveTraffic && sameSession && old.metricsAvailable;
    final display = current.connected
        ? next ?? (sameSession ? previous : null)
        : null;
    int upload = 0, download = 0;
    if (liveTraffic &&
        !_resetSpeed &&
        sameSession &&
        next != null &&
        previous != null) {
      final elapsed = next.sampledAtMs - previous.sampledAtMs;
      if (elapsed > 0 &&
          next.uplink >= previous.uplink &&
          next.downlink >= previous.downlink) {
        upload = ((next.uplink - previous.uplink) * 1000 / elapsed).round();
        download = ((next.downlink - previous.downlink) * 1000 / elapsed)
            .round();
      }
    }
    if (liveTraffic) _resetSpeed = false;
    state.value = ConnectionView(
      phase: _failureLatched
          ? ConnectionPhase.failed
          : switch (current.status) {
              VpnStatus.connected => ConnectionPhase.connected,
              VpnStatus.connecting => ConnectionPhase.connecting,
              VpnStatus.disconnecting => ConnectionPhase.disconnecting,
              VpnStatus.disconnected => ConnectionPhase.disconnected,
            },
      runtime: current.status == VpnStatus.disconnected
          ? null
          : current.runtime,
      traffic: display,
      metricsAvailable:
          current.connected && (retainLive || (liveTraffic && next != null)),
      uploadSpeed: retainLive ? old.uploadSpeed : upload,
      downloadSpeed: retainLive ? old.downloadSpeed : download,
      issue:
          issue ??
          (current.connected && current.runtime == null
              ? 'runtimeMetadataUnavailable'
              : null),
      permission: permission,
      error: error,
    );
    _syncTrafficSampling();
  }

  static bool _permissionRequired(PlatformPermissionResult? permission) =>
      permission?.state == PlatformPermissionState.notDetermined ||
      permission?.state == PlatformPermissionState.awaitingUserApproval ||
      permission?.state == PlatformPermissionState.denied;

  void clearTrafficView() {
    _commandGeneration++;
    _trafficGeneration++;
    _pendingStatus = null;
    _resetSpeed = true;
    _failureLatched = false;
    state.value = const ConnectionView();
    _syncTrafficSampling();
  }

  void dispose() {
    _closed = true;
    _visibleTrafficPages.clear();
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    cancel();
    unawaited(_statusSubscription?.cancel());
    _disposeStatus();
    _trafficPoll?.cancel();
    state.dispose();
  }
}
