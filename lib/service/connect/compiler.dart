import 'dart:convert';

import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/dialing.dart';
import 'package:onexray/service/connect/runtime_network_policy.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/dns.dart';
import 'package:onexray/service/connect/routing/dns_forwarding.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/shared/xray/runtime_inbounds.dart';
import 'package:onexray/service/shared/xray/runtime_outbounds.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';
import 'package:onexray/service/shared/xray/fragment.dart';
import 'package:onexray/service/shared/xray/remnawave.dart';
import 'package:onexray/service/shared/xray/vpn_config.dart';
import 'package:onexray/service/shared/xray/server_dialing.dart';

/// A complete provider graph selected as one subscription asset.
class ResolvedProfile {
  final int id;
  final int sourceId;
  final String name;
  final Map<String, dynamic> _config;

  ResolvedProfile({
    required this.id,
    required this.sourceId,
    required this.name,
    required Map<String, dynamic> config,
  }) : _config = JsonTool.copyMap(config) {
    if (id <= 0 || sourceId <= 0 || name.trim().isEmpty) {
      throw const FormatException('Invalid provider profile');
    }
  }

  factory ResolvedProfile.fromRow(CoreConfigData row) {
    if (row.type != CoreConfigType.Remnawave.name || row.data == null) {
      throw const FormatException('Provider configuration is unavailable');
    }
    return ResolvedProfile(
      id: row.id,
      sourceId: row.subId,
      name: row.name,
      config: ConnectionCompiler.parseRawJson(
        utf8.decode(base64Decode(row.data!)),
      ),
    );
  }

  String get type => CoreConfigType.Remnawave.name;
  Map<String, dynamic> get config => JsonTool.copyMap(_config);
}

class ResolvedServer {
  final int id;
  final int sourceId;
  final String name;
  final Map<String, dynamic> _outbound;
  late final String outboundJson = jsonEncode(_outbound);

  ResolvedServer({
    required this.id,
    required this.sourceId,
    required Map<String, dynamic> outbound,
  }) : name = outboundDisplayName(outbound),
       _outbound = JsonTool.copyMap(outbound);

  factory ResolvedServer.fromRow(CoreConfigData row) {
    if (row.type != 'outbound') {
      throw const FormatException('A server must be an outbound');
    }
    return ResolvedServer(
      id: row.id,
      sourceId: row.subId,
      outbound: readOutboundFromDbData(row),
    );
  }

  Map<String, dynamic> get outbound => JsonTool.copyMap(_outbound);
  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'name': name,
    'outbound': outbound,
  };
}

class RuntimeOptions {
  final ConnectionPlatform platform;
  final WindowsMode windowsMode;
  final String sessionDirectory;
  final int metricsPort;
  final int socksPort;
  final bool lanProxyEnabled;
  final int lanProxyPort;
  final bool ipv6;
  final ServerDialingSettings dialing;
  final String tunDnsIpv4Address;
  final String tunDnsIpv6Address;
  final String interfaceName;
  final bool logEnabled;
  final bool logFilesSupported;
  final String logLevel;
  final bool dnsLog;
  final String maskAddress;

  RuntimeOptions({
    required this.platform,
    WindowsMode? windowsMode,
    required this.sessionDirectory,
    required this.metricsPort,
    required this.socksPort,
    this.lanProxyEnabled = false,
    this.lanProxyPort = defaultLanProxyPort,
    this.ipv6 = true,
    this.dialing = const ServerDialingSettings(),
    this.tunDnsIpv4Address = '8.8.8.8',
    this.tunDnsIpv6Address = '2001:4860:4860::8888',
    this.interfaceName = '',
    this.logEnabled = false,
    this.logFilesSupported = true,
    this.logLevel = 'warning',
    this.dnsLog = true,
    this.maskAddress = '',
  }) : windowsMode = windowsMode ?? windowsBuildMode {
    if (metricsPort == socksPort) {
      throw const FormatException('Runtime ports are invalid');
    }
    if (lanProxyEnabled && (lanProxyPort < 1024 || lanProxyPort > 65535)) {
      throw const FormatException('LAN proxy port must be within 1024–65535');
    }
    if (lanProxyEnabled &&
        (lanProxyPort == metricsPort || lanProxyPort == socksPort)) {
      throw const FormatException(
        'LAN proxy port conflicts with a runtime port',
      );
    }
    if ((platform == ConnectionPlatform.windows ||
            platform == ConnectionPlatform.linux) &&
        interfaceName.isEmpty) {
      throw const FormatException('Network interface is required');
    }
  }

