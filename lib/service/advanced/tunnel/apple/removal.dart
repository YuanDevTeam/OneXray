import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/settings.dart';

/// Removing the system VPN never changes the saved servers or tunnel policy.
class AppleVpnRemovalService {
  AppleVpnRemovalService({
    ConnectionCoordinator? coordinator,
    ConnectionPlatform? platform,
    Future<bool> Function()? useSystemExtension,
    Future<AppleVpnRemovalResult> Function()? remove,
  }) : _coordinator = coordinator ?? ConnectionCoordinator.instance,
       _platform = platform ?? connectionPlatform,
       _useSystemExtension =
           useSystemExtension ?? AppHostApi().useSystemExtension,
       _remove = remove ?? AppHostApi().removeAppleVpn;

  final ConnectionCoordinator _coordinator;
  final ConnectionPlatform _platform;
  final Future<bool> Function() _useSystemExtension;
  final Future<AppleVpnRemovalResult> Function() _remove;
  bool _removing = false;

  Future<bool> useSystemExtension() async =>
      _platform == ConnectionPlatform.macos && await _useSystemExtension();

  Future<AppleVpnRemovalResult> remove() async {
    if (_platform != ConnectionPlatform.ios &&
        _platform != ConnectionPlatform.macos) {
      throw UnsupportedError('Apple VPN removal is unavailable');
    }
    if (_removing) throw StateError('VPN removal is already in progress');
    _removing = true;
    try {
      return await _coordinator.withStoppedVpn(_remove);
    } finally {
      _removing = false;
    }
  }
}
