import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/connect/target_picker.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/raw/editor.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';

import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:onexray/pages/servers/catalog.dart';
import 'package:onexray/pages/shared/connection_action.dart';

const _unchanged = Object();

class ConnectPageState {
  ConnectPageState({
    ConnectionConfiguration? configuration,
    this.connectionView = const ConnectionView(),
    this.connectedMinutes = 0,
    ServerCatalog? catalog,
    List<CoreConfigData> raws = const [],
    List<RoutingConfiguration> customRoutes = const [],
    this.ready = false,
    this.failed = false,
    this.pendingChange,
  }) : configuration = configuration ?? ConnectionConfiguration(),
       catalog = catalog ?? ServerCatalog(),
       raws = List.unmodifiable(raws),
       customRoutes = List.unmodifiable(customRoutes);

  final ConnectionConfiguration configuration;
  final ConnectionView connectionView;
  final int connectedMinutes;
  final ServerCatalog catalog;
  List<CoreConfigData> get servers => catalog.servers;
  final List<CoreConfigData> raws;
  final List<RoutingConfiguration> customRoutes;
  List<SubscriptionData> get sources => catalog.sources;
  final bool ready;
  final bool failed;
  final String? pendingChange;

  ConnectPageState copyWith({
    ConnectionConfiguration? configuration,
    ConnectionView? connectionView,
    int? connectedMinutes,
    ServerCatalog? catalog,
    List<CoreConfigData>? raws,
    List<RoutingConfiguration>? customRoutes,
    bool? ready,
    bool? failed,
    Object? pendingChange = _unchanged,
  }) => ConnectPageState(
    configuration: configuration ?? this.configuration,
    connectionView: connectionView ?? this.connectionView,
    connectedMinutes: connectedMinutes ?? this.connectedMinutes,
    catalog: catalog ?? this.catalog,
    raws: raws ?? this.raws,
    customRoutes: customRoutes ?? this.customRoutes,
    ready: ready ?? this.ready,
    failed: failed ?? this.failed,
    pendingChange: identical(pendingChange, _unchanged)
        ? this.pendingChange
        : pendingChange as String?,
  );
  bool sameContentAs(ConnectPageState other) =>
      configuration == other.configuration &&
      catalog == other.catalog &&
      const ListEquality<CoreConfigData>().equals(raws, other.raws) &&
      const ListEquality<RoutingConfiguration>().equals(
        customRoutes,
        other.customRoutes,
      ) &&
      ready == other.ready &&
      failed == other.failed &&
      pendingChange == other.pendingChange &&
      connectedMinutes == other.connectedMinutes &&
      connectionView.phase == other.connectionView.phase &&
      connectionView.runtime == other.connectionView.runtime &&
      connectionView.issue == other.connectionView.issue &&
      connectionView.error == other.connectionView.error &&
      connectionView.permission == other.connectionView.permission;
}

class ConnectController extends PageCubit<ConnectPageState> with ServerLabels {
  ConnectController({
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
    Future<PlatformPermissionResult> Function()? requestPermission,
  }) : db = database ?? AppDatabase(),
       coordinator = coordinator ?? ConnectionCoordinator.instance,
       _requestPermission =
           requestPermission ?? AppHostApi().requestPlatformPermission,
       super(ConnectPageState()) {
    this.coordinator.state.addListener(_connectionChanged);
    _connectionChanged();
  }

  final AppDatabase db;
  final ConnectionCoordinator coordinator;
  final Future<PlatformPermissionResult> Function() _requestPermission;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _pageVisible = false;

  @override
  ServerCatalog get catalog => state.catalog;

  ConnectionConfiguration get configuration => state.configuration;
  set configuration(ConnectionConfiguration value) =>
      emit(state.copyWith(configuration: value));

  ConnectionView get connectionView => state.connectionView;
  List<CoreConfigData> get servers => state.servers;
  set servers(List<CoreConfigData> value) =>
      emit(state.copyWith(catalog: catalog.copyWith(servers: value)));
  List<CoreConfigData> get raws => state.raws;
  set raws(List<CoreConfigData> value) => emit(state.copyWith(raws: value));
  List<RoutingConfiguration> get customRoutes => state.customRoutes;
  set customRoutes(List<RoutingConfiguration> value) =>
      emit(state.copyWith(customRoutes: value));
  List<SubscriptionData> get sources => state.sources;
  set sources(List<SubscriptionData> value) =>
      emit(state.copyWith(catalog: catalog.copyWith(sources: value)));
  bool get ready => state.ready;
  set ready(bool value) => emit(state.copyWith(ready: value));
  bool get failed => state.failed;
  set failed(bool value) => emit(state.copyWith(failed: value));
  String? get pendingChange => state.pendingChange;
  set pendingChange(String? value) =>
      emit(state.copyWith(pendingChange: value));

