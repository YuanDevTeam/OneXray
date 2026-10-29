import 'dart:io';

import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/dialing.dart';
import 'package:onexray/service/shared/xray/fragment.dart';

/// Compiles the device's server dialing preference into managed runtime maps.
abstract final class ManagedServerDialing {
  static const dnsTag = 'app-dns-bootstrap';

  /// [outbounds] must already be runtime copies. Intermediate proxy hops keep
  /// their domains, except WireGuard peers which Core always resolves locally.
  static List<String> apply({
    required List<Map<String, dynamic>> outbounds,
    required EffectiveServerDialing settings,
    String? interfaceName,
  }) {
    final domains = <String>{};
    final fragment = outbounds.where(XrayFragment.matches).firstOrNull;
    // A Fragment helper can serve both TCP and WireGuard UDP entries. Keep
    // its TCP racing capability independent of their traversal order.
    final managedStreams = <Map<String, dynamic>, bool>{};

    void configure(Map<String, dynamic> stream, bool supportsHappyEyeballs) {
      if (!settings.enabled) {
        _map(stream['sockopt'])?.remove('happyEyeballs');
        return;
      }
      final sockopt = _object(stream, 'sockopt');
      if (sockopt == null) return;
      sockopt['domainStrategy'] = settings.domainStrategy;
      if (settings.happyEyeballs && supportsHappyEyeballs) {
        sockopt['happyEyeballs'] = {'tryDelayMs': 250};
      } else {
        sockopt.remove('happyEyeballs');
      }
      if (interfaceName != null) sockopt['interface'] = interfaceName;
    }

    void collect(List<String> addresses) {
      if (!settings.enabled) return;
      for (final address in addresses) {
        final domain = _domain(address);
        if (domain != null) domains.add(domain);
      }
    }

    void route(
      Map<String, dynamic> stream,
      List<String> addresses, {
      bool supportsHappyEyeballs = true,
    }) {
      if (addresses.isEmpty) return;
      final sockopt = _map(stream['sockopt']);
      final dialer = sockopt?['dialerProxy'];
      var physical = stream;
      if (dialer is String && dialer.isNotEmpty) {
        if (fragment == null || dialer != XrayFragment.tag) return;
        final helper = settings.enabled
            ? _object(fragment, 'streamSettings')
            : _map(fragment['streamSettings']);
        if (helper == null) return;
        physical = helper;
        final helperDialer = _map(physical['sockopt'])?['dialerProxy'];
        if (helperDialer is String && helperDialer.isNotEmpty) return;
        // Core migrates these freedom aliases over sockopt.domainStrategy;
        // the explicit managed preference must own the final physical dial.
        if (settings.enabled) {
          final legacy = _map(fragment['settings']);
          legacy?.remove('domainStrategy');
          legacy?.remove('targetStrategy');
        }
      }
      managedStreams[physical] =
          supportsHappyEyeballs || managedStreams[physical] == true;
      collect(addresses);
    }

    for (final outbound in outbounds) {
      if (const {
        'freedom',
        'blackhole',
        'loopback',
        'dns',
      }.contains(outbound['protocol'])) {
        continue;
      }
      var addresses = _serverAddresses(outbound);
      var stream = _map(outbound['streamSettings']);
      if (stream == null && addresses.isNotEmpty && settings.enabled) {
        stream = _object(outbound, 'streamSettings');
      }
      if (stream == null) continue;
      if (outbound['protocol'] == 'wireguard') {
        // WireGuard resolves peers locally with its own socket strategy,
        // even before sending UDP through a dialerProxy. It cannot TCP-race.
        managedStreams[stream] = false;
        collect(addresses);
        route(stream, addresses, supportsHappyEyeballs: false);
        continue;
      }
      final streamAddress = stream['address'];
      if (_network(stream) == 'xdrive') {
        if (streamAddress is String && streamAddress.isNotEmpty) {
          // Explicit fronting overrides the storage service's endpoint.
          addresses = [streamAddress];
        } else {
          final xdrive = _map(stream['xdriveSettings']);
          if (xdrive != null && xdrive['service'] == 's3') {
            addresses = _s3Addresses(xdrive);
          }
        }
      }
      route(stream, addresses);

      final download = _downloadSettings(stream);
      if (download == null) continue;
      final downloadAddress = download['address'];
      if (downloadAddress is! String || downloadAddress.isEmpty) continue;
      // Core only shares parent sockopt with downloadSettings when penetrate
      // is true. Otherwise the independent stream owns its routing/socket.
      final penetrates = _map(stream['sockopt'])?['penetrate'] == true;
      route(penetrates ? stream : download, [downloadAddress]);
    }
    for (final entry in managedStreams.entries) {
      configure(entry.key, entry.value);
    }
    return domains.toList();
  }

