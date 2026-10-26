// Public list parameters keep the settings API independent of private storage.
// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/shared/ping/state.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';

/// Editable address of one DNS resolver.
final class RoutingDnsResolver {
  final String address;

  const RoutingDnsResolver({required this.address});

  factory RoutingDnsResolver.fromJson(Map<String, dynamic> json) =>
      RoutingDnsResolver(address: json['address'] as String);

  factory RoutingDnsResolver.fromXrayDnsServer(XrayDnsServer server) =>
      RoutingDnsResolver(address: server.address ?? '');

  Map<String, dynamic> toJson() => {'address': address.trim()};

  XrayDnsServer toXrayDnsServer({
    required String tag,
    List<String>? domains,
    bool? skipFallback,
    bool? finalQuery,
    String? queryStrategy,
  }) => XrayDnsServer(
    address: address.trim(),
    tag: tag,
    domains: domains,
    skipFallback: skipFallback,
    finalQuery: finalQuery,
    queryStrategy: queryStrategy,
  );

  RoutingDnsResolver copyWith({String? address}) =>
      RoutingDnsResolver(address: address ?? this.address);

  void validate() {
    if (address.trim().isEmpty) {
      throw const FormatException('DNS address is invalid');
    }
    final value = address.trim().toLowerCase();
    final uri = Uri.tryParse(value);
    final literal =
        InternetAddress.tryParse(value) ??
        (uri?.host.isNotEmpty == true
            ? InternetAddress.tryParse(uri!.host)
            : null);
    if (value == 'localhost' ||
        value == FakeDns.address ||
        (uri?.scheme.endsWith('+local') ?? false) ||
        uri?.host == 'localhost' ||
        (literal?.isLoopback ?? false)) {
      throw const FormatException(
        'Ordinary DNS resolvers must use routed remote addresses',
      );
    }
  }
}

/// Handling of DNS records outside the managed A/AAAA resolver policy.
enum NonAddressDnsPolicy { proxy, direct, empty }

/// App-owned DNS policy; runtime domain blocks are generated from routing.
final class RoutingDnsSettings {
  static const defaultAddress = '8.8.8.8';
  static const proxyTag = 'app-dns-proxy';
  static const directTag = 'app-dns-direct';
  static const defaultResolvers = [RoutingDnsResolver(address: defaultAddress)];

  final List<RoutingDnsResolver> _proxyResolvers;
  final List<RoutingDnsResolver> _directResolvers;
  final bool disableCache;
  final bool sameExitOnly;
  final NonAddressDnsPolicy nonAddressPolicy;

  const RoutingDnsSettings({
    List<RoutingDnsResolver> proxyResolvers = defaultResolvers,
    List<RoutingDnsResolver> directResolvers = defaultResolvers,
    this.disableCache = false,
    this.sameExitOnly = false,
    this.nonAddressPolicy = NonAddressDnsPolicy.proxy,
  }) : _proxyResolvers = proxyResolvers,
       _directResolvers = directResolvers;

  List<RoutingDnsResolver> get proxyResolvers =>
      List.unmodifiable(_proxyResolvers);
  List<RoutingDnsResolver> get directResolvers =>
      List.unmodifiable(_directResolvers);
  List<RoutingDnsResolver> get effectiveProxyResolvers =>
      proxyResolvers.isEmpty ? defaultResolvers : proxyResolvers;
  List<RoutingDnsResolver> get effectiveDirectResolvers =>
      directResolvers.isEmpty ? defaultResolvers : directResolvers;
  String get directAddress => effectiveDirectResolvers.first.address;

  factory RoutingDnsSettings.fromJson(Map<String, dynamic> json) =>
      RoutingDnsSettings(
        proxyResolvers: _resolvers(json['proxyResolvers']),
        directResolvers: _resolvers(json['directResolvers']),
        disableCache: json['disableCache'] as bool? ?? false,
        sameExitOnly: json['sameExitOnly'] as bool? ?? false,
        nonAddressPolicy: switch (json['nonAddressPolicy']) {
          null || 'proxy' => NonAddressDnsPolicy.proxy,
          'direct' => NonAddressDnsPolicy.direct,
          'empty' => NonAddressDnsPolicy.empty,
          _ => throw const FormatException(
            'Unsupported non-address DNS policy',
          ),
        },
      );