  void _connectionChanged() {
    if (isPageActive) {
      final view = coordinator.state.value;
      emit(
        state.copyWith(
          connectionView: view,
          connectedMinutes: view.runtime == null
              ? 0
              : DateTime.now().difference(view.runtime!.startedAt).inMinutes,
        ),
      );
    }
  }

  void setPageVisible(bool visible) {
    if (!isPageActive || _pageVisible == visible) return;
    _pageVisible = visible;
    _syncTrafficVisibility();
  }

  void _syncTrafficVisibility() =>
      coordinator.setTrafficVisible(this, isPageActive && _pageVisible);

  Future<void> initialize() async {
    failed = false;
    try {
      if (!isPageActive) return;
      configuration = await coordinator.configuration;
      if (_subscriptions.isEmpty) {
        _subscriptions.add(
          db.connectionConfigDao.watch().listen((row) {
            configuration = ConnectionConfiguration.fromJson(
              jsonDecode(row.configurationJson) as Map<String, dynamic>,
            );
          }, onError: _readFailed),
        );
        _subscriptions.add(
          ServerCatalog.watch(db).listen((value) {
            emit(state.copyWith(catalog: value));
          }, onError: _readFailed),
        );
        _subscriptions.add(
          db.coreConfigDao.allRawRowsWithDataStream.listen((rows) {
            raws = rows;
          }, onError: _readFailed),
        );
        _subscriptions.add(
          db.routingProfileDao.allRowsStream.listen((rows) {
            final readable = <RoutingConfiguration>[];
            for (final row in rows) {
              try {
                readable.add(CustomRoutingService.readConfiguration(row));
              } catch (_) {
                // Row diagnostics belong to the routing page. An unrelated
                // damaged route must not block ordinary connection choices.
              }
            }
            customRoutes = readable;
          }, onError: _readFailed),
        );
      }
      ready = true;
    } catch (_) {
      failed = true;
    }
  }

  String selectionTitle(AppLocalizations l10n) {
    final settings = configuration.connection;
    if (settings.expert) {
      return raws.where((r) => r.id == settings.rawId).firstOrNull?.name ??
          l10n.prototypeNotSelected;
    }
    return _selectionName(l10n, settings.selection);
  }

  String _selectionName(AppLocalizations l, ServerSelection selection) =>
      selectionName(l, selection);

  int? _configuredEntryCount(ConnectionSettings settings) {
    if (settings.selection.kind == SelectionKind.server ||
        settings.trafficMode == TrafficMode.allVpn) {
      return 1;
    }
    if (settings.trafficMode == TrafficMode.smart) {
      return settings.smart.entryCount;
    }
    final profile = customRoutes
        .where((profile) => profile.id == settings.customId)
        .firstOrNull;
    return profile?.entryCount;
  }

  CoreConfigData? get selectedProvider =>
      !configuration.connection.expert &&
          configuration.connection.selection.kind == SelectionKind.server
      ? servers
            .where(
              (row) =>
                  row.id == configuration.connection.selection.id &&
                  row.type == CoreConfigType.Remnawave.name &&
                  catalog.selectable(row),
            )
            .firstOrNull
      : null;

  RuntimeProfile? get runningProfile => connectionView.runtime?.profile;
  bool get providerConfiguration =>
      runningProfile != null || selectedProvider != null;

  String selectionKindLabel(AppLocalizations l) =>
      configuration.connection.expert || selectedProvider != null
      ? l.serverCompleteConfigurationsTab
      : configuration.connection.selection.kind == SelectionKind.server
      ? l.serverSelectionFixedNode
      : l.serverSelectionAutomaticScope;

  int candidateCount(ServerSelection selection) {
    final settings = _ordinarySettings(configuration.connection);
    final seen = <int>{};
    return servers
        .where(
          (row) =>
              row.id > 0 &&
              seen.add(row.id) &&
              row.id != settings.finalExitId &&
              catalog.outboundEligible(row) &&
              switch (selection.kind) {
                SelectionKind.automatic => true,
                SelectionKind.source => row.subId == selection.id,
                SelectionKind.server => row.id == selection.id,
              },
        )
        .length;
  }

