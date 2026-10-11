// Public list parameters keep the settings API independent of private storage.
// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/shared/ping/state.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';

/// Editable DNS resolver options. Null cache values inherit the DNS root.
final class RoutingDnsResolver {
  final String address;
  final int timeoutMs;
  final List<String> _expectedIPs;
  final List<String> _unexpectedIPs;
  final bool? disableCache;
  final bool? serveStale;
  final int? serveExpiredTTL;

  const RoutingDnsResolver({
    required this.address,
    this.timeoutMs = 4000,
    List<String> expectedIPs = const [],
    List<String> unexpectedIPs = const [],
    this.disableCache,
    this.serveStale,
    this.serveExpiredTTL,
  }) : _expectedIPs = expectedIPs,
       _unexpectedIPs = unexpectedIPs;

  List<String> get expectedIPs => List.unmodifiable(_expectedIPs);
  List<String> get unexpectedIPs => List.unmodifiable(_unexpectedIPs);

  factory RoutingDnsResolver.fromJson(Map<String, dynamic> json) =>
      RoutingDnsResolver(
        address: json['address'] as String,
        timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 4000,
        expectedIPs: _strings(json['expectedIPs']),
        unexpectedIPs: _strings(json['unexpectedIPs']),
        disableCache: json['disableCache'] as bool?,
        serveStale: json['serveStale'] as bool?,
        serveExpiredTTL: (json['serveExpiredTTL'] as num?)?.toInt(),
      );

  factory RoutingDnsResolver.fromXrayDnsServer(XrayDnsServer server) =>
      RoutingDnsResolver(
        address: server.address ?? '',
        timeoutMs: server.timeoutMs ?? 4000,
        expectedIPs: List.unmodifiable(
          server.expectedIPs?.isNotEmpty == true
              ? server.expectedIPs!
              : server.expectIPs ?? server.expectedIPs ?? const [],
        ),
        unexpectedIPs: List.unmodifiable(server.unexpectedIPs ?? const []),
        disableCache: server.disableCache,
        serveStale: server.serveStale,
        serveExpiredTTL: server.serveExpiredTTL,
      );

  Map<String, dynamic> toJson() => {
    'address': address.trim(),
    'timeoutMs': timeoutMs,
    if (expectedIPs.isNotEmpty) 'expectedIPs': expectedIPs,
    if (unexpectedIPs.isNotEmpty) 'unexpectedIPs': unexpectedIPs,
    if (disableCache != null) 'disableCache': disableCache,
    if (serveStale != null) 'serveStale': serveStale,
    if (serveExpiredTTL != null) 'serveExpiredTTL': serveExpiredTTL,
  };

  Map<String, dynamic> effectiveJson({
    bool rootDisableCache = false,
    bool rootServeStale = false,
    int rootServeExpiredTTL = 300,
  }) {
    final cacheDisabled = disableCache ?? rootDisableCache;
    final stale = serveStale ?? rootServeStale;
    return {
      'address': address.trim(),
      'timeoutMs': timeoutMs == 0 ? 4000 : timeoutMs,
      'expectedIPs': expectedIPs,
      'unexpectedIPs': unexpectedIPs,
      'disableCache': cacheDisabled,
      if (!cacheDisabled) 'serveStale': stale,
      if (!cacheDisabled && stale)
        'serveExpiredTTL': serveExpiredTTL ?? rootServeExpiredTTL,
    };
  }

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
    timeoutMs: timeoutMs,
    expectedIPs: expectedIPs.isEmpty ? null : expectedIPs,
    unexpectedIPs: unexpectedIPs.isEmpty ? null : unexpectedIPs,
    disableCache: disableCache,
    serveStale: serveStale,
    serveExpiredTTL: serveExpiredTTL,
  );

  RoutingDnsResolver copyWith({
    String? address,
    int? timeoutMs,
    List<String>? expectedIPs,
    List<String>? unexpectedIPs,
    bool? disableCache,
    bool clearDisableCache = false,
    bool? serveStale,
    bool clearServeStale = false,
    int? serveExpiredTTL,
    bool clearServeExpiredTTL = false,
  }) => RoutingDnsResolver(
    address: address ?? this.address,
    timeoutMs: timeoutMs ?? this.timeoutMs,
    expectedIPs: List.unmodifiable(expectedIPs ?? this.expectedIPs),
    unexpectedIPs: List.unmodifiable(unexpectedIPs ?? this.unexpectedIPs),
    disableCache: clearDisableCache ? null : disableCache ?? this.disableCache,
    serveStale: clearServeStale ? null : serveStale ?? this.serveStale,
    serveExpiredTTL: clearServeExpiredTTL
        ? null
        : serveExpiredTTL ?? this.serveExpiredTTL,
  );

  void validate({
    bool rootDisableCache = false,
    bool rootServeStale = false,
    int rootServeExpiredTTL = 300,
  }) {
    if (address.trim().isEmpty || timeoutMs < 0) {
      throw const FormatException('DNS address and timeout are invalid');
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
    final ttl = serveExpiredTTL ?? rootServeExpiredTTL;
    if (ttl < 0 || ttl > 0xffffffff) {
      throw const FormatException('DNS stale cache lifetime is invalid');
    }
    if (!(disableCache ?? rootDisableCache) &&
        (serveStale ?? rootServeStale) &&
        ttl == 0) {
      throw const FormatException('DNS stale cache requires a finite lifetime');
    }
  }
}

