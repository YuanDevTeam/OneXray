// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:onexray/core/errors/failure.dart';

import 'package:onexray/core/ffi/windows/model.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/ffi/windows/tun2socks.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/pigeon/model_writer.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/traffic.dart';
import 'package:onexray/service/shared/xray/metrics/model.dart';
import 'package:path/path.dart' as p;

export 'traffic.dart' show ConnectionTraffic;

typedef InspectConnection = Future<HostConnection> Function(
  ConnectionRuntime?, {
  VpnStatus? observedStatus,
});

class HostConnection {
  final VpnStatus status;
  final ConnectionRuntime? runtime;
  final ConnectionTraffic? traffic;
  final PlatformPermissionResult? permission;
  const HostConnection(
    this.status, {
    this.runtime,
    this.traffic,
    this.permission,
  });
  bool get connected => status == VpnStatus.connected;
}

class ConnectionHostException extends AppFailure {
  final String reason;
  final PlatformPermissionResult? permission;
  const ConnectionHostException(this.reason, {this.permission, super.cause})
    : super(FailureCategory.runtime, reason);
}

/// Native status owns VPN state. Xray metrics supplies current-session counters.
class ConnectionRuntimeHost {
  final AppHostApi _host = AppHostApi();
  final String? _runDirectory;
  final Future<XrayMetricsVars> Function(int port)? _metrics;
  final Future<VpnStatus> Function()? _readStatus;
  final Future<NativeVpnCommandResult> Function(ConnectionRuntime runtime)?
  _startVpn;
  final Future<void> Function(ConnectionRuntime runtime)? _writeStartFile;
  final Future<NativeVpnCommandResult> Function()? _stopVpn;

  ConnectionRuntimeHost({
    String? runDirectory,
    Future<XrayMetricsVars> Function(int port)? readMetrics,
    Future<VpnStatus> Function()? readStatus,
    Future<NativeVpnCommandResult> Function(ConnectionRuntime runtime)?
    startVpn,
    Future<void> Function(ConnectionRuntime runtime)? writeStartFile,
    Future<NativeVpnCommandResult> Function()? stopVpn,
  }) : _runDirectory = runDirectory,
       _readStatus = readStatus,
       _startVpn = startVpn,
       _writeStartFile = writeStartFile,
       _stopVpn = stopVpn,
       _metrics = readMetrics;

  String get _directory => _runDirectory ?? VpnConstants.runDir;

  Future<
    ({VpnStatus status, PlatformPermissionResult? permission, String? message})
  >
  _status() async {
    final readStatus = _readStatus;
    if (readStatus != null) {
      return (status: await readStatus(), permission: null, message: null);
    }
    final result = await _host.readVpnStatus();
    if (result.state != NativeVpnCommandState.success ||
        result.status == null) {
      throw ConnectionHostException(
        'nativeStatusFailed',
        permission: result.permission,
        cause: result.message ?? result.permission?.message,
      );
    }
    return (
      status: result.status!,
      permission: result.permission,
      message: result.message,
    );
  }