  String? fallbackMessage(AppLocalizations l) {
    final runtime = connectionView.runtime;
    final fallback = runtime?.selectionFallback;
    if (runtime == null ||
        fallback == null ||
        connectionView.phase != ConnectionPhase.connected) {
      return null;
    }
    return l.connectionScopeFallback(
      fallback.sourceName ?? _selectionName(l, fallback.originalSelection),
      runtime.profile?.name ?? runtime.entries.map((e) => e.name).join(' + '),
    );
  }

  String? selectionDetail(AppLocalizations l10n) {
    final settings = configuration.connection;
    if (settings.expert) return l10n.xrayRawPageTitle;
    if (selectedProvider != null) return l10n.providerConfigurationTitle;
    return '${l10n.connectionCandidates(candidateCount(settings.selection))} · ${l10n.connectionRequiredEntries(_configuredEntryCount(settings) ?? 1)}';
  }

  // The runtime chooses the node identity; the badge shows that node's latest
  // successful probe, not a measurement of this session or a new selection.
  String? selectionHealth(AppLocalizations l10n) {
    if (providerConfiguration) return null;
    final view = connectionView;
    if (view.phase != ConnectionPhase.connected) return null;
    final entries = view.runtime?.entries;
    if (entries == null || entries.isEmpty) return null;
    final id = entries.first.id;
    final row = servers.where((row) => row.id == id).firstOrNull;
    if (row == null || !PingDelayConstants.isSuccessful(row.delay)) {
      return null;
    }
    return health(l10n, row);
  }

  String homeMethodTitle(AppLocalizations l10n) =>
      configuration.connection.expert
      ? l10n.completeConfigurationRoutingTitle
      : providerConfiguration
      ? l10n.providerConfigurationTitle
      : configuration.connection.trafficMode == TrafficMode.smart
      ? l10n.prototypeSmartRoutingRecommended
      : methodTitle(l10n);

  int _ruleCount(RoutingConfiguration profile) => profile.ruleCount;

  String methodDescription(AppLocalizations l10n) {
    if (configuration.connection.expert) {
      return l10n.completeConfigurationRoutingNotice;
    }
    if (providerConfiguration) return l10n.providerRoutingNotice;
    switch (configuration.connection.trafficMode) {
      case TrafficMode.smart:
        return l10n.prototypeSmartRoutingDescription;
      case TrafficMode.allVpn:
        return l10n.prototypeAllViaVpnDescription;
      case TrafficMode.custom:
        final row = customRoutes
            .where((row) => row.id == configuration.connection.customId)
            .firstOrNull;
        final count = row == null ? null : _ruleCount(row);
        return count == null
            ? l10n.prototypeCustomRoutingDescription
            : l10n.prototypeCustomRuleCount(count);
    }
  }

  /// Only the active runtime metadata describes the path in use. Later
  /// asset renames, probes and subscription updates cannot change these labels.
  ({int entryCount, String path})? get runningRoute {
    final view = connectionView;
    final runtime = view.runtime;
    if (!view.canDisconnect ||
        runtime == null ||
        runtime.configuration.connection.expert ||
        runtime.profile != null) {
      return null;
    }
    final entries = runtime.entries;
    if (entries.isEmpty) return null;
    final names = entries.map((entry) => entry.name);
    final exit = runtime.finalExit;
    return (
      entryCount: entries.length,
      path: '${names.join(' + ')}${exit == null ? '' : ' → ${exit.name}'}',
    );
  }

  String methodTitle(AppLocalizations l10n) => providerConfiguration
      ? l10n.providerConfigurationTitle
      : switch (configuration.connection.trafficMode) {
          TrafficMode.smart => l10n.prototypeSmartRouting,
          TrafficMode.allVpn => l10n.prototypeAllViaVpn,
          TrafficMode.custom =>
            customRoutes
                    .where((row) => row.id == configuration.connection.customId)
                    .firstOrNull
                    ?.name ??
                l10n.prototypeCustomRouting,
        };

  Future<void> connectionAction(BuildContext context) async {
    final view = connectionView;
    if (view.busy) {
      coordinator.cancel();
      return;
    }
    if (pendingChange != null) return;
    // A command may await permission, status reads or the serial queue before
    // publishing a VPN phase. Acknowledge the tap without inventing that phase.
    pendingChange = 'connection';
    try {
      if (view.canDisconnect) {
        await run(context, coordinator.disconnect);
      } else {
        await run(context, () async {
          if (view.issue == 'permissionRequired' && view.permission != null) {
            final permission = await _requestPermission();
            if (permission.state != PlatformPermissionState.granted &&
                permission.state != PlatformPermissionState.notRequired) {
              throw ConnectionHostException(
                'permissionRequired',
                permission: permission,
                cause: permission.message,
              );
            }
          }
          await coordinator.connect();
        });
      }
    } finally {
      pendingChange = null;
    }
  }