/// App-owned DNS policy; runtime domain blocks are generated from routing.
final class RoutingDnsSettings {
  static const defaultAddress = '8.8.8.8';
  static const proxyTag = 'app-dns-proxy';
  static const directTag = 'app-dns-direct';
  static const defaultResolvers = [RoutingDnsResolver(address: defaultAddress)];

  final List<RoutingDnsResolver> _proxyResolvers;
  final List<RoutingDnsResolver> _directResolvers;
  final bool disableCache;
  final bool serveStale;
  final int serveExpiredTTL;
  final bool enableParallelQuery;
  final bool sameExitOnly;

  const RoutingDnsSettings({
    List<RoutingDnsResolver> proxyResolvers = defaultResolvers,
    List<RoutingDnsResolver> directResolvers = defaultResolvers,
    this.disableCache = false,
    this.serveStale = false,
    this.serveExpiredTTL = 300,
    this.enableParallelQuery = false,
    this.sameExitOnly = false,
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
        serveStale: json['serveStale'] as bool? ?? false,
        serveExpiredTTL: (json['serveExpiredTTL'] as num?)?.toInt() ?? 300,
        enableParallelQuery: json['enableParallelQuery'] as bool? ?? false,
        sameExitOnly: json['sameExitOnly'] as bool? ?? false,
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
        if (!FakeDns.isAddress(server.address) ||
            server.timeoutMs != null ||
            server.expectedIPs != null ||
            server.expectIPs != null ||
            server.unexpectedIPs != null ||
            server.disableCache != null ||
            server.serveStale != null ||
            server.serveExpiredTTL != null) {
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
      serveStale: dns?.serveStale ?? false,
      serveExpiredTTL: dns?.serveExpiredTTL ?? 300,
      enableParallelQuery: dns?.enableParallelQuery ?? false,
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
    'serveStale': serveStale,
    'serveExpiredTTL': serveExpiredTTL,
    'enableParallelQuery': enableParallelQuery,
    'sameExitOnly': sameExitOnly,
  };

  /// Standard DNS exchange fields only; no derived domains or platform query.
  XrayDns toStoredXrayDns({bool fakeDns = false}) => XrayDns(
    disableCache: disableCache,
    serveStale: serveStale,
    serveExpiredTTL: serveExpiredTTL,
    disableFallbackIfMatch: sameExitOnly,
    enableParallelQuery: enableParallelQuery,
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
    bool? serveStale,
    int? serveExpiredTTL,
    bool? enableParallelQuery,
    bool? sameExitOnly,
  }) => RoutingDnsSettings(
    proxyResolvers: List.unmodifiable(proxyResolvers ?? this.proxyResolvers),
    directResolvers: List.unmodifiable(directResolvers ?? this.directResolvers),
    disableCache: disableCache ?? this.disableCache,
    serveStale: serveStale ?? this.serveStale,
    serveExpiredTTL: serveExpiredTTL ?? this.serveExpiredTTL,
    enableParallelQuery: enableParallelQuery ?? this.enableParallelQuery,
    sameExitOnly: sameExitOnly ?? this.sameExitOnly,
  );

  Map<String, dynamic> effectiveJson({
    bool directEnabled = true,
    bool fakeDns = false,
  }) => {
    'proxyResolvers': [
      for (final resolver in effectiveProxyResolvers)
        resolver.effectiveJson(
          rootDisableCache: disableCache,
          rootServeStale: serveStale,
          rootServeExpiredTTL: serveExpiredTTL,
        ),
    ],
    if (directEnabled)
      'directResolvers': [
        for (final resolver in effectiveDirectResolvers)
          resolver.effectiveJson(
            rootDisableCache: disableCache,
            rootServeStale: serveStale,
            rootServeExpiredTTL: serveExpiredTTL,
          ),
      ],
    'sameExitOnly': sameExitOnly,
    'enableParallelQuery':
        enableParallelQuery &&
        sameExitOnly &&
        !fakeDns &&
        (effectiveProxyResolvers.length > 1 ||
            (directEnabled && effectiveDirectResolvers.length > 1)),
  };

  void validate({bool directEnabled = true}) {
    if (serveExpiredTTL < 0 ||
        serveExpiredTTL > 0xffffffff ||
        (!disableCache && serveStale && serveExpiredTTL == 0)) {
      throw const FormatException('DNS stale cache requires a finite lifetime');
    }
    for (final resolver in [
      ...effectiveProxyResolvers,
      if (directEnabled) ...effectiveDirectResolvers,
    ]) {
      resolver.validate(
        rootDisableCache: disableCache,
        rootServeStale: serveStale,
        rootServeExpiredTTL: serveExpiredTTL,
      );
    }
  }
}

/// Shared ordinary-mode sniffing; destination overrides remain App-managed.
final class RoutingSniffingSettings {
  final bool enabled;
  final bool routeOnly;
  final bool metadataOnly;
  final List<String> _domainsExcluded;
  final List<String> _ipsExcluded;

