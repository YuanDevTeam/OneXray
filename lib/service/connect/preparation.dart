import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/advanced/local_api/service.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/connect/platform_requirements.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:path/path.dart' as p;

Future<List<int>> allocateRuntimePorts(
  List<dynamic> rawInbounds, {
  List<int> excludePorts = const [],
  Future<List<int>> Function(int count, {List<int>? excludePorts})?
  getFreePorts,
}) async {
  final allocate = getFreePorts ?? AppHostApi().getFreePorts;
  for (var attempt = 0; attempt < 5; attempt++) {
    final candidates = await allocate(
      2,
      excludePorts: excludePorts.isEmpty ? null : excludePorts,
    );
    if (!rawInbounds.any(
      (entry) =>
          entry is Map &&
          candidates.any(
            (port) => ConnectionCompiler.portIncludes(entry['port'], port),
          ),
    )) {
      return candidates;
    }
  }
  throw const FormatException('Runtime ports are unavailable');
}

bool _inboundConflictsWithHttpApi(Map<String, dynamic> inbound, int port) {
  if (inbound['tag'] == 'tunIn' ||
      !ConnectionCompiler.portIncludes(inbound['port'], port)) {
    return false;
  }
  final protocol = '${inbound['protocol']}'.toLowerCase();
  if (protocol == 'tun' || protocol == 'wireguard') return false;
  final stream = inbound['streamSettings'];
  final transport = stream is Map
      ? '${stream['method'] ?? stream['network']}'.toLowerCase()
      : null;
  if (const ['kcp', 'mkcp', 'hysteria'].contains(transport)) {
    return false;
  }
  if (stream is Map && '${stream['security']}'.toLowerCase() == 'tls') {
    final tls = stream['tlsSettings'];
    final configuredAlpn = tls is Map ? tls['alpn'] : null;
    final alpn = configuredAlpn is String
        ? configuredAlpn.split(',')
        : configuredAlpn;
    if (const ['xhttp', 'splithttp'].contains(transport) &&
        alpn is List &&
        alpn.length == 1 &&
        alpn.single == 'h3') {
      return false;
    }
    // MASQUE selects TCP only when its TLS ALPN includes HTTP/2.
    if (transport == 'masque' &&
        (alpn == null || (alpn is List && !alpn.contains('h2')))) {
      return false;
    }
  }
  final settings = inbound['settings'];
  if (settings is Map &&
      const ['tunnel', 'dokodemo-door', 'shadowsocks'].contains(protocol)) {
    final network =
        settings['network'] ??
        (protocol == 'shadowsocks' ? null : settings['allowedNetwork']);
    final networks = network is String ? network.split(',') : network;
    if (networks is List &&
        (protocol != 'shadowsocks' || networks.isNotEmpty) &&
        !networks.any((value) => '$value'.toLowerCase() == 'tcp')) {
      return false;
    }
  }
  final listen = inbound['listen'];
  if (listen == null) return true;
  if (listen is! String) return false;
  var listenAddress = listen;
  if (listenAddress.startsWith('[') && listenAddress.endsWith(']')) {
    listenAddress = listenAddress.substring(1, listenAddress.length - 1);
  }
  listenAddress = listenAddress.trim();
  if (listenAddress.isEmpty || listenAddress == 'localhost') return true;
  final address = InternetAddress.tryParse(listenAddress);
  if (address == null) return false; // Unix sockets do not occupy the API port.
  var bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv6) {
    if (bytes.every((value) => value == 0)) {
      final sockopt = stream is Map ? stream['sockopt'] : null;
      return sockopt is! Map || sockopt['v6only'] != true;
    }
    if (bytes.take(10).every((value) => value == 0) &&
        bytes[10] == 255 &&
        bytes[11] == 255) {
      bytes = bytes.sublist(12);
    } else {
      return false;
    }
  }
  return bytes.every((value) => value == 0) ||
      (bytes[0] == 127 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 1);
}

/// Resolves and compiles without publishing settings or starting a VPN.
class ConnectionPreparation {
  final AppDatabase db;
  final ConnectionResolver resolver;
  final Future<List<int>> Function(int count, {List<int>? excludePorts})?
  getFreePorts;
  final LocalApiService _localApi;
  final Future<void> Function(Map<String, GeoDataType>) _requireDependencies;

  ConnectionPreparation({
    AppDatabase? db,
    ConnectionResolver? resolver,
    this.getFreePorts,
    LocalApiService? localApi,
    Future<void> Function(Map<String, GeoDataType>)? requireDependencies,
  }) : db = db ?? AppDatabase(),
       _localApi = localApi ?? LocalApiService.instance,
       _requireDependencies =
           requireDependencies ?? GeoDataService().requireDependencies,
       resolver =
           resolver ??
           ConnectionResolver(
             rows: () {
               final database = db ?? AppDatabase();
               return database.coreConfigDao.watchServers();
             },
           );