  static Map<String, dynamic> _jsonObject(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid JSON response');
    }
    return json;
  }

  Future<ConnectionRuntime?> readRuntime() async {
    try {
      final file = File(p.join(_directory, 'start.json'));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() > 16 * 1024 * 1024) {
        return null;
      }
      return ConnectionRuntime.fromRequest(
        StartVpnRequest.fromJson(_jsonObject(await file.readAsString())),
      );
    } on Exception {
      return null;
    } on ArgumentError {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<XrayMetricsVars> _readMetrics(int port) async {
    final reader = _metrics;
    if (reader != null) return reader(port);
    try {
      return XrayMetricsVars.fromJson(
        await _httpJson(
          Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: port,
            path: '/debug/vars',
          ),
        ),
      );
    } on TypeError {
      throw const FormatException('Invalid metrics counters');
    }
  }

  static Future<Map<String, dynamic>> _httpJson(
    Uri uri, {
    int maximumBytes = 1048576,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const ConnectionHostException('runtimeMetricsUnavailable');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 3))) {
        bytes.addAll(chunk);
        if (bytes.length > maximumBytes) {
          throw const FormatException('Invalid metrics response size');
        }
      }
      return _jsonObject(utf8.decode(bytes));
    } finally {
      client.close(force: true);
    }
  }

  Future<ConnectionTraffic> query(ConnectionRuntime runtime) async {
    final port = int.tryParse(runtime.request.metricsPort ?? '');
    if (port == null || port < 1 || port > 65535) {
      throw const ConnectionHostException('runtimeMetricsUnavailable');
    }
    final metrics = await _readMetrics(port);
    if (metrics.stats == null) {
      throw const FormatException('Missing metrics stats');
    }
    // Xray creates inbound counters lazily, when the first connection arrives.
    final traffic = metrics.managedTraffic;
    final uplink = traffic.uplink;
    final downlink = traffic.downlink;
    if (uplink < 0 || downlink < 0) {
      throw const FormatException('Invalid metrics counters');
    }
    return ConnectionTraffic(
      uplink: uplink,
      downlink: downlink,
      sampledAtMs: DateTime.now().millisecondsSinceEpoch,
      observations: List.unmodifiable([
        for (final path in runtime.observationPaths)
          RuntimePathObservation.fromMetrics(
            path: path,
            report: metrics.observatory?[path.tag],
            startedAtSeconds: runtime.startedAt.millisecondsSinceEpoch ~/ 1000,
          ),
      ]),
    );
  }

  Future<HostConnection> inspect(
    ConnectionRuntime? runtime, {
    VpnStatus? observedStatus,
  }) async {
    final platform = observedStatus == null
        ? await _status()
        : (status: observedStatus, permission: null, message: null);
    return HostConnection(
      platform.status,
      runtime: platform.status == VpnStatus.disconnected ? null : runtime,
      permission: platform.permission,
    );
  }

  Future<NativeVpnCommandResult> _start(ConnectionRuntime runtime) {
    final startVpn = _startVpn;
    if (startVpn != null) return startVpn(runtime);
    final policy = runtime.configuration.policy;
    final windows =
        runtime.platform == ConnectionPlatform.windows &&
        windowsBuildMode == WindowsMode.msix;
    return _host.startVpn(
      windowsConfigYaml: windows
          ? buildWindowsTun2SocksConfig(
              runtime.request.socksPort!,
              enableIPv6: policy.ipv6Enabled,
            )
          : null,
      windowsNetworkSettings: windows
          ? WindowsVpnNetworkSettings(
              ipv4Address: PlatformPolicy.tunIpv4Address,
              ipv6Address: PlatformPolicy.tunIpv6Address,
              dnsIpv4Address: policy.dnsIpv4Address,
              dnsIpv6Address: policy.dnsIpv6Address,
            )
          : null,
      windowsPolicy: windows
          ? policy.toWindowsPolicy()
          : const WindowsVpnPolicy(
              alwaysOn: false,
              allowLocalNetwork: true,
              excludedCidrs: [],
            ),
    );
  }

  Future<HostConnection> start(
    ConnectionRuntime runtime, {
    Future<void>? cancelled,
  }) async {
    var wasCancelled = false;
    unawaited(
      cancelled?.then<void>((_) {
        wasCancelled = true;
      }),
    );
    final writeStartFile = _writeStartFile;
    if (writeStartFile != null) {
      await writeStartFile(runtime);
    } else if (_startVpn == null) {
      await runtime.request.writeToStartFile();
    }
    if (cancelled != null) {
      // Observe an already completed cancellation before submitting any native
      // command, including when an injected host needs no file preparation.
      await Future<void>.value();
      if (wasCancelled) throw const ConnectionHostException('cancelled');
    }
    // Only iOS has native admission and preparation draining for concurrent
    // Stop. Other platforms retain their serialized native-command contract.
    final submitted = _start(runtime);
    final result =
        await (cancelled == null || runtime.platform != ConnectionPlatform.ios
            ? submitted
            : Future.any([
                submitted,
                cancelled.then<NativeVpnCommandResult>(
                  (_) => throw const ConnectionHostException('cancelled'),
                ),
              ]));
    if (result.state != NativeVpnCommandState.success) {
      throw ConnectionHostException(
        result.state == NativeVpnCommandState.waitingForPlatformPermission
            ? 'permissionRequired'
            : 'startFailed',
        permission: result.permission,
        cause: result.message ?? result.permission?.message,
      );
    }
    if (result.status != VpnStatus.connected) {
      throw ConnectionHostException('startNotConfirmed', cause: result.message);
    }
    return HostConnection(
      result.status!,
      runtime: runtime,
      permission: result.permission,
    );
  }

  Future<HostConnection> stop() async {
    final result = await (_stopVpn?.call() ?? _host.stopVpn());
    if (result.state != NativeVpnCommandState.success) {
      throw ConnectionHostException('stopFailed', cause: result.message);
    }
    if (result.status != VpnStatus.disconnected) {
      throw ConnectionHostException('stopNotConfirmed', cause: result.message);
    }
    return HostConnection(result.status!, permission: result.permission);
  }
}