  factory RoutingDnsSettings.fromXrayDns(XrayDns? dns) {
    if (dns != null && (dns.servers == null || dns.servers!.isEmpty)) {
      throw const JsonDiagnostic(
        'Custom DNS requires a nonempty servers array',
        path: ['dns', 'servers'],
      );
    }
    if (dns?.disableFallback != null) {
      throw const JsonDiagnostic(
        'Custom DNS uses the same-exit fallback option',
        path: ['dns', 'disableFallback'],
      );
    }
    final servers = dns?.servers ?? const <XrayDnsServer>[];
    if (servers.where((server) => server.tag == FakeDns.tag).length > 1) {
      throw const JsonDiagnostic(
        'Custom DNS supports one FakeDNS marker',
        path: ['dns', 'servers'],
      );
    }
    for (final (index, server) in servers.indexed) {
      final path = <Object>['dns', 'servers', index];
      if (!const {proxyTag, directTag, FakeDns.tag}.contains(server.tag)) {
        throw JsonDiagnostic(
          'Unsupported Custom DNS server tag',
          path: [...path, 'tag'],
        );
      }
      if (server.address == null ||
          server.domains != null ||
          server.skipFallback != null ||
          server.queryStrategy != null ||
          server.finalQuery != null) {
        throw JsonDiagnostic(
          'Custom DNS servers cannot contain runtime matching fields',
          path: path,
        );
      }
      if (server.tag == FakeDns.tag) {
        if (!FakeDns.isAddress(server.address)) {
          throw JsonDiagnostic(
            'Custom FakeDNS marker must contain only tag and address',
            path: path,
          );
        }
      } else if (FakeDns.isAddress(server.address)) {
        throw JsonDiagnostic(
          'FakeDNS requires the app-dns-fake tag',
          path: [...path, 'address'],
        );
      }
    }
    List<RoutingDnsResolver> role(String tag) => List.unmodifiable([
      for (final server in servers)
        if (server.tag == tag) RoutingDnsResolver.fromXrayDnsServer(server),
    ]);
    return RoutingDnsSettings(
      proxyResolvers: role(proxyTag),
      directResolvers: role(directTag),
      disableCache: dns?.disableCache ?? false,
      sameExitOnly: dns?.disableFallbackIfMatch ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'proxyResolvers': [
      for (final resolver in effectiveProxyResolvers) resolver.toJson(),
    ],
    'directResolvers': [
      for (final resolver in effectiveDirectResolvers) resolver.toJson(),
    ],
    'disableCache': disableCache,
    'sameExitOnly': sameExitOnly,
    'nonAddressPolicy': nonAddressPolicy.name,
  };

  /// Standard DNS exchange fields only; no derived domains or platform query.
  XrayDns toStoredXrayDns({bool fakeDns = false}) => XrayDns(
    disableCache: disableCache,
    disableFallbackIfMatch: sameExitOnly,
    servers: [
      for (final resolver in effectiveProxyResolvers)
        resolver.toXrayDnsServer(tag: proxyTag),
      for (final resolver in effectiveDirectResolvers)
        resolver.toXrayDnsServer(tag: directTag),
      if (fakeDns) XrayDnsServer(address: FakeDns.address, tag: FakeDns.tag),
    ],
  );

  RoutingDnsSettings withDirectAddress(String value) => copyWith(
    directResolvers: [
      effectiveDirectResolvers.first.copyWith(address: value),
      ...effectiveDirectResolvers.skip(1),
    ],
  );

  RoutingDnsSettings copyWith({
    List<RoutingDnsResolver>? proxyResolvers,
    List<RoutingDnsResolver>? directResolvers,
    bool? disableCache,
    bool? sameExitOnly,
    NonAddressDnsPolicy? nonAddressPolicy,
  }) => RoutingDnsSettings(
    proxyResolvers: List.unmodifiable(proxyResolvers ?? this.proxyResolvers),
    directResolvers: List.unmodifiable(directResolvers ?? this.directResolvers),
    disableCache: disableCache ?? this.disableCache,
    sameExitOnly: sameExitOnly ?? this.sameExitOnly,
    nonAddressPolicy: nonAddressPolicy ?? this.nonAddressPolicy,
  );

  Map<String, dynamic> effectiveJson({bool directEnabled = true}) => {
    'proxyResolvers': [
      for (final resolver in effectiveProxyResolvers) resolver.toJson(),
    ],
    if (directEnabled)
      'directResolvers': [
        for (final resolver in effectiveDirectResolvers) resolver.toJson(),
      ],
    'disableCache': disableCache,
    'sameExitOnly': sameExitOnly,
    'nonAddressPolicy': nonAddressPolicy.name,
  };

  void validate({bool directEnabled = true}) {
    for (final resolver in [
      ...effectiveProxyResolvers,
      if (directEnabled) ...effectiveDirectResolvers,
    ]) {
      resolver.validate();
    }
  }
}

/// Shared ordinary-mode sniffing; destination overrides remain App-managed.
final class RoutingSniffingSettings {
  final bool enabled;
  final bool routeOnly;
  final bool metadataOnly;