  /// Exact endpoint rules stop at the final bootstrap resolver, keeping both
  /// physical DNS transports outside the ordinary proxy/FakeDNS fallback.
  static List<XrayDnsServer> bootstrapServers({
    required List<String> domains,
    required String ipv4Address,
    required String ipv6Address,
    required bool ipv6,
  }) {
    if (domains.isEmpty) return const [];
    final rules = [for (final domain in domains.toSet()) 'full:$domain'];
    final addresses = [ipv4Address, if (ipv6) ipv6Address];
    return [
      for (final (index, address) in addresses.indexed)
        XrayDnsServer(
          address: address,
          tag: dnsTag,
          domains: List.of(rules),
          skipFallback: true,
          finalQuery: index == addresses.length - 1 ? true : null,
          queryStrategy: ipv6 ? 'UseIP' : 'UseIPv4',
        ),
    ];
  }

  static List<String> _serverAddresses(Map<String, dynamic> outbound) {
    final settings = _map(outbound['settings']);
    if (settings == null) return [];
    if (outbound['protocol'] == 'wireguard') {
      return [
        if (settings['peers'] case List peers)
          for (final peer in peers)
            if (_map(peer)?['endpoint'] case String endpoint)
              if (Uri.tryParse('//$endpoint')?.host case String host)
                if (host.isNotEmpty) host,
      ];
    }
    final address = settings['address'];
    if (address is String && address.isNotEmpty) return [address];
    return [
      for (final field in const ['vnext', 'servers'])
        if (settings[field] case List servers)
          for (final server in servers)
            if (_map(server)?['address'] case String address)
              if (address.isNotEmpty) address,
    ];
  }

  static Map<String, dynamic>? _downloadSettings(Map<String, dynamic> stream) {
    final network = _network(stream);
    if (network != 'xhttp' && network != 'splithttp') return null;
    final xhttp =
        _map(stream['xhttpSettings']) ?? _map(stream['splithttpSettings']);
    if (xhttp == null) return null;
    // Core replaces the XHTTP object with extra, preserving only host/path/
    // mode from the outer object. An outer downloadSettings is then inactive.
    final effective = xhttp['extra'] == null ? xhttp : _map(xhttp['extra']);
    return _map(effective?['downloadSettings']);
  }

  /// S3 dials its HTTP endpoint, not the VLESS protocol's logical address.
  /// Core owns validation; only extract the host for its existing DNS policy.
  static List<String> _s3Addresses(Map<String, dynamic> xdrive) {
    final s3 = _map(xdrive['s3']);
    final endpoint = s3?['endpoint'];
    final host = endpoint is String ? Uri.tryParse(endpoint)?.host : null;
    if (host == null || host.isEmpty) return [];
    if (s3?['pathStyle'] != false) return [host];
    final bucket = s3?['bucket'];
    return bucket is String ? ['$bucket.$host'] : [];
  }

  static String? _domain(String address) {
    var value = address.trim();
    if (value.startsWith('[') && value.endsWith(']')) {
      value = value.substring(1, value.length - 1);
    }
    if (InternetAddress.tryParse(value) != null) return null;
    if (value.endsWith('.')) value = value.substring(0, value.length - 1);
    return value.isEmpty ? null : value.toLowerCase();
  }

  static String? _network(Map<String, dynamic> stream) {
    final value = stream['method'] ?? stream['network'];
    return value is String ? value.toLowerCase() : null;
  }

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static Map<String, dynamic>? _object(
    Map<String, dynamic> parent,
    String key,
  ) {
    final value = parent[key];
    if (value == null) return parent[key] = <String, dynamic>{};
    return _map(value);
  }
}