  Future<bool> change(
    BuildContext context,
    Map<String, dynamic> values, {
    Future<void> Function()? writeAssets,
    Future<void> Function()? validateAssets,
    String? label,
  }) async {
    if (connectionView.busy || pendingChange != null) return false;
    if (providerConfiguration &&
        !values.containsKey('selection') &&
        !values.containsKey('expert') &&
        (values.containsKey('trafficMode') || values.containsKey('customId'))) {
      return false;
    }
    pendingChange = values.containsKey('rawId')
        ? 'raw:${values['rawId']}'
        : values.containsKey('selection')
        ? 'selection'
        : values.containsKey('trafficMode')
        ? 'method'
        : 'expert';
    try {
      if (validateAssets != null &&
          !await runConnectionAction(context, coordinator, validateAssets)) {
        return false;
      }
      if (!context.mounted || !isPageActive) return false;
      final current = await coordinator.configuration;
      if (!context.mounted || !isPageActive) return false;
      final next = ConnectionConfiguration(
        connection: ConnectionSettings.fromJson({
          ...current.connection.toJson(),
          ...values,
        }),
        policy: current.policy,
      );
      if (next.encode() == current.encode() && writeAssets == null) {
        configuration = current;
        return true;
      }
      final saved = await applyConnectionChange(
        context,
        coordinator,
        values,
        validateAssets: validateAssets,
        writeAssets: validateAssets == null
            ? writeAssets
            : () async {
                await validateAssets();
                await writeAssets?.call();
              },
        label: (next) =>
            label ?? _changeLabel(AppLocalizations.of(context)!, values, next),
      );
      if (saved == null) return false;
      configuration = saved;
      return true;
    } catch (error, stackTrace) {
      if (context.mounted && isPageActive) {
        await runConnectionAction(context, coordinator, () async {
          Error.throwWithStackTrace(error, stackTrace);
        });
      }
      return false;
    } finally {
      pendingChange = null;
    }
  }

  String _changeLabel(
    AppLocalizations l,
    Map<String, dynamic> values,
    ConnectionSettings next,
  ) {
    if (next.expert) {
      return raws.where((row) => row.id == next.rawId).firstOrNull?.name ??
          'Raw JSON';
    }
    if (values.containsKey('selection')) {
      return _selectionName(l, next.selection);
    }
    return switch (next.trafficMode) {
      TrafficMode.smart => l.prototypeSmartRoutingRecommended,
      TrafficMode.allVpn => l.prototypeAllViaVpn,
      TrafficMode.custom =>
        customRoutes
                .where((row) => row.id == next.customId)
                .firstOrNull
                ?.name ??
            l.prototypeCustomRouting,
    };
  }

  Future<void> selectRaw(BuildContext context, int id) async {
    await change(
      context,
      {'expert': true, 'rawId': id},
      validateAssets: () async {
        await RawEditorService(
          database: db,
          coordinator: coordinator,
        ).validateSelection(id);
      },
    );
  }

  Future<void> _validateSelection(ServerSelection selection) async {
    await ServerAssetService(
      database: db,
      coordinator: coordinator,
    ).validateSelection(selection);
    if (selection.kind == SelectionKind.source && selection.id! > 0) {
      final source = await db.subscriptionDao.searchRow(selection.id!);
      if (source?.mode != SubscriptionMode.appManaged.name) {
        throw const FormatException('The selected subscription mode changed');
      }
    }
    if (selection.kind == SelectionKind.server) {
      final settings = _ordinarySettings(
        (await coordinator.configuration).connection,
      );
      if (selection.id == settings.finalExitId &&
          (await db.coreConfigDao.searchActiveServerRow(selection.id!))?.type ==
              CoreConfigType.outbound.name) {
        throw const ConnectionResolutionException(
          ConnectionResolutionFailure.selfReference,
        );
      }
    }
  }

