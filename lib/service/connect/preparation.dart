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

/// Resolves and compiles without publishing settings or starting a VPN.
class ConnectionPreparation {
  final AppDatabase db;
  final ConnectionResolver resolver;
  final Future<List<int>> Function(int count, {List<int>? excludePorts})?
  getFreePorts;
  final Future<void> Function(Map<String, GeoDataType>) _requireDependencies;

  ConnectionPreparation({
    AppDatabase? db,
    ConnectionResolver? resolver,
    this.getFreePorts,
    Future<void> Function(Map<String, GeoDataType>)? requireDependencies,
  }) : db = db ?? AppDatabase(),
       _requireDependencies =
           requireDependencies ?? GeoDataService().requireDependencies,
       resolver =
           resolver ??
           ConnectionResolver(
             rows: () {
               final database = db ?? AppDatabase();
               return database.coreConfigDao.watchOutbounds();
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
        settings.selection.kind == SelectionKind.source) {
      final source = await db.subscriptionDao.searchRow(settings.selection.id!);
      if (source == null || source.mode != SubscriptionMode.appManaged.name) {
        throw const FormatException(
          'Choose an individual provider configuration',
        );
      }
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
      try {
        entries = await resolver.resolve(
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
            (await db.subscriptionDao.searchRow(settings.selection.id!))
                    ?.mode !=
                SubscriptionMode.appManaged.name) {
          throw const FormatException('The selected subscription mode changed');
        }
        if (settings.selection.kind == SelectionKind.automatic ||
            !{
              ConnectionResolutionFailure.selectionUnavailable,
              ConnectionResolutionFailure.insufficientHealthyServers,
            }.contains(error.reason)) {
          rethrow;
        }
        settings = ConnectionSettings.fromJson({
          ...settings.toJson(),
          'selection': const ServerSelection.automatic().toJson(),
        });
        entries = await resolver.resolve(
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
    final userInbounds =
        profile?.config['inbounds'] ??
        rawConfig?['inbounds'] ??
        custom?.toJson()['inbounds'] ??
        [];
    if (userInbounds is! List ||
        userInbounds.any((entry) => entry is! Map<String, dynamic>)) {
      throw const FormatException('inbounds must be an object array');
    }
    final apiPort = await LocalApiService.instance.reservedPort();
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
      custom: custom,
      regions: regions,
      options: RuntimeOptions(
        platform: platform,
        sessionDirectory: VpnConstants.runDir,
        socksPort: ports[0],
        metricsPort: ports[1],
        lanProxyEnabled: shareLanProxy,
        lanProxyPort: policy.lanProxyPort,
        ipv6: policy.ipv6Enabled,
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
