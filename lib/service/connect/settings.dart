import 'package:onexray/service/connect/routing/options.dart';

enum ConnectionPlatform { ios, macos, android, windows, linux }

enum SelectionKind { automatic, source, server }

enum TrafficMode { smart, allVpn, custom }

class ServerSelection {
  final SelectionKind kind;
  final int? id;

  const ServerSelection.automatic() : kind = SelectionKind.automatic, id = null;
  const ServerSelection.server(int this.id) : kind = SelectionKind.server;
  const ServerSelection.source(int this.id) : kind = SelectionKind.source;

  factory ServerSelection.fromJson(Map<String, dynamic> value) {
    final kind = SelectionKind.values
        .where((kind) => kind.name == value['kind'])
        .firstOrNull;
    return switch (kind) {
      SelectionKind.automatic => const ServerSelection.automatic(),
      SelectionKind.server => ServerSelection.server(value['id'] as int),
      SelectionKind.source => ServerSelection.source(value['id'] as int),
      null => const ServerSelection.automatic(),
    };
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (id != null) 'id': id,
  };
}

class SmartRoutingSettings {
  final int entryCount;
  final int? finalExitId;
  final List<String> directRegions;
  final bool directPrivate;
  final bool directApple;
  final bool directWindows;
  final bool directDns;
  final RoutingDnsSettings dns;
  final RoutingSniffingSettings sniffing;
  final RoutingSelectionSettings selection;
  String get directDnsAddress => dns.directAddress;
  final bool fakeDns;
  final bool fragment;
  final bool blockAds;

  SmartRoutingSettings({
    this.entryCount = 1,
    this.finalExitId,
    Iterable<String> directRegions = const ['CN'],
    this.directPrivate = true,
    this.directApple = true,
    this.directWindows = true,
    this.directDns = true,
    String? directDnsAddress,
    RoutingDnsSettings dns = const RoutingDnsSettings(),
    this.sniffing = const RoutingSniffingSettings(),
    this.selection = const RoutingSelectionSettings(),
    this.fakeDns = false,
    this.fragment = false,
    this.blockAds = false,
  }) : dns = directDnsAddress == null
           ? dns
           : dns.withDirectAddress(directDnsAddress),
       directRegions = List.unmodifiable(directRegions) {
    if (entryCount < 1 || entryCount > 3) {
      throw const FormatException('Entry count must be 1–3');
    }
  }

  factory SmartRoutingSettings.fromJson(Map<String, dynamic> value) =>
      SmartRoutingSettings(
        entryCount: value['entryCount'] as int? ?? 1,
        finalExitId: value['finalExitId'] as int?,
        directRegions:
            (value['directRegions'] as List?)?.cast<String>() ?? ['CN'],
        directPrivate: value['directPrivate'] as bool? ?? true,
        directApple: value['directApple'] as bool? ?? true,
        directWindows: value['directWindows'] as bool? ?? true,
        directDns: value['directDns'] as bool? ?? true,
        directDnsAddress: value['directDnsAddress'] as String?,
        dns: RoutingDnsSettings.fromJson(
          value['dns'] as Map<String, dynamic>? ?? {},
        ),
        sniffing: RoutingSniffingSettings.fromJson(
          value['sniffing'] as Map<String, dynamic>? ?? {},
        ),
        selection: RoutingSelectionSettings.fromJson(
          value['selection'] as Map<String, dynamic>? ?? {},
        ),
        fakeDns: value['fakeDns'] as bool? ?? false,
        fragment: value['fragment'] as bool? ?? false,
        blockAds: value['blockAds'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'entryCount': entryCount,
    'finalExitId': finalExitId,
    'directRegions': directRegions,
    'directPrivate': directPrivate,
    'directApple': directApple,
    'directWindows': directWindows,
    'directDns': directDns,
    'dns': dns.toJson(),
    'sniffing': sniffing.toJson(),
    'selection': selection.toJson(),
    'fakeDns': fakeDns,
    'fragment': fragment,
    'blockAds': blockAds,
  };

  void validate() {
    dns.validate(directEnabled: directDns);
    sniffing.validate(fakeDns: fakeDns);
    selection.validate();
  }

  String get effectiveDirectDnsAddress =>
      directDns ? directDnsAddress.trim() : RoutingDnsSettings.defaultAddress;
}

/// Retains the normal selection while Raw is active. The coordinator stores
/// this value together with tunnel/log settings in one database transaction.
class ConnectionSettings {
  final bool expert;
  final int? rawId;
  final ServerSelection selection;
  final TrafficMode trafficMode;
  final int? customId;
  final SmartRoutingSettings smart;

  ConnectionSettings({
    this.expert = false,
    this.rawId,
    this.selection = const ServerSelection.automatic(),
    this.trafficMode = TrafficMode.smart,
    this.customId,
    SmartRoutingSettings? smart,
  }) : smart = smart ?? SmartRoutingSettings();

  factory ConnectionSettings.fromJson(Map<String, dynamic> value) =>
      ConnectionSettings(
        expert: value['expert'] as bool? ?? false,
        rawId: value['rawId'] as int?,
        selection: ServerSelection.fromJson(
          value['selection'] as Map<String, dynamic>? ?? {'kind': 'automatic'},
        ),
        trafficMode: TrafficMode.values.byName(
          value['trafficMode'] as String? ?? 'smart',
        ),
        customId: value['customId'] as int?,
        smart: SmartRoutingSettings.fromJson(
          value['smart'] as Map<String, dynamic>? ?? {},
        ),
      );

  Map<String, dynamic> toJson() => {
    'expert': expert,
    'rawId': rawId,
    'selection': selection.toJson(),
    'trafficMode': trafficMode.name,
    'customId': customId,
    'smart': smart.toJson(),
  };

  int requiredEntries({int? customEntryCount}) {
    if (expert) return 0;
    if (selection.kind == SelectionKind.server ||
        trafficMode == TrafficMode.allVpn) {
      return 1;
    }
    return switch (trafficMode) {
      TrafficMode.smart => smart.entryCount,
      TrafficMode.allVpn => 1,
      TrafficMode.custom =>
        customEntryCount ?? (throw StateError('Custom route is required')),
    };
  }

  int? get finalExitId =>
      !expert && trafficMode == TrafficMode.smart ? smart.finalExitId : null;
}