  const RoutingSniffingSettings({
    this.enabled = true,
    this.routeOnly = false,
    this.metadataOnly = false,
    List<String> domainsExcluded = const [],
    List<String> ipsExcluded = const [],
  }) : _domainsExcluded = domainsExcluded,
       _ipsExcluded = ipsExcluded;

  List<String> get domainsExcluded => List.unmodifiable(_domainsExcluded);
  List<String> get ipsExcluded => List.unmodifiable(_ipsExcluded);

  factory RoutingSniffingSettings.fromJson(Map<String, dynamic> json) =>
      RoutingSniffingSettings(
        enabled: json['enabled'] as bool? ?? true,
        routeOnly: json['routeOnly'] as bool? ?? false,
        metadataOnly: json['metadataOnly'] as bool? ?? false,
        domainsExcluded: _strings(json['domainsExcluded']),
        ipsExcluded: _strings(json['ipsExcluded']),
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
      domainsExcluded: List.unmodifiable(sniffing?.domainsExcluded ?? const []),
      ipsExcluded: List.unmodifiable(sniffing?.ipsExcluded ?? const []),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'routeOnly': routeOnly,
    'metadataOnly': metadataOnly,
    'domainsExcluded': domainsExcluded,
    'ipsExcluded': ipsExcluded,
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
          domainsExcluded: domainsExcluded.isEmpty ? null : domainsExcluded,
          ipsExcluded: ipsExcluded.isEmpty ? null : ipsExcluded,
        );

  RoutingSniffingSettings copyWith({
    bool? enabled,
    bool? routeOnly,
    bool? metadataOnly,
    List<String>? domainsExcluded,
    List<String>? ipsExcluded,
  }) => RoutingSniffingSettings(
    enabled: enabled ?? this.enabled,
    routeOnly: routeOnly ?? this.routeOnly,
    metadataOnly: metadataOnly ?? this.metadataOnly,
    domainsExcluded: List.unmodifiable(domainsExcluded ?? this.domainsExcluded),
    ipsExcluded: List.unmodifiable(ipsExcluded ?? this.ipsExcluded),
  );

  void validate({bool fakeDns = false}) {
    if (fakeDns && !enabled) {
      throw const FormatException('FakeDNS requires managed sniffing');
    }
    if (fakeDns) {
      for (final (index, excluded) in ipsExcluded.indexed) {
        if (_overlapsFakeDnsPool(excluded)) {
          throw JsonDiagnostic(
            'Sniffing IP exclusions overlap a managed FakeDNS pool',
            path: ['inbounds', 0, 'sniffing', 'ipsExcluded', index],
          );
        }
      }
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
    'probeURL': probeURL,
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
    probeURL: probeURL,
    probeInterval: probeInterval,
    enableConcurrency: enableConcurrency,
  );

  ({XrayBalancer balancer, XrayObservatory observatory, bool automatic})
  compile({required List<String> selector}) {
    final automatic = type == 'leastPing' && selector.length >= 2;
    return (
      automatic: automatic,
      balancer: XrayBalancer(
        tag: 'proxy',
        selector: List.of(selector),
        strategy: XrayBalancingStrategy(
          type: automatic ? 'leastPing' : 'roundRobin',
        ),
        fallbackTag: automatic ? selector.first : 'direct',
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

List<String> _strings(Object? value) => value == null
    ? const []
    : List<String>.unmodifiable((value as List).cast<String>());

List<RoutingDnsResolver> _resolvers(Object? value) => value == null
    ? RoutingDnsSettings.defaultResolvers
    : List<RoutingDnsResolver>.unmodifiable([
        for (final json in value as List)
          RoutingDnsResolver.fromJson(Map<String, dynamic>.from(json as Map)),
      ]);
bool _overlapsFakeDnsPool(String text) {
  final parts = text.trim().split('/');
  if (parts.length > 2) return false;
  final address = InternetAddress.tryParse(parts.first);
  if (address == null) return false;
  final bytes = address.rawAddress;
  final prefix = parts.length == 1
      ? bytes.length * 8
      : int.tryParse(parts.last);
  if (prefix == null || prefix < 0 || prefix > bytes.length * 8) return false;
  final pool = address.type == InternetAddressType.IPv4
      ? InternetAddress('198.19.0.0').rawAddress
      : InternetAddress('fc00:1::').rawAddress;
  final poolPrefix = address.type == InternetAddressType.IPv4 ? 16 : 64;
  final compareBits = prefix < poolPrefix ? prefix : poolPrefix;
  for (
    var index = 0;
    index < bytes.length && index * 8 < compareBits;
    index++
  ) {
    final remaining = compareBits - index * 8;
    final mask = remaining >= 8 ? 255 : (255 << (8 - remaining)) & 255;
    if ((bytes[index] & mask) != (pool[index] & mask)) return false;
  }
  return true;
}
