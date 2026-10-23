import 'dart:async';

import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/service/launch/app_startup.dart';

/// A navigation request is accepted only by the currently ready shell. Requests
/// received during Setup, initialization or a modal are never queued.
final class MacOSSettingsMenuService {
  static final _instance = MacOSSettingsMenuService._();
  factory MacOSSettingsMenuService() => _instance;

  MacOSSettingsMenuService._()
    : _commands = AppFlutterApi().openSettingsController.stream,
      _showMainWindow = AppStartupService().showMainWindow,
      _supported = AppPlatform.isMacOS;

  MacOSSettingsMenuService.forTesting({
    required this._commands,
    required this._showMainWindow,
    this._supported = true,
  });

  final Stream<void> _commands;
  final Future<void> Function() _showMainWindow;
  final bool _supported;
  StreamSubscription<void>? _subscription;
  Object? _owner;
  bool Function()? _canNavigate;
  void Function()? _openSettings;
  bool _running = false;

  void initialize() {
    if (!_supported || _subscription != null) return;
    _subscription = _commands.listen((_) => unawaited(receive()));
  }

  void attach({
    required Object owner,
    required bool Function() canNavigate,
    required void Function() openSettings,
  }) {
    if (!_supported) return;
    _owner = owner;
    _canNavigate = canNavigate;
    _openSettings = openSettings;
  }

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _canNavigate = null;
    _openSettings = null;
  }

  Future<void> receive() async {
    if (!_supported || _running) return;
    _running = true;
    final owner = _owner;
    final openSettings = _openSettings;
    try {
      // Snapshot admission before the asynchronous window operation. Closing a
      // modal or finishing startup during it must not revive this request.
      final admitted = openSettings != null && (_canNavigate?.call() ?? false);
      await _showMainWindow();
      if (admitted &&
          identical(_owner, owner) &&
          (_canNavigate?.call() ?? false)) {
        openSettings();
      }
    } catch (error, stackTrace) {
      ygLogger('Open Settings menu failed: $error\n$stackTrace');
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async {
    _owner = null;
    _canNavigate = null;
    _openSettings = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}
