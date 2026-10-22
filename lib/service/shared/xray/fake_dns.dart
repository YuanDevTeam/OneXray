import 'package:onexray/core/model/xray_json.dart';

/// Keeps FakeDNS servers, pools and managed inbound recovery in sync.
abstract final class FakeDns {
  static const address = 'fakedns';
  static const tag = 'app-dns-fake';

  static bool isAddress(Object? value) =>
      value is String && value.toLowerCase() == address;

  static bool usesServer(XrayDns? dns) =>
      dns?.servers?.any((server) => isAddress(server.address)) ?? false;

  static List<XrayFakeDns>? poolsFor(XrayDns? dns) => usesServer(dns)
      ? [
          // Do not allocate the tunnel's own 198.18.0.1 / fc00::1 addresses.
          XrayFakeDns(ipPool: '198.19.0.0/16', poolSize: 32768),
          XrayFakeDns(ipPool: '2001:2::/48', poolSize: 32768),
        ]
      : null;

  static bool usedByRaw(Map<String, dynamic> config) {
    if (config.entries.any(
      (entry) => entry.key.toLowerCase() == address && entry.value != null,
    )) {
      return true;
    }
    final dns = config['dns'];
    final servers = dns is Map ? dns['servers'] : null;
    return servers is List &&
        servers.any(
          (server) => isAddress(server is Map ? server['address'] : server),
        );
  }
}
