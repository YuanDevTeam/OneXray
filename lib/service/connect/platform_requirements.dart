import 'dart:io';

import 'package:onexray/core/ffi/linux_ffi_api.dart';
import 'package:onexray/core/ffi/windows/ffi_api.dart';
import 'package:onexray/core/proxy/host.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';

enum ConnectionPlatformRequirementFailure {
  outboundInterfaceRequired,
  outboundInterfaceUnavailable,
}

final class ConnectionPlatformRequirementException implements Exception {
  final ConnectionPlatformRequirementFailure failure;

  const ConnectionPlatformRequirementException(this.failure);

  String get reason => switch (failure) {
    ConnectionPlatformRequirementFailure.outboundInterfaceRequired =>
      'interfaceRequired',
    ConnectionPlatformRequirementFailure.outboundInterfaceUnavailable =>
      'interfaceUnavailable',
  };
}

/// Checks the platform requirements needed by every normal VPN session.
final class ConnectionPlatformRequirements {
  final ConnectionPlatform platform;
  final Future<Set<String>> Function() _interfaceNames;

  ConnectionPlatformRequirements({
    ConnectionPlatform? platform,
    Future<Set<String>> Function()? interfaceNames,
  }) : platform = platform ?? connectionPlatform,
       _interfaceNames = interfaceNames ?? _readInterfaceNames;

  static Future<Set<String>> _readInterfaceNames() async => {
    for (final value in await queryXrayOutboundInterfaceList()) value.name,
  };

  Future<void> ensureOutboundInterface(
    String name, {
    bool proxyMode = false,
  }) async {
    if (proxyMode) return;
    if (platform != ConnectionPlatform.windows &&
        platform != ConnectionPlatform.linux) {
      return;
    }
    if (name.trim().isEmpty || name.contains('\u0000')) {
      throw const ConnectionPlatformRequirementException(
        ConnectionPlatformRequirementFailure.outboundInterfaceRequired,
      );
    }
    if (!(await _interfaceNames()).contains(name)) {
      throw const ConnectionPlatformRequirementException(
        ConnectionPlatformRequirementFailure.outboundInterfaceUnavailable,
      );
    }
  }

  Future<void> ensureRuntime({bool proxyMode = false}) async {
    if (proxyMode) {
      // Availability is checked by the proxy host without invoking the old
      // TUN/package-provider/capabilities startup path.
      await DesktopProxyHost().ensureRuntime();
      return;
    }
    if (platform == ConnectionPlatform.windows) {
      await WindowsFfiApi().ensureRuntime();
      return;
    }
    if (platform != ConnectionPlatform.linux) return;

    final file = File(LinuxFfiApi().corePath);
    if (!await file.exists() ||
        ((await file.stat()).mode & 0x49) == 0 ||
        !await File('/dev/net/tun').exists()) {
      throw StateError('OneXrayCore / TUN is unavailable');
    }
    final status = await File('/proc/self/status').readAsString();
    if (RegExp(r'^Uid:\s+0\s+0\s+0\s+0$', multiLine: true).hasMatch(status)) {
      return;
    }
    final result = await Process.run('getcap', [
      file.path,
    ]).timeout(const Duration(seconds: 5));
    final capabilities = '${result.stdout}';
    if (result.exitCode != 0 ||
        !capabilities.contains('cap_net_admin') ||
        !capabilities.contains('cap_net_raw') ||
        !RegExp(r'=[eip]*e[eip]*\s*$').hasMatch(capabilities)) {
      throw StateError('cap_net_admin / cap_net_raw are unavailable');
    }
  }
}