  bool get usesWindowsSystemVpn =>
      platform == ConnectionPlatform.windows && windowsMode == WindowsMode.msix;
}

class CompiledConnection {
  final String xrayJson;
  final List<ResolvedServer> entries;
  final ResolvedServer? finalExit;
  final Map<String, int> nodeTags;
  final ResolvedProfile? profile;

  CompiledConnection({
    required this.xrayJson,
    required Iterable<ResolvedServer> entries,
    required this.finalExit,
    required Map<String, int> nodeTags,
    this.profile,
  }) : entries = List.unmodifiable(entries),
       nodeTags = Map.unmodifiable(nodeTags);

  Map<String, dynamic> get config =>
      jsonDecode(xrayJson) as Map<String, dynamic>;
}

/// Pure value compilation. Never opens a database, edits an asset, allocates a
/// port or starts Xray. Runtime files and commits belong to the coordinator.
class ConnectionCompiler {
  static Map<String, dynamic> parseRawJson(String text) {
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Raw configuration must be an object');
    }
    return value;
  }

  /// Compare editor drafts through the same overrides as a real Raw runtime.
  /// The caller supplies identical options for both drafts; no files are written.
  static Map<String, dynamic> rawSemanticJson(
    Map<String, dynamic> source,
    RuntimeOptions options,
  ) {
    final value = JsonTool.copyMap(source)..remove('name');
    return _fullRuntimeMap(VpnConfigAdapter.adapt(value), options);
  }

  static const dnsProxy = RoutingDns.proxyTag;
  static const dnsDirect = RoutingDns.directTag;
  static const dnsOutbound = RoutingDnsForwarding.outboundTag;

  /// Checks only collisions with the enabled App-managed LAN listener.
  static void validateLanProxyInbounds(List<dynamic> inbounds, int port) {
    for (final inbound in inbounds.whereType<Map>()) {
      final tag = inbound['tag'];
      if (tag == lanProxyInboundTag) {
        throw const FormatException('The LAN proxy inbound tag is App-managed');
      }
      if (tag != 'tunIn' && portIncludes(inbound['port'], port)) {
        throw const FormatException(
          'LAN proxy port conflicts with a configuration inbound',
        );
      }
    }
  }

  /// The editor and runtime share these exact built-in rules and their order.
  static List<XrayRoutingRule> smartRules(
    SmartRoutingSettings smart,
    RegionCatalog regions,
  ) {
    final domains = <String>{
      if (smart.directPrivate) 'geosite:PRIVATE',
      if (smart.directApple) 'geosite:APPLE',
      if (smart.directWindows) ...['geosite:MICROSOFT', 'geosite:BING'],
      ...regions.domainRules(smart.directRegions),
    }.toList();
    final ips = <String>{
      if (smart.directPrivate) 'geoip:PRIVATE',
      ...regions.ipRules(smart.directRegions),
    }.toList();
    return [
      if (smart.blockAds)
        XrayRoutingRule(
          ruleTag: 'app-smart-ads',
          domain: ['geosite:CATEGORY-ADS-ALL'],
          outboundTag: 'block',
        ),
      if (smart.directWindows)
        XrayRoutingRule(
          ruleTag: 'app-smart-github',
          domain: ['geosite:GITHUB'],
          balancerTag: 'proxy',
        ),
      if (domains.isNotEmpty)
        XrayRoutingRule(
          ruleTag: 'app-smart-direct-domain',
          domain: domains,
          outboundTag: 'direct',
        ),
      if (ips.isNotEmpty)
        XrayRoutingRule(
          ruleTag: 'app-smart-direct-ip',
          ip: ips,
          outboundTag: 'direct',
        ),
    ];
  }

  static CompiledConnection compile({
    required ConnectionSettings settings,
    required List<ResolvedServer> entries,
    ResolvedServer? finalExit,
    Map<String, dynamic>? raw,
    ResolvedProfile? profile,
    RoutingConfiguration? custom,
    required RegionCatalog regions,
    required RuntimeOptions options,
  }) {
    final nodeTags = <String, int>{};
    late final Map<String, dynamic> config;
    if (profile != null) {
      if (settings.expert ||
          (settings.selection.kind == SelectionKind.server &&
              settings.selection.id != profile.id) ||
          (settings.selection.kind == SelectionKind.source &&
              settings.selection.id != profile.sourceId) ||
          entries.isNotEmpty ||
          finalExit != null ||
          raw != null ||
          custom != null) {
        throw const FormatException(
          'Provider configuration requires one matching complete profile',
        );
      }
      final adapted = RemnawaveAdapter.adapt(profile.config);
      config = _fullRuntimeMap(adapted, options);
    } else if (settings.expert) {
      if (raw == null || entries.isNotEmpty || finalExit != null) {
        throw const FormatException(
          'Raw configuration is required without normal nodes',
        );
      }
      config = _fullRuntimeMap(VpnConfigAdapter.adapt(raw), options);
    } else {
      final required = settings.requiredEntries(
        customEntryCount: custom?.entryCount,
      );
      if (entries.length != required ||
          entries.map((entry) => entry.id).toSet().length != required) {
        throw const FormatException('Not enough distinct entry nodes');
      }
      if (settings.finalExitId != finalExit?.id ||
          entries.any((entry) => entry.id == finalExit?.id)) {
        throw const FormatException('Invalid final exit selection');
      }
      if (settings.selection.kind == SelectionKind.server &&
          entries.single.id != settings.selection.id) {
        throw const FormatException('Fixed server does not match');
      }
      if (settings.trafficMode == TrafficMode.custom && custom == null) {
        throw const FormatException('Custom route is required');
      }
      if (settings.trafficMode == TrafficMode.custom &&
          custom is AdvancedRoutingProfile) {
        final outbounds = <Map<String, dynamic>>[];
        for (final (index, entry) in entries.indexed) {
          final tag = 'app-entry-$index';
          outbounds.add(_node(entry, tag));
          nodeTags[tag] = entry.id;
        }
        _applyOutboundPolicy(outbounds, options, raw: false);
        final template = custom.fillSlots(
          outbounds,
          includeLanProxy: options.lanProxyEnabled,
        );
        final inbounds = _objects(template, 'inbounds');
        for (var index = 0; index < inbounds.length; index++) {
          if (inbounds[index]['tag'] == 'tunIn') {
            inbounds[index] = {
              ..._runtimeInbound(
                options,
                fakeDns: FakeDns.usedByRaw(template),
              ).toJson(),
              ...inbounds[index],
            };
          }
        }
        template['inbounds'] = inbounds;
        return CompiledConnection(
          xrayJson: jsonEncode(
            _rawRuntimeMap(
              template,
              options,
              includeLanProxy: options.lanProxyEnabled,
            ),
          ),
          entries: entries,
          finalExit: null,
          nodeTags: nodeTags,
        );
      }
      final ordinary = custom is RoutingProfileState ? custom : null;
      final allVpn = settings.trafficMode == TrafficMode.allVpn;
      final rules = <XrayRoutingRule>[];
      if (settings.trafficMode == TrafficMode.smart) {
        rules.addAll(smartRules(settings.smart, regions));
      } else if (settings.trafficMode == TrafficMode.custom) {
        for (final (index, rule) in ordinary!.rules.indexed) {
          rules.add(rule.xrayJson..ruleTag = 'app-custom-$index');
        }
      }
      final entriesOutbounds = <Map<String, dynamic>>[];
      final exits = <Map<String, dynamic>>[];
      final selector = <String>[];
      for (final (index, entry) in entries.indexed) {
        final entryTag = 'app-entry-$index';
        final outbound = _node(entry, entryTag);
        nodeTags[entryTag] = entry.id;
        entriesOutbounds.add(outbound);
        if (finalExit == null) {
          selector.add(entryTag);
        } else {
          final exitTag = 'app-exit-$index';
          final exit = _node(finalExit, exitTag);
          setOutboundDialerProxy(exit, entryTag);
          nodeTags[exitTag] = finalExit.id;
          exits.add(exit);
          selector.add(exitTag);
        }
      }
      final fragment = switch (settings.trafficMode) {
        TrafficMode.smart =>
          settings.smart.fragment ? XrayFragment.defaultOutbound() : null,
        TrafficMode.custom => ordinary!.fragmentOutbound,
        TrafficMode.allVpn => null,
      };
      final helpers = <Map<String, dynamic>>[?fragment];
      final connectedEntries = XrayFragment.connectEntries(
        entriesOutbounds,
        helpers,
      );
      final outbounds = <Map<String, dynamic>>[
        if (finalExit == null) ...connectedEntries else ...exits,
        if (finalExit != null) ...connectedEntries,
        ...helpers,
      ];
      _applyOutboundPolicy(outbounds, options, raw: false);
      final bootstrapDomains = ManagedServerDialing.apply(
        outbounds: outbounds,
        settings: options.dialing.effective(ipv6: options.ipv6),
        interfaceName:
            options.platform == ConnectionPlatform.windows ||
                options.platform == ConnectionPlatform.linux
            ? options.interfaceName
            : null,
      );
      outbounds.addAll([
        createFreedomOutbound(
          tag: 'direct',
          interfaceName:
              options.platform == ConnectionPlatform.windows ||
                  options.platform == ConnectionPlatform.linux
              ? options.interfaceName
              : null,
        ).toJson(),
        createBlackholeOutbound(tag: 'block').toJson(),
      ]);
      final dnsSettings = switch (settings.trafficMode) {
        TrafficMode.smart => settings.smart.dns,
        TrafficMode.custom => ordinary!.dns,
        TrafficMode.allVpn => const RoutingDnsSettings(),
      };
      final forwarding = RoutingDnsForwarding.compile(
        policy: dnsSettings.nonAddressPolicy,
        fixedProxyTag: allVpn ? selector.single : null,
      );
      outbounds.addAll(forwarding.outbounds);
      final sniffing = switch (settings.trafficMode) {
        TrafficMode.smart => settings.smart.sniffing,
        TrafficMode.custom => ordinary!.sniffing,
        TrafficMode.allVpn => const RoutingSniffingSettings(),
      };
      final selectionSettings = switch (settings.trafficMode) {
        TrafficMode.smart => settings.smart.selection,
        TrafficMode.custom => ordinary!.selection,
        TrafficMode.allVpn => const RoutingSelectionSettings(),
      };
      final selection = selectionSettings.compile(
        selector: selector,
        fallbackTag: selector.first,
      );
      final fakeDns = !allVpn && (ordinary?.fakeDns ?? settings.smart.fakeDns);
      dnsSettings.validate(
        directEnabled:
            !allVpn && (ordinary != null || settings.smart.directDns),
      );
      selectionSettings.validate();
      sniffing.validate(fakeDns: fakeDns);
      final dns = RoutingDns.compile(
        settings: dnsSettings,
        rules: allVpn ? const [] : rules,
        directEnabled:
            !allVpn && (ordinary != null || settings.smart.directDns),
        fakeDns: fakeDns,
        ipv6: options.ipv6,
      );
      dns.servers = [
        ...ManagedServerDialing.bootstrapServers(
          domains: bootstrapDomains,
          ipv4Address: options.tunDnsIpv4Address,
          ipv6Address: options.tunDnsIpv6Address,
          ipv6: options.ipv6,
        ),
        ...?dns.servers,
      ];
      final normal = XrayJson(
        env: XrayEnv(
          assetLocation: VpnConstants.datDir,
          certLocation: VpnConstants.datDir,
        ),
        inbounds: [
          _runtimeInbound(
            options,
            fakeDns: FakeDns.usesServer(dns),
            sniffing: sniffing,
          ),
          if (options.lanProxyEnabled)
            createLanProxyInbound(
              options.lanProxyPort,
              fakeDns: FakeDns.usesServer(dns),
              sniffing: sniffing,
            ),
        ],
        log: _runtimeLog(options),
        stats: XrayStats(),
        metrics: XrayMetrics(listen: '127.0.0.1:${options.metricsPort}'),
        policy: XrayPolicy(system: _runtimeStatsPolicy()),
        outbounds: outbounds,
        observatory: selection.observatory,
        dns: dns,
        fakedns: FakeDns.poolsFor(dns),
        routing: XrayRouting(
          domainStrategy: allVpn ? 'AsIs' : 'IPIfNonMatch',
          balancers: [selection.balancer],
          rules: [
            if (bootstrapDomains.isNotEmpty)
              XrayRoutingRule(
                ruleTag: ManagedServerDialing.dnsTag,
                inboundTag: [ManagedServerDialing.dnsTag],
                outboundTag: 'direct',
              ),
            ...forwarding.rules,
            XrayRoutingRule(
              ruleTag: 'app-default',
              inboundTag: [dnsProxy],
              balancerTag: 'proxy',
            ),
            if (!allVpn)
              XrayRoutingRule(
                ruleTag: 'app-direct-dns',
                inboundTag: [dnsDirect],
                outboundTag: 'direct',
              ),
            XrayRoutingRule(
              ruleTag: 'app-tunnel-dns',
              inboundTag: ['tunIn'],
              port: '53',
              outboundTag: dnsOutbound,
            ),
            XrayRoutingRule(
              ruleTag: 'app-tunnel-dot',
              inboundTag: ['tunIn'],
              port: '853',
              balancerTag: 'proxy',
            ),
            ...rules,
            if (selection.automatic)
              XrayRoutingRule(
                ruleTag: 'app-proxy-catchall',
                inboundTag: [
                  'tunIn',
                  if (options.lanProxyEnabled) lanProxyInboundTag,
                ],
                balancerTag: 'proxy',
              ),
          ],
        ),
      );
      config = normal.toJson();
    }
    return CompiledConnection(
      xrayJson: jsonEncode(config),
      entries: entries,
      finalExit: finalExit,
      nodeTags: nodeTags,
      profile: profile,
    );
  }

  static Map<String, dynamic> _node(ResolvedServer node, String tag) {
    final outbound = node.outbound;
    if (outboundDialerProxy(outbound)?.isNotEmpty == true ||
        outboundProxyTag(outbound)?.isNotEmpty == true) {
      throw const FormatException(
        'Normal nodes cannot reference other outbounds; use Raw for a complete configuration',
      );
    }
    return outbound
      ..remove('name')
      ..['tag'] = tag;
  }

  static Map<String, dynamic> _object(Map<String, dynamic> parent, String key) {
    final value = parent[key];
    if (value == null) return parent[key] = <String, dynamic>{};
    if (value is! Map<String, dynamic>) {
      throw FormatException('$key must be an object');
    }
    return parent[key] = Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _objects(
    Map<String, dynamic> parent,
    String key,
  ) {
    final value = parent[key] ?? <dynamic>[];
    if (value is! List || value.any((item) => item is! Map<String, dynamic>)) {
      throw FormatException('$key must be an object array');
    }
    return value.cast<Map<String, dynamic>>().toList();
  }

  static XrayInbound _runtimeInbound(
    RuntimeOptions options, {
    bool fakeDns = false,
    RoutingSniffingSettings sniffing = const RoutingSniffingSettings(),
  }) {
    if (options.usesWindowsSystemVpn) {
      return createSocksInbound(
        '${options.socksPort}',
        fakeDns: fakeDns,
        sniffing: sniffing,
      );
    }
    final nativeTun =
        options.platform == ConnectionPlatform.linux ||
        options.platform == ConnectionPlatform.windows;
    return createTunInbound(
      fakeDns: fakeDns,
      sniffing: sniffing,
      gateway: nativeTun
          ? ['198.18.0.1/15', if (options.ipv6) 'fc00::1/64']
          : null,
      dns: nativeTun
          ? [
              options.tunDnsIpv4Address,
              if (options.ipv6) options.tunDnsIpv6Address,
            ]
          : null,
      autoSystemRoutingTable: nativeTun
          ? ['0.0.0.0/0', if (options.ipv6) '::/0']
          : null,
      autoOutboundsInterface: nativeTun ? options.interfaceName : null,
      autoSystemWfpBlockLeak: options.platform == ConnectionPlatform.windows
          ? ['dns']
          : null,
    );
  }

  static XrayLog _runtimeLog(RuntimeOptions options) {
    final enabled = options.logEnabled && options.logFilesSupported;
    return XrayLog(
      access: enabled ? '${options.sessionDirectory}/access.log' : 'none',
      error: enabled ? '${options.sessionDirectory}/error.log' : 'none',
      logLevel: enabled ? options.logLevel : 'none',
      dnsLog: enabled && options.dnsLog,
      maskAddress: options.maskAddress,
    );
  }

  static XrayPolicySystem _runtimeStatsPolicy() => XrayPolicySystem(
    statsInboundUplink: true,
    statsInboundDownlink: true,
    statsOutboundUplink: false,
    statsOutboundDownlink: false,
  );

  static Map<String, dynamic> _fullRuntimeMap(
    Map<String, dynamic> source,
    RuntimeOptions options,
  ) => _rawRuntimeMap(
    VpnConfigAdapter.withDefaultDns(
      source,
      ipv4Address: options.tunDnsIpv4Address,
      ipv6Address: options.ipv6 ? options.tunDnsIpv6Address : null,
    ),
    options,
  );

  static Map<String, dynamic> _rawRuntimeMap(
    Map<String, dynamic> source,
    RuntimeOptions options, {
    bool includeLanProxy = false,
  }) {
    final config = JsonTool.copyMap(source);
    validateLocalDnsNetworkPolicy(
      config,
      requiresInterface:
          options.platform == ConnectionPlatform.windows ||
          options.platform == ConnectionPlatform.linux,
    );
    final outbounds = _objects(config, 'outbounds');
    final inbounds = _objects(config, 'inbounds');
    if (includeLanProxy) {
      validateLanProxyInbounds(inbounds, options.lanProxyPort);
    }
    for (final inbound in inbounds) {
      final tag = inbound['tag'];
      if (tag == 'tunIn') continue;
      if (inbound['protocol'] == 'tun') {
        throw const FormatException('Use the App-managed tunIn tunnel');
      }
      if (portIncludes(inbound['port'], options.metricsPort) ||
          (options.usesWindowsSystemVpn &&
              portIncludes(inbound['port'], options.socksPort))) {
        throw const FormatException(
          'Raw inbound conflicts with an App-managed port',
        );
      }
    }
    final managed = inbounds.where((value) => value['tag'] == 'tunIn').toList();
    if (managed.length > 1) {
      throw const FormatException('Only one App-managed tunIn is allowed');
    }
    final generated = _runtimeInbound(
      options,
      fakeDns: FakeDns.usedByRaw(config),
    ).toJson();
    if (managed.isEmpty) {
      inbounds.insert(0, generated);
    } else {
      final inbound = managed.single;
      if (options.usesWindowsSystemVpn) {
        final settings = inbound['protocol'] == 'socks'
            ? _object(inbound, 'settings')
            : <String, dynamic>{};
        settings.addAll(generated['settings'] as Map<String, dynamic>);
        for (final key in ['protocol', 'listen', 'port']) {
          inbound[key] = generated[key];
        }
        inbound['settings'] = settings;
      } else {
        if (inbound['protocol'] != 'tun') {
          throw const FormatException('tunIn must use the tun protocol');
        }
        final settings = _object(inbound, 'settings');
        final platform = generated['settings'] as Map<String, dynamic>;
        for (final key in const [
          'name',
          'mtu',
          'gateway',
          'dns',
          'autoSystemRoutingTable',
          'autoOutboundsInterface',
        ]) {
          if (platform.containsKey(key)) {
            settings[key] = platform[key];
          } else {
            settings.remove(key);
          }
        }
        // Raw may explicitly opt out or select additional core-side filters.
        if (platform.containsKey('autoSystemWfpBlockLeak')) {
          settings.putIfAbsent(
            'autoSystemWfpBlockLeak',
            () => platform['autoSystemWfpBlockLeak'],
          );
        }
      }
    }
    if (includeLanProxy) {
      inbounds.add(
        createLanProxyInbound(
          options.lanProxyPort,
          fakeDns: FakeDns.usedByRaw(config),
        ).toJson(),
      );
    }
    config['inbounds'] = inbounds;
    final env = _object(config, 'env');
    // File descriptors belong to this native session, never an imported graph.
    env.remove('xray.tun.fd');
    env.remove('XRAY_TUN_FD');
    env['xray.location.asset'] = VpnConstants.datDir;
    env['xray.location.cert'] = VpnConstants.datDir;
    config.remove(
      'geodata',
    ); // App controls installed files, never core-side remote downloads.
    config['log'] = _runtimeLog(options).toJson();
    config['stats'] = <String, dynamic>{};
    config['metrics'] = {'listen': '127.0.0.1:${options.metricsPort}'};
    final policy = _object(config, 'policy');
    final system = _object(policy, 'system');
    system.addAll(_runtimeStatsPolicy().toJson());
    final levels = policy['levels'];
    if (levels is Map<String, dynamic>) {
      for (final level in levels.values) {
        if (level is Map<String, dynamic>) {
          level['statsUserUplink'] = false;
          level['statsUserDownlink'] = false;
        }
      }
    }
    final dns = _object(config, 'dns');
    final queryStrategy = options.ipv6 ? 'UseIP' : 'UseIPv4';
    dns['queryStrategy'] = queryStrategy;
    for (final server in (dns['servers'] as List? ?? [])) {
      if (server is Map<String, dynamic>) {
        server['queryStrategy'] = queryStrategy;
      }
    }
    _applyOutboundPolicy(outbounds, options, raw: true);
    config['outbounds'] = outbounds;
    return config;
  }

  // Proxy payloads remain maps in both modes; only their App-owned network
  // fields are changed here, without decoding the full config into a model.
  static void _applyOutboundPolicy(
    List<Map<String, dynamic>> outbounds,
    RuntimeOptions options, {
    required bool raw,
  }) {
    for (final outbound in outbounds) {
      if (['blackhole', 'loopback', 'dns'].contains(outbound['protocol'])) {
        continue;
      }
      final stream = _object(outbound, 'streamSettings');
      final sockopt = _object(stream, 'sockopt');
      _applyInterfacePolicy(sockopt, options);
      if (!raw) {
        sockopt.remove('domainStrategy');
        final settings = outbound['settings'];
        if (settings is Map<String, dynamic>) {
          settings.remove('domainStrategy');
        }
      }
      if (sockopt.isEmpty) stream.remove('sockopt');
      if (stream.isEmpty) outbound.remove('streamSettings');
    }
  }

  static void _applyInterfacePolicy(
    Map<String, dynamic> sockopt,
    RuntimeOptions options,
  ) {
    if (options.platform == ConnectionPlatform.windows ||
        options.platform == ConnectionPlatform.linux) {
      sockopt['interface'] = options.interfaceName;
    } else {
      sockopt.remove('interface');
    }
  }

  static bool portIncludes(Object? value, int port) {
    if (value == null) return false;
    for (final part in '$value'.split(',')) {
      final ends = part.trim().split('-');
      final first = int.tryParse(ends.first);
      final last = int.tryParse(ends.last);
      if (first != null && last != null && first <= port && port <= last) {
        return true;
      }
    }
    return false;
  }
}
