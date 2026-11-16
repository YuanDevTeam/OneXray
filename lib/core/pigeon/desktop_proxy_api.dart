import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/platform.dart';

/// macOS owns a signed child runtime; libXray invocations stay in the Runner.
final class DesktopProxyApi {
  final BridgeDesktopProxyApi _api = BridgeDesktopProxyApi();

  void _requireMacOS() {
    if (!AppPlatform.isMacOS) {
      throw UnsupportedError('The Apple proxy helper is available on macOS');
    }
  }

  Future<NativeVpnCommandResult> start(String requestJson) {
    _requireMacOS();
    return _api.startProxy(requestJson);
  }

  Future<NativeVpnCommandResult> stop() {
    _requireMacOS();
    return _api.stopProxy();
  }

  Future<NativeVpnCommandResult> readStatus() {
    _requireMacOS();
    return _api.readProxyStatus();
  }
}