  Future<ConnectionRuntime> prepare(
    ConnectionConfiguration input, {
    Future<void>? cancelled,
    String? rawDraft,
    RoutingConfiguration? customDraft,
    Map<int, ResolvedServer> serverDrafts = const {},
    void Function(Set<int>)? onResolved,
  }) async {
    var configuration = input;
    var settings = input.connection;
    final policy = input.policy;
    final platform = connectionPlatform;
    ResolvedProfile? profile;
    CoreConfigData? profileRow;
    String? sourceMode;
    if (!settings.expert && settings.selection.kind == SelectionKind.server) {
      final id = settings.selection.id!;
      final selected = await db.coreConfigDao.searchRow(id);
      if (selected == null) {
        throw const ConnectionResolutionException(
          ConnectionResolutionFailure.selectionUnavailable,
        );
      }
      final active = await db.coreConfigDao.searchActiveServerRow(id);
      if (active == null) {
        throw const FormatException(
          'The selected configuration is incompatible with the subscription mode',
        );
      }
      if (selected.type == CoreConfigType.Remnawave.name) {
        profileRow = active;
        profile = ResolvedProfile.fromRow(active);
        onResolved?.call({profile.id});
      }
    } else if (!settings.expert &&
        settings.selection.kind == SelectionKind.source &&
        settings.selection.id! > 0) {
      final source = await db.subscriptionDao.searchRow(settings.selection.id!);
      if (source == null) {
        throw const FormatException('The selected subscription is unavailable');
      }
      sourceMode = source.mode;
    }
    await ConnectionPlatformRequirements(platform: platform)
        .ensureOutboundInterface(policy.xrayOutboundInterfaceName);
    final tun = policy.toTun(platform);
    String? raw = rawDraft;
    RoutingConfiguration? custom = customDraft;
    if (settings.expert && raw == null) {
      final row = settings.rawId == null
          ? null
          : await db.coreConfigDao.searchRow(settings.rawId!);
      if (row == null || row.type != 'raw') {
        throw const FormatException('Raw configuration is unavailable');
      }
      if (row.data == null) {
        throw const FormatException('Raw configuration is empty');
      }
      raw = utf8.decode(base64Decode(row.data!));
    } else if (profile == null &&
        !settings.expert &&
        settings.trafficMode == TrafficMode.custom &&
        custom == null) {
      final row = settings.customId == null
          ? null
          : await db.routingProfileDao.searchRow(settings.customId!);
      if (row == null) {
        throw const FormatException('Custom route is unavailable');
      }
      custom = CustomRoutingService.readConfiguration(row);
    }
    String? notice;
    List<ResolvedServer> entries = const [];
    if (profile == null) {
      ResolvedConnectionTarget target;
      try {
        target = await resolver.resolveTarget(
          settings,
          custom: custom,
          cancelled: cancelled,
        );
      } on ConnectionResolutionException catch (error) {
        if (settings.selection.kind == SelectionKind.server &&
            await db.coreConfigDao.searchActiveOutboundRow(
                  settings.selection.id!,
                ) ==
                null) {
          throw const FormatException(
            'The selected configuration is unavailable in the subscription mode',
          );
        }
        if (settings.selection.kind == SelectionKind.source &&
            settings.selection.id! > 0 &&
            (await db.subscriptionDao.searchRow(settings.selection.id!))
                    ?.mode !=
                sourceMode) {
          throw const FormatException('The selected subscription mode changed');
        }
        if (settings.selection.kind == SelectionKind.automatic ||
            !{
              ConnectionResolutionFailure.selectionUnavailable,
              ConnectionResolutionFailure.insufficientHealthyServers,
            }.contains(error.reason)) {
          rethrow;
        }
        final retryFromFixed = settings.selection.kind == SelectionKind.server;
        settings = ConnectionSettings.fromJson({
          ...settings.toJson(),
          'selection': const ServerSelection.automatic().toJson(),
        });
        // Preserve the existing ordinary-node retry for a failed fixed node.
        // Only automatic/source intent may introduce a provider target.
        target = retryFromFixed
            ? ResolvedConnectionTarget.entries(
                await resolver.resolve(
                  settings,
                  custom: custom,
                  cancelled: cancelled,
                ),
              )
            : await resolver.resolveTarget(
                settings,
                custom: custom,
                cancelled: cancelled,
              );
        configuration = ConnectionConfiguration(
          connection: settings,
          policy: policy,
        );
        notice = 'selectionReset';
      }
      entries = target.entries;
      profile = target.profile;
      profileRow = target.profileRow;
    }
    entries = [for (final entry in entries) serverDrafts[entry.id] ?? entry];
    onResolved?.call({
      for (final entry in entries) entry.id,
      if (profile != null) profile.id,
      if (profile == null && settings.finalExitId != null)
        settings.finalExitId!,
    });
    ResolvedServer? finalExit;
    if (profile == null && settings.finalExitId != null) {
      final row = await db.coreConfigDao.searchActiveOutboundRow(
        settings.finalExitId!,
      );
      if (row == null) throw const FormatException('Final exit is unavailable');
      finalExit = serverDrafts[row.id] ?? ResolvedServer.fromRow(row);
    }
    var regions = const RegionCatalog.empty();
    if (profile == null &&
        !settings.expert &&
        settings.trafficMode == TrafficMode.smart &&
        settings.smart.directRegions.isNotEmpty) {
      Future<Map<String, dynamic>> readIndex(String name) async => jsonDecode(
        await File(p.join(VpnConstants.datDir, '$name.json')).readAsString(),
      ) as Map<String, dynamic>;
      regions = RegionCatalog.fromJson(
        jsonDecode(await rootBundle.loadString(RegionCatalog.assetPath))
            as Map<String, dynamic>,
        geositeCodes: RegionCatalog.codesFromIndex(await readIndex('geosite')),
        geoipCodes: RegionCatalog.codesFromIndex(await readIndex('geoip')),
      );
    }
    final rawConfig = raw == null ? null : ConnectionCompiler.parseRawJson(raw);
    final userInbounds = profile != null
        ? profile.config['inbounds'] ?? []
        : rawConfig?['inbounds'] ?? custom?.toJson()['inbounds'] ?? [];
    if (userInbounds is! List ||
        userInbounds.any((entry) => entry is! Map<String, dynamic>)) {
      throw const FormatException('inbounds must be an object array');
    }
    final apiPort = await _localApi.reservedPort();
    if (apiPort != null) {
      var apiEnabled = _localApi.listening;
      try {
        apiEnabled = apiEnabled || (await _localApi.load()).enabled;
      } catch (_) {
        // An unavailable optional API preference must not block VPN startup.
      }
      if (apiEnabled &&
          userInbounds.cast<Map<String, dynamic>>().any(
            (inbound) => _inboundConflictsWithHttpApi(inbound, apiPort),
          )) {
        throw const FormatException(
          'Configuration inbound conflicts with the HTTP API port',
        );
      }
    }
    final shareLanProxy =
        profile == null && !settings.expert && policy.lanProxyEnabled;
    if (shareLanProxy && policy.lanProxyPort == apiPort) {
      throw const FormatException(
        'LAN proxy port conflicts with the HTTP API port',
      );
    }
    final ports = await allocateRuntimePorts(
      userInbounds.cast<Map<String, dynamic>>(),
      excludePorts: [?apiPort, if (shareLanProxy) policy.lanProxyPort],
      getFreePorts: getFreePorts,
    );
    final compiled = ConnectionCompiler.compile(
      settings: settings,
      entries: entries,
      finalExit: finalExit,
      raw: rawConfig,
      profile: profile,
      custom: profile == null ? custom : null,
      regions: regions,
      options: RuntimeOptions(
        platform: platform,
        sessionDirectory: VpnConstants.runDir,
        socksPort: ports[0],
        metricsPort: ports[1],
        lanProxyEnabled: shareLanProxy,
        lanProxyPort: policy.lanProxyPort,
        ipv6: policy.ipv6Enabled,
        dialing: policy.dialing,
        tunDnsIpv4Address: policy.dnsIpv4Address,
        tunDnsIpv6Address: policy.dnsIpv6Address,
        interfaceName: policy.xrayOutboundInterfaceName,
        logEnabled: policy.logEnabled,
        logLevel: policy.logLevel,
        dnsLog: policy.recordDns,
        maskAddress: policy.maskAddress,
      ),
    );
    await _requireDependencies(
      geoDataReferences(jsonDecode(compiled.xrayJson) as Map<String, dynamic>),
    );
    for (final server in [...entries, ?finalExit]) {
      final row = await db.coreConfigDao.searchActiveOutboundRow(server.id);
      if (row == null ||
          row.type != 'outbound' ||
          (!serverDrafts.containsKey(row.id) &&
              ResolvedServer.fromRow(row).outboundJson !=
                  server.outboundJson)) {
        throw const FormatException(
          'A selected server changed during preparation',
        );
      }
    }
    if (profileRow != null) {
      final current = await db.coreConfigDao.searchActiveServerRow(
        profileRow.id,
      );
      if (current == null ||
          current.type != profileRow.type ||
          current.subId != profileRow.subId ||
          current.data != profileRow.data ||
          current.name != profileRow.name) {
        throw const FormatException(
          'A selected provider configuration changed during preparation',
        );
      }
    }
    final request = StartVpnRequest(
      tun,
      platform == ConnectionPlatform.windows ||
              platform == ConnectionPlatform.ios
          ? '${ports[0]}'
          : null,
      '${ports[1]}',
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(compiled.xrayJson).toJson(),
        ).toJson(),
      ),
    );
    return ConnectionRuntime.create(
      configuration: configuration,
      compiled: compiled,
      platform: platform,
      request: request,
      notice: notice,
    );
  }
}