  Future<void> addServers(BuildContext context) =>
      context.pushScoped(AppPageDestination.serversImport);
  Future<void> editRaw(BuildContext context, [int? id]) =>
      context.pushScoped(AppPageDestination.rawEditor, extra: id);
  Future<void> chooseServer(BuildContext context) async {
    if (connectionView.busy || pendingChange != null) return;
    final l = AppLocalizations.of(context)!;
    final choice = await showConnectDialog<ConnectionTargetChoice>(
      context,
      (_) => ConnectionTargetPicker(
        settings: configuration.connection,
        catalog: catalog,
        raws: raws,
        candidateCount: candidateCount,
        selectionName: (s) => _selectionName(l, s),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice.manage) {
      await context.pushScoped(AppPageDestination.servers);
    } else if (choice.restore) {
      OrdinaryPlanRestore? restored;
      if (!await runConnectionAction(context, coordinator, () async {
        restored = await coordinator.restoreOrdinaryPlan();
      })) {
        return;
      }
      final plan = restored;
      if (!context.mounted || plan == null) return;
      final selection = plan.configuration.connection.selection;
      if (await change(context, {
            'expert': false,
            'selection': selection.toJson(),
          }, validateAssets: () => _validateSelection(selection)) &&
          plan.requiresSelection &&
          context.mounted) {
        ContextAlert.showToast(context, l.connectionRememberedPlanUnavailable);
      }
    } else if (choice.rawId != null) {
      await selectRaw(context, choice.rawId!);
    } else if (choice.selection != null) {
      final selection = choice.selection!;
      await change(context, {
        'expert': false,
        'selection': selection.toJson(),
      }, validateAssets: () => _validateSelection(selection));
    }
  }

  Future<void> chooseTrafficMethod(BuildContext context) =>
      context.pushScoped(AppPageDestination.routing);

  Future<void> showWhy(BuildContext context) async {
    final view = connectionView;
    final runtime = view.runtime;
    if (!view.canDisconnect || runtime == null) return;
    final settings = runtime.configuration.connection;
    final l = AppLocalizations.of(context)!;
    if (runtime.profile != null || settings.expert) {
      await showConnectDialog<void>(
        context,
        (dialogContext) => ConnectDialog(
          title: l.prototypeWhyConnectionTitle,
          body: Padding(
            padding: const EdgeInsets.all(22),
            child: ConnectExplanation(
              icon: LucideIcons.shieldCheck,
              text: settings.expert
                  ? l.prototypeRawManagedSettingsNotice
                  : l.providerRoutingNotice,
            ),
          ),
          actions: [
            ConnectDialogButton(
              label: l.prototypeDone,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      );
      return;
    }
    final names = runtime.entries.map((entry) => entry.name).toList();
    final entryNames = names.join(' + ');
    final exit = runtime.finalExit?.name;
    final methodReason = names.isEmpty
        ? l.prototypeNoAvailableEntries
        : switch (settings.trafficMode) {
            TrafficMode.smart =>
              exit == null
                  ? l.prototypeSmartConnectionReason(entryNames)
                  : l.prototypeSmartConnectionChainReason(entryNames, exit),
            TrafficMode.allVpn => l.prototypeAllVpnConnectionReason(entryNames),
            TrafficMode.custom => l.prototypeCustomConnectionReason,
          };
    final selectionReason = names.isEmpty
        ? null
        : l.prototypeRunningEntriesReason(entryNames);
    await showConnectDialog<void>(
      context,
      (dialogContext) => ConnectDialog(
        title: l.prototypeWhyConnectionTitle,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 4),
              child: Column(
                children: [
                  ConnectExplanation(
                    icon: LucideIcons.shieldCheck,
                    text: methodReason,
                  ),
                  if (selectionReason != null) ...[
                    const SizedBox(height: 15),
                    ConnectExplanation(
                      icon: LucideIcons.wifi,
                      text: selectionReason,
                    ),
                  ],
                ],
              ),
            ),
            ConnectCallout(
              icon: LucideIcons.lockKeyhole,
              text: l.prototypeNoAnalyticsLocalLogs,
            ),
          ],
        ),
        actions: [
          ConnectDialogButton(
            label: l.prototypeDone,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  ConnectionSettings _ordinarySettings(ConnectionSettings settings) =>
      ConnectionSettings.fromJson({...settings.toJson(), 'expert': false});

  Future<void> run(BuildContext context, Future<void> Function() action) async {
    await runConnectionAction(context, coordinator, action);
  }

  void _readFailed(Object error) {
    failed = true;
  }

  @override
  Future<void> disposePageResources() async {
    _syncTrafficVisibility();
    coordinator.state.removeListener(_connectionChanged);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