  const RoutingSniffingSettings({
    this.enabled = true,
    this.routeOnly = false,
    this.metadataOnly = false,
  });

  factory RoutingSniffingSettings.fromJson(Map<String, dynamic> json) =>
      RoutingSniffingSettings(
        enabled: json['enabled'] as bool? ?? true,
        routeOnly: json['routeOnly'] as bool? ?? false,
        metadataOnly: json['metadataOnly'] as bool? ?? false,
      );

  factory RoutingSniffingSettings.fromXraySniffing(
    XrayInboundSniffing? sniffing,
  ) {
    final overrides = sniffing?.destOverride;
    if (overrides != null) {
      final values = overrides.toSet();
      if (values.length != overrides.length ||
          !values.containsAll(const ['http', 'tls', 'quic']) ||
          values.any(
            (value) =>
                !const {'http', 'tls', 'quic', 'fakedns'}.contains(value),
          )) {
        throw const JsonDiagnostic(
          'Custom sniffing uses App-managed HTTP/TLS/QUIC overrides',
          path: ['inbounds', 0, 'sniffing', 'destOverride'],
        );
      }
    }
    return RoutingSniffingSettings(
      enabled: sniffing?.enabled ?? true,
      routeOnly: sniffing?.routeOnly ?? false,
      metadataOnly: sniffing?.metadataOnly ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'routeOnly': routeOnly,
    'metadataOnly': metadataOnly,
  };

  Map<String, dynamic> effectiveJson({bool fakeDns = false}) =>
      enabled ? toXraySniffing(fakeDns: fakeDns).toJson() : {'enabled': false};

  XrayInboundSniffing toXraySniffing({
    bool fakeDns = false,
    bool forStorage = false,
  }) => !enabled && !forStorage
      ? XrayInboundSniffing(enabled: false)
      : XrayInboundSniffing(
          enabled: enabled,
          routeOnly: routeOnly,
          destOverride: ['http', 'tls', 'quic', if (fakeDns) 'fakedns'],
          metadataOnly: metadataOnly ? true : null,
        );

  RoutingSniffingSettings copyWith({
    bool? enabled,
    bool? routeOnly,
    bool? metadataOnly,
  }) => RoutingSniffingSettings(
    enabled: enabled ?? this.enabled,
    routeOnly: routeOnly ?? this.routeOnly,
    metadataOnly: metadataOnly ?? this.metadataOnly,
  );

  void validate({bool fakeDns = false}) {
    if (fakeDns && !enabled) {
      throw const FormatException('FakeDNS requires managed sniffing');
    }
  }
}

/// Runtime observation stays separate from manual node latency tests.
final class RoutingSelectionSettings {
  static const defaultProbeURL = 'https://www.google.com/generate_204';
  static const defaultProbeInterval = '60s';

  final String type;
  final String probeURL;
  final String probeInterval;
  final bool enableConcurrency;

  const RoutingSelectionSettings({
    this.type = 'roundRobin',
    this.probeURL = defaultProbeURL,
    this.probeInterval = defaultProbeInterval,
    this.enableConcurrency = true,
  });

  factory RoutingSelectionSettings.fromJson(Map<String, dynamic> json) =>
      RoutingSelectionSettings(
        type: json['type'] as String? ?? 'roundRobin',
        probeURL: json['probeURL'] as String? ?? defaultProbeURL,
        probeInterval: json['probeInterval'] as String? ?? defaultProbeInterval,
        enableConcurrency: json['enableConcurrency'] as bool? ?? true,
      );

