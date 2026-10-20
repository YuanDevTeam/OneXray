import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/shared/xray/vpn_config.dart';

/// Projects App configurations for libXray instance construction, not startup.
/// Only disposable copies are changed; persisted and runtime JSON stay intact.
abstract final class XrayValidation {
  /// Complete configurations share portable VPN supplements with runtime.
  /// Advanced templates call [raw] directly to retain their own DNS policy.
  static String full(Map<String, dynamic> source) =>
      raw(VpnConfigAdapter.adapt(source));

  static XrayEnv _env() => XrayEnv(
    assetLocation: VpnConstants.datDir,
    certLocation: VpnConstants.datDir,
  );

  static XrayLog _log() =>
      XrayLog(access: 'none', error: 'none', logLevel: 'none', dnsLog: false);

  static String nodes(List<dynamic> outbounds) {
    // Malformed native structures still belong to libXray, not Dart validation.
    if (outbounds.any((value) => value is! Map<String, dynamic>)) {
      return JsonTool.encoder.convert({'outbounds': outbounds});
    }
    return normal(XrayJson(outbounds: outbounds.cast<Map<String, dynamic>>()));
  }

  static String normal(XrayJson config) => JsonTool.encoder.convert(
    XrayJson(
      env: _env(),
      log: _log(),
      inbounds: config.inbounds == null
          ? null
          : [
              for (final inbound in config.inbounds ?? <XrayInbound>[])
                XrayInbound(
                  tag: inbound.tag,
                  protocol: 'socks',
                  listen: '127.0.0.1',
                  port: '1080',
                  settings: {'auth': 'noauth', 'udp': true},
                  sniffing: inbound.sniffing,
                ),
            ],
      outbounds: config.outbounds?.map(_outbound).toList(),
      routing: config.routing,
      dns: config.dns,
      fakedns: config.fakedns,
      observatory: config.observatory,
    ).toJson(),
  );

  static String raw(Map<String, dynamic> source) {
    final config = JsonTool.copyMap(source);
    config.remove('geodata');
    config.remove('metrics');
    config['log'] = _log().toJson();
    // Keep the feature for user API services which may depend on it.
    config['stats'] = <String, dynamic>{};

    final inbounds = config['inbounds'];
    if (inbounds is List) {
      config['inbounds'] = [
        for (final value in inbounds)
          if (value is Map<String, dynamic> && value['tag'] == 'tunIn')
            {
              ...value,
              // Validate user sniffing without constructing a platform TUN.
              'protocol': 'socks',
              'listen': '127.0.0.1',
              'port': 1080,
              'settings': {'auth': 'noauth', 'udp': true},
            }
          else
            value,
      ];
    }
    final env = config['env'];
    if (env == null || env is Map<String, dynamic>) {
      config['env'] =
          {if (env is Map<String, dynamic>) ...env, ..._env().toJson()}
            ..removeWhere(
              (key, _) => const {'xray.tun.fd', 'XRAY_TUN_FD'}.contains(key),
            );
    }

    final policy = config['policy'];
    if (policy is Map) {
      final system = policy['system'];
      if (system is Map) {
        for (final key in const [
          'statsInboundUplink',
          'statsInboundDownlink',
          'statsOutboundUplink',
          'statsOutboundDownlink',
        ]) {
          system.remove(key);
        }
      }
      final levels = policy['levels'];
      if (levels is Map) {
        for (final level in levels.values) {
          if (level is Map) {
            level.remove('statsUserUplink');
            level.remove('statsUserDownlink');
          }
        }
      }
    }
    final dns = config['dns'];
    if (dns is Map) {
      dns.remove('queryStrategy');
      final servers = dns['servers'];
      if (servers is List) {
        for (final server in servers) {
          if (server is Map) server.remove('queryStrategy');
        }
      }
    }
    final outbounds = config['outbounds'];
    if (outbounds is List) {
      config['outbounds'] = [
        for (final value in outbounds)
          if (value is Map<String, dynamic>) _outbound(value) else value,
      ];
    }
    return JsonTool.encoder.convert(config);
  }

  static Map<String, dynamic> _outbound(Map<String, dynamic> source) {
    final outbound = JsonTool.copyMap(source);
    final stream = outbound['streamSettings'];
    if (stream is Map) {
      final sockopt = stream['sockopt'];
      if (sockopt is Map) {
        sockopt.remove('interface');
        if (sockopt.isEmpty) stream.remove('sockopt');
      }
      if (stream.isEmpty) outbound.remove('streamSettings');
    }
    return outbound;
  }
}
