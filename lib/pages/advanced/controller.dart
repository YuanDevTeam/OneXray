import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/shared/app_lifecycle.dart';

class AdvancedPageState {
  final PlatformPolicy? policy;
  final ConnectionView runtime;
  final String xrayVersion;
  final String uptime;
  final bool failed;

  const AdvancedPageState({
    this.policy,
    this.runtime = const ConnectionView(),
    this.xrayVersion = '—',
    this.uptime = '—',
    this.failed = false,
  });
}

/// Runtime facts shared by Xray pages; platform edits use their own draft.
class AdvancedController extends PageCubit<AdvancedPageState>
    with WidgetsBindingObserver {
  final ConnectionCoordinator coordinator;
  StreamSubscription<ConnectionConfigData>? _subscription;
  PlatformPolicy? _policy;
  String _version = '—';
  bool _failed = false;
  bool _visible = false;
  bool _appVisible = true;
  Timer? _uptimeTimer;
  final DateTime Function() _now;

  AdvancedController({
    ConnectionCoordinator? coordinator,
    DateTime Function()? now,
  }) : coordinator = coordinator ?? ConnectionCoordinator.instance,
       _now = now ?? DateTime.now,
       super(const AdvancedPageState()) {
    WidgetsBinding.instance.addObserver(this);
    _appVisible = isAppVisible(WidgetsBinding.instance.lifecycleState);
    this.coordinator.state.addListener(_publish);
    reload();
    _readVersion();
  }

  void setVisible(bool visible) {
    if (!isPageActive || _visible == visible) return;
    _visible = visible;
    _publish();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = isAppVisible(state);
    if (_appVisible == visible) return;
    _appVisible = visible;
    _publish();
  }

  Future<void> reload() async {
    await _subscription?.cancel();
    if (!isPageActive) return;
    _subscription = coordinator.db.connectionConfigDao.watch().listen(
      (row) {
        try {
          _policy = ConnectionConfiguration.fromJson(
            jsonDecode(row.configurationJson) as Map<String, dynamic>,
          ).policy;
          _failed = false;
        } catch (_) {
          _policy = null;
          _failed = true;
        }
        _publish();
      },
      onError: (Object _) {
        _policy = null;
        _failed = true;
        _publish();
      },
    );
  }

  Future<void> _readVersion() async {
    try {
      final version = await AppHostApi().xrayVersion();
      if (version.isNotEmpty) _version = version;
    } catch (_) {
      // Version lookup is optional; never display a fabricated version.
    }
    _publish();
  }

  void _publish() {
    if (!isPageActive) return;
    final runtime = coordinator.state.value;
    final started = runtime.runtime?.startedAt.millisecondsSinceEpoch;
    var uptime = '—';
    if (runtime.phase == ConnectionPhase.connected &&
        started != null &&
        started > 0) {
      final seconds = ((_now().millisecondsSinceEpoch - started) ~/ 1000).clamp(
        0,
        1 << 53,
      );
      uptime =
          '${seconds ~/ 3600}:'
          '${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:'
          '${(seconds % 60).toString().padLeft(2, '0')}';
    }
    emit(
      AdvancedPageState(
        policy: _policy,
        runtime: runtime,
        xrayVersion: _version,
        uptime: uptime,
        failed: _failed,
      ),
    );
    if (_visible && _appVisible && uptime != '—') {
      _uptimeTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _publish(),
      );
    } else {
      _uptimeTimer?.cancel();
      _uptimeTimer = null;
    }
  }

  String statusLabel(AppLocalizations l10n) => switch (state.runtime.phase) {
    ConnectionPhase.disconnected => l10n.prototypeDisconnected,
    ConnectionPhase.preparing ||
    ConnectionPhase.connecting => l10n.prototypeConnecting,
    ConnectionPhase.connected => l10n.prototypeConnected,
    ConnectionPhase.disconnecting => l10n.prototypeDisconnecting,
    ConnectionPhase.failed => l10n.prototypeConnectionFailed,
  };

  @override
  Future<void> disposePageResources() async {
    WidgetsBinding.instance.removeObserver(this);
    _uptimeTimer?.cancel();
    coordinator.state.removeListener(_publish);
    await _subscription?.cancel();
  }
}