  factory RoutingSelectionSettings.fromXray({
    XrayRouting? routing,
    XrayObservatory? observatory,
  }) {
    final balancers = routing?.balancers ?? const <XrayBalancer>[];
    final proxy = balancers.where((balancer) => balancer.tag == 'proxy');
    return RoutingSelectionSettings(
      type: proxy.isEmpty
          ? 'roundRobin'
          : proxy.first.strategy?.type ?? 'roundRobin',
      probeURL: observatory?.probeURL ?? defaultProbeURL,
      probeInterval: observatory?.probeInterval ?? defaultProbeInterval,
      enableConcurrency: observatory?.enableConcurrency ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'probeURL': probeURL.trim(),
    'probeInterval': probeInterval,
    'enableConcurrency': enableConcurrency,
  };

  Map<String, dynamic> effectiveJson({int entryCount = 2}) =>
      type == 'leastPing' && entryCount >= 2
      ? {
          'type': type,
          'probeURL': probeURL.trim(),
          'probeIntervalNanoseconds': durationNanoseconds(probeInterval),
          'enableConcurrency': enableConcurrency,
        }
      : {'type': 'roundRobin'};

  XrayRouting toStoredRouting() => XrayRouting(
    balancers: [
      XrayBalancer(
        tag: 'proxy',
        strategy: XrayBalancingStrategy(type: type),
      ),
    ],
  );

  XrayObservatory toStoredObservatory() => XrayObservatory(
    probeURL: probeURL.trim(),
    probeInterval: probeInterval,
    enableConcurrency: enableConcurrency,
  );

  ({XrayBalancer balancer, XrayObservatory observatory, bool automatic})
  compile({required List<String> selector, String? fallbackTag}) {
    final automatic = type == 'leastPing' && selector.length >= 2;
    return (
      automatic: automatic,
      balancer: XrayBalancer(
        tag: 'proxy',
        selector: List.of(selector),
        strategy: XrayBalancingStrategy(
          type: automatic ? 'leastPing' : 'roundRobin',
        ),
        fallbackTag: automatic ? selector.first : fallbackTag ?? 'direct',
      ),
      observatory: automatic
          ? XrayObservatory(
              subjectSelector: List.of(selector),
              probeURL: probeURL.trim(),
              probeInterval: probeInterval,
              enableConcurrency: enableConcurrency,
            )
          : XrayObservatory(subjectSelector: []),
    );
  }

  RoutingSelectionSettings copyWith({
    String? type,
    String? probeURL,
    String? probeInterval,
    bool? enableConcurrency,
  }) => RoutingSelectionSettings(
    type: type ?? this.type,
    probeURL: probeURL ?? this.probeURL,
    probeInterval: probeInterval ?? this.probeInterval,
    enableConcurrency: enableConcurrency ?? this.enableConcurrency,
  );

  void validate() {
    if (type != 'roundRobin' && type != 'leastPing') {
      throw const FormatException('Unsupported proxy selection strategy');
    }
    if (type != 'leastPing') return;
    if (!PingUrl.isValidCustomUrl(probeURL.trim())) {
      throw const FormatException('Probe URL must be an HTTP(S) URL');
    }
    final duration = durationNanoseconds(probeInterval);
    if (duration != null &&
        duration >= 10000000000 &&
        duration < 9223372036854775808.0) {
      return;
    }
    throw const FormatException(
      'Probe interval must be a finite duration of at least 10s',
    );
  }

  /// Go duration syntax, including compound and fractional components.
  static double? durationNanoseconds(String text) {
    var value = text;
    if (value.startsWith('+')) value = value.substring(1);
    if (value.isEmpty) return null;
    final part = RegExp(r'(\d+(?:\.\d*)?|\.\d+)(ns|us|µs|μs|ms|s|m|h)');
    const units = <String, double>{
      'ns': 1,
      'us': 1000,
      'µs': 1000,
      'μs': 1000,
      'ms': 1000000,
      's': 1000000000,
      'm': 60000000000,
      'h': 3600000000000,
    };
    var offset = 0;
    var total = 0.0;
    for (final match in part.allMatches(value)) {
      if (match.start != offset) return null;
      final amount = double.tryParse(match[1]!);
      if (amount == null || !amount.isFinite) return null;
      total += amount * units[match[2]]!;
      offset = match.end;
    }
    return offset == value.length && total.isFinite ? total : null;
  }
}

List<RoutingDnsResolver> _resolvers(Object? value) => value == null
    ? RoutingDnsSettings.defaultResolvers
    : List<RoutingDnsResolver>.unmodifiable([
        for (final json in value as List)
          RoutingDnsResolver.fromJson(Map<String, dynamic>.from(json as Map)),
      ]);
