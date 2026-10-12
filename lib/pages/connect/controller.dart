import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/raw/editor.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';

import 'package:onexray/service/servers/catalog.dart';
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
    this.expertView = false,
    this.ready = false,
    this.failed = false,
    this.pendingChange,
    Set<int> deletingRawIds = const {},
  }) : configuration = configuration ?? ConnectionConfiguration(),
       catalog = catalog ?? ServerCatalog(),
       raws = List.unmodifiable(raws),
       customRoutes = List.unmodifiable(customRoutes),
       deletingRawIds = Set.unmodifiable(deletingRawIds);

  final ConnectionConfiguration configuration;
  final ConnectionView connectionView;
  final int connectedMinutes;
  final ServerCatalog catalog;
  List<CoreConfigData> get servers => catalog.servers;
  final List<CoreConfigData> raws;
  final List<RoutingConfiguration> customRoutes;
  List<SubscriptionData> get sources => catalog.sources;
  final bool expertView;
  final bool ready;
  final bool failed;
  final String? pendingChange;
  final Set<int> deletingRawIds;

  ConnectPageState copyWith({
    ConnectionConfiguration? configuration,
    ConnectionView? connectionView,
    int? connectedMinutes,
    ServerCatalog? catalog,
    List<CoreConfigData>? raws,
    List<RoutingConfiguration>? customRoutes,
    bool? expertView,
    bool? ready,
    bool? failed,
    Object? pendingChange = _unchanged,
    Set<int>? deletingRawIds,
  }) => ConnectPageState(
    configuration: configuration ?? this.configuration,
    connectionView: connectionView ?? this.connectionView,
    connectedMinutes: connectedMinutes ?? this.connectedMinutes,
    catalog: catalog ?? this.catalog,
    raws: raws ?? this.raws,
    customRoutes: customRoutes ?? this.customRoutes,
    expertView: expertView ?? this.expertView,
    ready: ready ?? this.ready,
    failed: failed ?? this.failed,
    pendingChange: identical(pendingChange, _unchanged)
        ? this.pendingChange
        : pendingChange as String?,
    deletingRawIds: deletingRawIds ?? this.deletingRawIds,
  );
  bool sameContentAs(ConnectPageState other) =>
      configuration == other.configuration &&
      catalog == other.catalog &&
      const ListEquality<CoreConfigData>().equals(raws, other.raws) &&
      const ListEquality<RoutingConfiguration>().equals(
        customRoutes,
        other.customRoutes,
      ) &&
      const SetEquality<int>().equals(deletingRawIds, other.deletingRawIds) &&
      expertView == other.expertView &&
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
  ConnectController({AppDatabase? database, ConnectionCoordinator? coordinator})
    : db = database ?? AppDatabase(),
      coordinator = coordinator ?? ConnectionCoordinator.instance,
      super(ConnectPageState()) {
    this.coordinator.state.addListener(_connectionChanged);
    _connectionChanged();
  }

  final AppDatabase db;
  final ConnectionCoordinator coordinator;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _viewInitialized = false;
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
  bool get expertView => state.expertView;
  set expertView(bool value) => emit(state.copyWith(expertView: value));
  bool get ready => state.ready;
  set ready(bool value) => emit(state.copyWith(ready: value));
  bool get failed => state.failed;
  set failed(bool value) => emit(state.copyWith(failed: value));
  String? get pendingChange => state.pendingChange;
  set pendingChange(String? value) =>
      emit(state.copyWith(pendingChange: value));
  Set<int> get deletingRawIds => state.deletingRawIds;

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
      if (!_viewInitialized) expertView = configuration.connection.expert;
      _viewInitialized = true;
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
            try {
              customRoutes = rows
                  .map(CustomRoutingService.readConfiguration)
                  .toList();
            } catch (error) {
              _readFailed(error);
              return;
            }
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
    if (settings.trafficMode != TrafficMode.allVpn &&
        settings.selection.kind != SelectionKind.server) {
      final count = runningRoute?.entryCount ?? _configuredEntryCount(settings);
      if (count != null) {
        return count == 1
            ? l10n.prototypeAutomaticOneEntry
            : l10n.prototypeAutomaticEntries(count);
      }
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

  String? selectionDetail(AppLocalizations l10n) =>
      runningRoute?.path ??
      (configuration.connection.selection.kind == SelectionKind.server
          ? null
          : l10n.prototypeChooseBySpeedAvailability);

  // The runtime chooses the node identity; the badge shows that node's latest
  // successful probe, not a measurement of this session or a new selection.
  String? selectionHealth(AppLocalizations l10n) {
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
      configuration.connection.trafficMode == TrafficMode.smart
      ? l10n.prototypeSmartRoutingRecommended
      : methodTitle(l10n);

  int _ruleCount(RoutingConfiguration profile) => profile.ruleCount;

  String methodDescription(AppLocalizations l10n) {
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
    if (view.phase != ConnectionPhase.connected ||
        runtime == null ||
        runtime.configuration.connection.expert) {
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

  String methodTitle(AppLocalizations l10n) =>
      switch (configuration.connection.trafficMode) {
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
    if (!view.canDisconnect && expertView && !configuration.connection.expert) {
      if (raws.isEmpty) {
        await editRaw(context);
        return;
      }
      ContextAlert.showToast(
        context,
        AppLocalizations.of(context)!.prototypeChooseRawConfiguration,
      );
      return;
    }
    // A command may await permission, status reads or the serial queue before
    // publishing a VPN phase. Acknowledge the tap without inventing that phase.
    pendingChange = 'connection';
    try {
      if (view.canDisconnect) {
        await run(context, coordinator.disconnect);
      } else {
        await run(context, () async {
          if (view.issue == 'permissionRequired' && view.permission != null) {
            await AppHostApi().requestPlatformPermission();
          }
          await coordinator.connect();
        });
      }
    } finally {
      pendingChange = null;
    }
  }

  Future<void> toggleExpert(BuildContext context, bool value) async {
    if (connectionView.busy || pendingChange != null) return;
    if (!value && configuration.connection.expert) {
      if (!await change(context, {'expert': false})) return;
    }
    expertView = value;
  }

  Future<bool> change(
    BuildContext context,
    Map<String, dynamic> values, {
    Future<void> Function()? writeAssets,
    String? label,
  }) async {
    if (connectionView.busy || pendingChange != null) return false;
    pendingChange = values.containsKey('rawId')
        ? 'raw:${values['rawId']}'
        : values.containsKey('selection')
        ? 'selection'
        : values.containsKey('trafficMode')
        ? 'method'
        : 'expert';
    try {
      final saved = await applyConnectionChange(
        context,
        coordinator,
        values,
        writeAssets: writeAssets,
        label: (next) =>
            label ?? _changeLabel(AppLocalizations.of(context)!, values, next),
      );
      if (saved == null) return false;
      configuration = saved;
      return true;
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
    await change(context, {'expert': true, 'rawId': id});
  }

  Future<void> deleteRaw(BuildContext context, CoreConfigData row) async {
    if (connectionView.busy ||
        pendingChange != null ||
        deletingRawIds.contains(row.id)) {
      return;
    }
    emit(state.copyWith(deletingRawIds: {...deletingRawIds, row.id}));
    try {
      await run(context, () async {
        var active = false;
        final deleted =
            await RawEditorService(
              database: db,
              coordinator: coordinator,
            ).delete(
              row,
              confirm: (selected, reconnect, disconnect) async {
                if (!context.mounted) return false;
                active = selected;
                final l10n = AppLocalizations.of(context)!;
                return await showDestructiveConfirmationDialog(
                      context,
                      title: l10n.prototypeDeleteRawQuestion,
                      subtitle: row.name,
                      warning: disconnect
                          ? l10n.prototypeRawDeleteDisconnectNotice
                          : selected
                          ? l10n.prototypeActiveRawDeleteNotice
                          : l10n.prototypeRawDeleteNotice,
                      confirmLabel: disconnect
                          ? l10n.prototypeDeleteAndDisconnect
                          : reconnect
                          ? l10n.prototypeDeleteAndReconnect
                          : l10n.prototypeDelete,
                    ) &&
                    context.mounted;
              },
            );
        if (deleted && active) expertView = false;
      });
    } finally {
      emit(state.copyWith(deletingRawIds: {...deletingRawIds}..remove(row.id)));
    }
  }

  Future<void> addServers(BuildContext context) =>
      context.pushScoped(AppPageDestination.serversImport);
  Future<void> editRaw(BuildContext context, [int? id]) =>
      context.pushScoped(AppPageDestination.rawEditor, extra: id);
  Future<void> chooseServer(BuildContext context) =>
      context.pushScoped(AppPageDestination.servers);

  Future<void> showRawActions(BuildContext context, CoreConfigData row) async {
    if (deletingRawIds.contains(row.id)) return;
    final edit = await showConnectDialog<bool>(context, (dialogContext) {
      final l = AppLocalizations.of(dialogContext)!;
      final palette = ColorManager.palette(dialogContext);
      return ConnectDialog(
        title: row.name,
        body: ListTileTheme(
          data: AppTheme.actionListTile,
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  LucideIcons.pencil,
                  color: palette.primary,
                  size: 20,
                ),
                title: Text(
                  l.prototypeEditRawJson,
                  style: AppTypography.dialogGroupTitle,
                ),
                trailing: const Icon(LucideIcons.chevronRightDir, size: 18),
                onTap: () => Navigator.of(dialogContext).pop(true),
              ),
              Divider(height: 1, color: palette.border),
              ListTile(
                enabled: !connectionView.busy,
                leading: Icon(
                  LucideIcons.trash2,
                  color: palette.destructive,
                  size: 20,
                ),
                title: Text(
                  l.prototypeDelete,
                  style: AppTypography.dialogGroupTitle.copyWith(
                    color: palette.destructive,
                  ),
                ),
                trailing: Icon(
                  LucideIcons.chevronRightDir,
                  color: palette.destructive,
                  size: 18,
                ),
                onTap: () => Navigator.of(dialogContext).pop(false),
              ),
            ],
          ),
        ),
      );
    });
    if (!context.mounted || edit == null) return;
    if (edit) {
      await editRaw(context, row.id);
    } else {
      await deleteRaw(context, row);
    }
  }

  Future<void> chooseTrafficMethod(BuildContext context) async {
    final selected = await showConnectDialog<ConnectTrafficChoice>(
      context,
      (context) => ConnectTrafficMethodDialog(
        current: configuration.connection,
        customRoutes: [
          for (final profile in customRoutes)
            (
              id: profile.id!,
              name: profile.name,
              ruleCount: _ruleCount(profile),
              advanced: profile.advanced,
            ),
        ],
      ),
    );
    if (selected != null && context.mounted) {
      if (selected.edit) {
        var destination = AppPageDestination.smartRouting;
        if (selected.mode == TrafficMode.custom) {
          final advanced = selected.id == null
              ? await showCustomRoutingModeDialog(context)
              : customRoutes
                    .firstWhere((profile) => profile.id == selected.id)
                    .advanced;
          if (advanced == null || !context.mounted) return;
          destination = advanced
              ? AppPageDestination.advancedRouting
              : AppPageDestination.customRouting;
        }
        if (!context.mounted) return;
        await context.pushScoped(destination, extra: selected.id);
        return;
      }
      await change(context, {
        'trafficMode': selected.mode.name,
        'customId': selected.id,
      });
    }
  }

  Future<void> showWhy(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final view = connectionView;
    final connected = view.phase == ConnectionPhase.connected;
    final runtime = connected ? view.runtime : null;
    final settings =
        runtime?.configuration.connection ?? configuration.connection;
    final names = connected
        ? (runtime?.entries ?? const <RuntimeNode>[])
              .map((entry) => entry.name)
              .toList()
        : _previewEntries(settings).map((row) => serverName(row)).toList();
    final entryNames = names.join(' + ');
    final exit = connected
        ? runtime?.finalExit?.name
        : servers
              .where((row) => row.id == settings.finalExitId)
              .map(serverName)
              .firstOrNull;
    final custom = customRoutes
        .where((row) => row.id == settings.customId)
        .firstOrNull;
    final methodReason = names.isEmpty
        ? l.prototypeNoAvailableEntries
        : switch (settings.trafficMode) {
            TrafficMode.smart =>
              exit == null
                  ? l.prototypeSmartConnectionReason(entryNames)
                  : l.prototypeSmartConnectionChainReason(entryNames, exit),
            TrafficMode.allVpn => l.prototypeAllVpnConnectionReason(entryNames),
            TrafficMode.custom =>
              custom == null
                  ? l.prototypeCustomConnectionReason
                  : l.prototypeNamedCustomConnectionReason(custom.name),
          };
    final selectionReason = names.isEmpty
        ? null
        : connected
        ? l.prototypeRunningEntriesReason(entryNames)
        : names.length > 1
        ? l.prototypeMultipleEntriesReason(names.length)
        : switch (settings.selection.kind) {
            SelectionKind.server => l.prototypeFixedEntryReason(entryNames),
            _ => l.prototypeAutomaticEntryReason(entryNames),
          };
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

  /// Explain existing successful measurements without probing or selecting a
  /// runtime input. The actual connection still resolves through the coordinator.
  List<CoreConfigData> _previewEntries(ConnectionSettings settings) {
    final count = _configuredEntryCount(settings);
    if (count == null || settings.expert) return [];
    final rows =
        servers.where((row) {
          if (row.type != 'outbound' ||
              row.id <= 0 ||
              row.id == settings.finalExitId ||
              !PingDelayConstants.isSuccessful(row.delay)) {
            return false;
          }
          final matches = switch (settings.selection.kind) {
            SelectionKind.automatic => true,
            SelectionKind.source => row.subId == settings.selection.id,
            SelectionKind.server => row.id == settings.selection.id,
          };
          if (!matches) return false;
          return catalog.display(row).readable;
        }).toList()..sort((a, b) {
          final delay = a.delay.compareTo(b.delay);
          return delay == 0 ? a.id.compareTo(b.id) : delay;
        });
    return rows.length < count ? [] : rows.take(count).toList();
  }

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
