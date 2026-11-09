import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/advanced/xray/config/params.dart';
import 'package:onexray/pages/shared/connection_action.dart';
import 'package:onexray/pages/servers/catalog.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/manual_groups.dart';
import 'package:onexray/pages/servers/manual_group_dialogs.dart';
import 'package:onexray/service/servers/sort.dart';
import 'package:onexray/pages/servers/order/controller.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/failure.dart';

import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/shared/share/params.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/servers/subscription/format_confirmation.dart';
import 'package:onexray/pages/servers/raw_copy_dialog.dart';
import 'package:onexray/pages/servers/sources.dart';
import 'package:onexray/pages/servers/subscription/params.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/raw/editor.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/subscription/failure.dart';
import 'package:onexray/service/servers/subscription/model.dart';

export 'catalog.dart';

enum ServerAction { edit, test, copy, share, move, delete }

enum SourceAction { update, edit, share, delete }

class ServerGroupParams {
  final ServersController controller;
  final String groupId;
  const ServerGroupParams(this.controller, this.groupId);
}

const _unchanged = Object();

typedef PendingServerTest = ({String? groupId, bool cancelling});

class ServersPageState {
  ServersPageState({
    ConnectionConfiguration? configuration,
    this.connectionView = const ConnectionView(),
    ServerCatalog? catalog,
    this.ready = false,
    this.failed = false,
    this.failure,
    this.serverSearchQuery = '',
    Set<String> pendingServerActions = const {},
    Map<Object, PendingServerTest> serverTests = const {},
    Set<int> favoritingServerIds = const {},
    this.selectingServers,
    this.sortSaving = false,
    Map<int, String> sourceErrors = const {},
    List<CoreConfigData> rawConfigurations = const [],
  }) : configuration = configuration ?? ConnectionConfiguration(),
       catalog = catalog ?? ServerCatalog(),
       pendingServerActions = Set.unmodifiable(pendingServerActions),
       serverTests = Map.unmodifiable(serverTests),
       favoritingServerIds = Set.unmodifiable(favoritingServerIds),
       sourceErrors = Map.unmodifiable(sourceErrors),
       rawConfigurations = List.unmodifiable(rawConfigurations);

  final ConnectionConfiguration configuration;
  final ConnectionView connectionView;
  List<CoreConfigData> get servers => catalog.servers;
  List<SubscriptionData> get sources => catalog.sources;
  final ServerCatalog catalog;
  final bool ready;
  final bool failed;
  final Object? failure;

  final String serverSearchQuery;
  final Set<String> pendingServerActions;
  final Map<Object, PendingServerTest> serverTests;
  final Set<int> favoritingServerIds;
  final ServerSelection? selectingServers;
  final bool sortSaving;
  final Map<int, String> sourceErrors;
  final List<CoreConfigData> rawConfigurations;

  ServersPageState copyWith({
    ConnectionConfiguration? configuration,
    ConnectionView? connectionView,
    ServerCatalog? catalog,
    bool? ready,
    bool? failed,
    Object? failure,
    String? serverSearchQuery,
    Set<String>? pendingServerActions,
    Map<Object, PendingServerTest>? serverTests,
    Set<int>? favoritingServerIds,
    Object? selectingServers = _unchanged,
    bool? sortSaving,
    Map<int, String>? sourceErrors,
    List<CoreConfigData>? rawConfigurations,
  }) => ServersPageState(
    configuration: configuration ?? this.configuration,
    connectionView: connectionView ?? this.connectionView,
    catalog: catalog ?? this.catalog,
    ready: ready ?? this.ready,
    failed: failed ?? this.failed,
    failure: failed == false ? null : failure ?? this.failure,
    serverSearchQuery: serverSearchQuery ?? this.serverSearchQuery,
    pendingServerActions: pendingServerActions ?? this.pendingServerActions,
    serverTests: serverTests ?? this.serverTests,
    favoritingServerIds: favoritingServerIds ?? this.favoritingServerIds,
    selectingServers: identical(selectingServers, _unchanged)
        ? this.selectingServers
        : selectingServers as ServerSelection?,
    sortSaving: sortSaving ?? this.sortSaving,
    sourceErrors: sourceErrors ?? this.sourceErrors,
    rawConfigurations: rawConfigurations ?? this.rawConfigurations,
  );
}

class ServersController extends PageCubit<ServersPageState>
    with ServerLabels, ServerGroups {
  static const mainListTestGroupId = 'main-list';

  ServersController({
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
    ServerAssetService? assets,
    PingService? ping,
  }) : db = database ?? AppDatabase(),
       coordinator = coordinator ?? ConnectionCoordinator.instance,
       _ping = ping ?? PingService(),
       super(ServersPageState()) {
    this.assets =
        assets ??
        ServerAssetService(database: db, coordinator: this.coordinator);
    this.coordinator.state.addListener(_connectionChanged);
    _connectionChanged();
    search.addListener(_searchChanged);
  }
  final AppDatabase db;
  final ConnectionCoordinator coordinator;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  @override
  ServerCatalog get catalog => state.catalog;
  @override
  String get query => state.serverSearchQuery;
  set servers(List<CoreConfigData> rows) =>
      emit(state.copyWith(catalog: catalog.copyWith(servers: rows)));
  set sources(List<SubscriptionData> rows) =>
      emit(state.copyWith(catalog: catalog.copyWith(sources: rows)));
  set manualGroups(List<ManualServerGroupData> rows) =>
      emit(state.copyWith(catalog: catalog.copyWith(manualGroups: rows)));
  ConnectionConfiguration get configuration => state.configuration;
  set configuration(ConnectionConfiguration value) =>
      emit(state.copyWith(configuration: value));
  List<CoreConfigData> get rawConfigurations => state.rawConfigurations;
  ConnectionView get connectionView => state.connectionView;
  bool get ready => state.ready;
  set ready(bool value) => emit(state.copyWith(ready: value));
  bool get failed => state.failed;

  void _connectionChanged() {
    final next = coordinator.state.value;
    if (next.phase != connectionView.phase ||
        next.runtime != connectionView.runtime) {
      emit(state.copyWith(connectionView: next));
    }
  }

  Future<void> initialize() async {
    emit(state.copyWith(failed: false));
    try {
      if (!isPageActive) return;
      configuration = await coordinator.configuration;
      if (_subscriptions.isEmpty) {
        _subscriptions.add(
          ServerCatalog.watch(db).listen(
            (value) => emit(state.copyWith(catalog: value)),
            onError: _readFailed,
          ),
        );
        _subscriptions.add(
          db.coreConfigDao.allRawRowsWithDataStream.listen(
            (rows) => emit(state.copyWith(rawConfigurations: rows)),
            onError: _readFailed,
          ),
        );
        _subscriptions.add(
          db.connectionConfigDao.watch().listen((row) {
            configuration = ConnectionConfiguration.fromJson(
              jsonDecode(row.configurationJson) as Map<String, dynamic>,
            );
          }, onError: _readFailed),
        );
      }
      ready = true;
    } catch (error) {
      _readFailed(error);
    }
  }

  void _readFailed(Object error) =>
      emit(state.copyWith(failed: true, failure: error));

  Future<void> setSortOrder(BuildContext context, ServerSortOrder order) async {
    if (state.sortSaving || order == catalog.sortOrder) return;
    emit(state.copyWith(sortSaving: true));
    try {
      await AppEventBus.instance.setServerSort(order);
      emit(state.copyWith(catalog: catalog.copyWith(sortOrder: order)));
    } catch (error) {
      if (isPageActive && context.mounted) {
        ContextAlert.showToast(
          context,
          appFailureMessage(AppLocalizations.of(context)!, error),
        );
      }
    } finally {
      emit(state.copyWith(sortSaving: false));
    }
  }

  Future<void> addServers(BuildContext context) =>
      context.pushScoped(AppPageDestination.serversImport);
  Future<void> run(BuildContext context, Future<void> Function() action) async {
    await runConnectionAction(context, coordinator, action);
  }

  late final ManualServerGroupService manualGroupService =
      ManualServerGroupService(database: db);
  late final ServerAssetService assets;
  final PingService _ping;
  bool _confirmingTest = false;
  final search = TextEditingController();
  Set<String> get _pending => state.pendingServerActions;
  Set<int> get favoritingIds => state.favoritingServerIds;
  ServerSelection? get selecting => state.selectingServers;
  set selecting(ServerSelection? value) =>
      emit(state.copyWith(selectingServers: value));
  Map<int, String> get sourceErrors => state.sourceErrors;

  void setSourceError(int id, String? error) {
    final next = {...sourceErrors};
    if (error == null) {
      next.remove(id);
    } else {
      next[id] = error;
    }
    emit(state.copyWith(sourceErrors: next));
  }

  bool get busy => selecting != null || connectionView.busy;
  bool serverBusy(CoreConfigData row) =>
      _pending.contains('server:${row.id}') ||
      _pending.contains('source:${row.subId}');
  bool sourceBusy(int id) =>
      _pending.contains('source:$id') ||
      servers.any(
        (row) => row.subId == id && _pending.contains('server:${row.id}'),
      );
  bool testingGroup(String groupId) =>
      state.serverTests.values.any((test) => test.groupId == groupId);
  bool cancellingGroup(String groupId) =>
      testingGroup(groupId) &&
      state.serverTests.values
          .where((test) => test.groupId == groupId)
          .every((test) => test.cancelling);

  void _searchChanged() => searchChanged(search.text);
  void searchChanged(String value) {
    if (value != state.serverSearchQuery) {
      emit(state.copyWith(serverSearchQuery: value));
    }
  }

  bool providerSource(SubscriptionData source) =>
      source.mode == SubscriptionMode.providerManaged.name;

  bool providerRow(CoreConfigData row) =>
      catalog.display(row).type == CoreConfigType.Remnawave.name;

  bool canTest(CoreConfigData row) => catalog.outboundEligible(row);

  bool selected(ServerSelection selection) =>
      !configuration.connection.expert &&
      jsonEncode(configuration.connection.selection.toJson()) ==
          jsonEncode(selection.toJson());

  bool canChoose(CoreConfigData row) =>
      catalog.selectable(row) && !exitConflict(row);

  bool exitConflict(CoreConfigData row) =>
      catalog.outboundEligible(row) &&
      configuration.connection.trafficMode == TrafficMode.smart &&
      configuration.connection.smart.finalExitId == row.id;

  bool chosen(CoreConfigData row) => selected(ServerSelection.server(row.id));

  void chooseRow(BuildContext context, CoreConfigData row) {
    if (!canChoose(row)) return;
    choose(context, ServerSelection.server(row.id));
  }

  Set<int> get runningEntries =>
      connectionView.phase == ConnectionPhase.connected
      ? {
          for (final entry
              in connectionView.runtime?.entries ?? const <RuntimeNode>[])
            entry.id,
          if (connectionView.runtime?.profile != null)
            connectionView.runtime!.profile!.id,
        }
      : {};

  String summary(AppLocalizations l, ServerGroup group) {
    var available = 0;
    int? fastest;
    for (final row in group.rows) {
      if (!catalog.selectable(row)) continue;
      available++;
      if (ServerAssetService.healthy(row) &&
          (fastest == null || row.delay < fastest)) {
        fastest = row.delay;
      }
    }
    return l.prototypeGroupAvailability(
      available,
      group.rows.length,
      fastest ?? '—',
    );
  }

  String? sourceCheckedLabel(
    AppLocalizations l,
    DateTime timestamp, {
    DateTime? now,
  }) {
    final checked = timestamp.toLocal();
    final reference = (now ?? DateTime.now()).toLocal();
    final elapsed = reference.difference(checked);
    if (elapsed.isNegative || elapsed.inMinutes < 1) {
      return l.prototypeCheckedJustNow;
    }
    if (DateUtils.isSameDay(checked, reference)) {
      return l.prototypeCheckedToday;
    }
    return null;
  }

  Future<void> browse(BuildContext context, ServerGroup group) async {
    await context.pushScoped(
      AppPageDestination.serverGroup,
      extra: ServerGroupParams(this, group.id),
    );
  }

  Future<void> editRaw(BuildContext context, int id) =>
      context.pushScoped(AppPageDestination.rawEditor, extra: id);

  Future<void> chooseRaw(BuildContext context, CoreConfigData row) async {
    if (busy || serverBusy(row)) return;
    selecting = ServerSelection.server(row.id);
    try {
      Future<void> validate() async {
        await RawEditorService(
          database: db,
          coordinator: coordinator,
        ).validateSelection(row.id);
      }

      if (!await runConnectionAction(context, coordinator, validate)) return;
      if (!context.mounted || !isPageActive) return;
      final current = await coordinator.configuration;
      if (!context.mounted || !isPageActive) return;
      if (current.connection.expert && current.connection.rawId == row.id) {
        configuration = current;
        return;
      }
      final saved = await applyConnectionChange(
        context,
        coordinator,
        {'expert': true, 'rawId': row.id},
        validateAssets: validate,
        writeAssets: validate,
        label: (_) => row.name,
      );
      if (saved != null) configuration = saved;
    } catch (error, stackTrace) {
      if (context.mounted && isPageActive) {
        await runConnectionAction(context, coordinator, () async {
          Error.throwWithStackTrace(error, stackTrace);
        });
      }
    } finally {
      selecting = null;
    }
  }

  Future<void> removeRaw(BuildContext context, CoreConfigData row) async {
    if (busy || serverBusy(row)) return;
    await perform(context, () async {
      await RawEditorService(database: db, coordinator: coordinator).delete(
        row,
        confirm: (selected, reconnect, disconnect) async {
          if (!context.mounted || !isPageActive) return false;
          final l = AppLocalizations.of(context)!;
          final confirmed = await showDestructiveConfirmationDialog(
            context,
            title: l.prototypeDeleteRawQuestion,
            subtitle: row.name,
            warning: disconnect
                ? l.prototypeRawDeleteDisconnectNotice
                : selected
                ? l.prototypeActiveRawDeleteNotice
                : l.prototypeRawDeleteNotice,
            confirmLabel: disconnect
                ? l.prototypeDeleteAndDisconnect
                : reconnect
                ? l.prototypeDeleteAndReconnect
                : l.prototypeDelete,
          );
          return confirmed && context.mounted && isPageActive;
        },
      );
    }, ids: {row.id});
  }

  Future<void> choose(BuildContext context, ServerSelection selection) async {
    if (busy) return;
    if (selection.kind == SelectionKind.source &&
        sources.any(
          (source) => source.id == selection.id && providerSource(source),
        )) {
      ContextAlert.showToast(
        context,
        AppLocalizations.of(context)!.providerChooseConfigurationHint,
      );
      return;
    }
    selecting = selection;
    try {
      final current = await coordinator.configuration;
      if (!context.mounted || !isPageActive) return;
      if (!current.connection.expert &&
          jsonEncode(current.connection.selection.toJson()) ==
              jsonEncode(selection.toJson())) {
        await run(context, () => assets.validateSelection(selection));
        return;
      }
      final saved = await applyConnectionChange(
        context,
        coordinator,
        {'selection': selection.toJson(), 'expert': false},
        validateAssets: () => assets.validateSelection(selection),
        writeAssets: () => assets.validateSelection(selection),
        label: (next) =>
            selectionName(AppLocalizations.of(context)!, next.selection),
      );
      if (saved != null) configuration = saved;
    } finally {
      selecting = null;
    }
  }

  Future<void> toggleFavorite(BuildContext context, CoreConfigData row) =>
      perform(context, () async {
        emit(state.copyWith(favoritingServerIds: {...favoritingIds, row.id}));
        try {
          await assets.favorite(row.id, !row.favorite);
        } finally {
          emit(
            state.copyWith(
              favoritingServerIds: {...favoritingIds}..remove(row.id),
            ),
          );
        }
      }, ids: {row.id});

  Future<void> test(
    BuildContext context,
    Iterable<CoreConfigData> rows, {
    String? groupId,
  }) async {
    final ids = rows.where(canTest).map((row) => row.id).toSet();
    if (ids.isEmpty || (groupId != null && testingGroup(groupId))) return;
    final confirmed = await _confirmManualTest(context);
    if (!confirmed ||
        !context.mounted ||
        !_testPageVisible(context) ||
        (groupId != null && testingGroup(groupId))) {
      return;
    }
    await run(context, () async {
      final request = Object();
      emit(
        state.copyWith(
          serverTests: {
            ...state.serverTests,
            request: (groupId: groupId, cancelling: false),
          },
        ),
      );
      try {
        await _ping.pingConfigIds(
          ids.toList(),
          force: true,
          isCancelled: () =>
              !isPageActive || (state.serverTests[request]?.cancelling ?? true),
        );
      } finally {
        emit(
          state.copyWith(serverTests: {...state.serverTests}..remove(request)),
        );
      }
    });
  }

  bool _testPageVisible(BuildContext context) =>
      context.mounted &&
      isPageActive &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  Future<bool> _confirmManualTest(BuildContext context) async {
    if (_confirmingTest || !_testPageVisible(context)) return false;
    final view = coordinator.state.value;
    final l = AppLocalizations.of(context)!;
    final title = switch (view.phase) {
      ConnectionPhase.connected => l.pingVpnActiveTitle,
      ConnectionPhase.connecting ||
      ConnectionPhase.disconnecting => l.pingVpnChangingTitle,
      ConnectionPhase.failed when view.canDisconnect =>
        l.pingVpnPossiblyActiveTitle,
      _ => null,
    };
    if (title == null) return true;
    _confirmingTest = true;
    try {
      return await ContextAlert.showConfirmDialog(
        context,
        title: title,
        content: l.pingVpnWarning,
        confirmLabel: l.pingContinueTest,
      );
    } finally {
      _confirmingTest = false;
    }
  }

  void cancelTest(String groupId) {
    emit(
      state.copyWith(
        serverTests: state.serverTests.map(
          (id, test) => MapEntry(
            id,
            test.groupId == groupId
                ? (groupId: groupId, cancelling: true)
                : test,
          ),
        ),
      ),
    );
  }

  Future<void> serverAction(
    BuildContext context,
    CoreConfigData row,
    ServerAction action,
  ) async {
    if (serverBusy(row)) return;
    final l = AppLocalizations.of(context)!;
    switch (action) {
      case ServerAction.edit:
        if (providerRow(row)) {
          await perform(context, () async {
            final draft = await assets.loadComplete(row.id);
            if (!context.mounted || !isPageActive) return;
            await context.pushScoped(
              AppPageDestination.configFileViewer,
              extra: ConfigFileViewerParams(
                draft.original.name,
                '',
                text: draft.text,
              ),
            );
          }, ids: {row.id});
        } else {
          await context.pushScoped(
            AppPageDestination.serverEditor,
            extra: row.id,
          );
        }
      case ServerAction.test:
        await test(context, [row]);
      case ServerAction.copy:
        await perform(context, () async {
          if (providerRow(row)) {
            final name = await showAppDialog<String>(
              context,
              (_) => ProviderRawCopyNameDialog(initialName: serverName(row)),
            );
            if (name == null || !context.mounted || !isPageActive) return;
            await assets.copyAsRaw(row.id, name: name);
          } else {
            await assets.copyLocal(row, l.prototypeLocalCopy);
          }
          if (context.mounted) {
            ContextAlert.showToast(
              context,
              providerRow(row)
                  ? l.providerRawCopySaved
                  : l.prototypeLocalCopySaved,
            );
          }
        }, ids: {row.id});
      case ServerAction.share:
        await shareAsset(context, SharePageParams(ShareType.config, row.id));
      case ServerAction.move:
        await moveServer(context, row);
      case ServerAction.delete:
        await remove(context, serverName(row), ids: {row.id});
    }
  }

  Future<void> openGroupOrder(BuildContext context) async {
    if (query.trim().isNotEmpty || catalog.manualGroups.length < 2) return;
    Future<List<ManualOrderItem>> load() async =>
        (await db.manualServerGroupDao.allRows)
            .map((group) => ManualOrderItem(group.id, group.name))
            .toList();
    await context.pushScoped(
      AppPageDestination.manualServerOrder,
      extra: ManualOrderParams(
        title: AppLocalizations.of(context)!.manualGroupOrder,
        items: catalog.orderedManualGroups
            .map((group) => ManualOrderItem(group.id, group.name))
            .toList(),
        reload: load,
        save: (expected, ordered) => manualGroupService.reorderGroups(
          expectedIds: expected,
          orderedIds: ordered,
        ),
      ),
    );
  }

  /// Each saved order belongs to one complete manual group, never a filter.
  Future<void> openManualServerOrder(BuildContext context) async {
    if (query.trim().isNotEmpty) return;
    final l = AppLocalizations.of(context)!;
    final scopes = groups(
      l,
      filter: false,
    ).where((group) => group.manual).toList();
    if (!scopes.any(
      (group) => group.rows.length >= 2 && !manualGroupBusy(group),
    )) {
      return;
    }
    final nonempty = scopes.where((group) => group.rows.isNotEmpty).toList();
    final id = nonempty.length == 1
        ? nonempty.single.id
        : await showAppDialog<String>(
            context,
            (_) => ManualServerOrderScopeDialog(
              groups: scopes,
              busyGroupIds: scopes
                  .where(manualGroupBusy)
                  .map((group) => group.id)
                  .toSet(),
            ),
          );
    if (id == null || !context.mounted || !isPageActive) return;
    final group = groups(
      l,
      filter: false,
    ).where((group) => group.id == id).firstOrNull;
    if (group != null) await openServerOrder(context, group);
  }

  Future<void> openServerOrder(BuildContext context, ServerGroup group) async {
    if (!group.manual ||
        query.trim().isNotEmpty ||
        group.rows.length < 2 ||
        manualGroupBusy(group)) {
      return;
    }
    List<ManualOrderItem> items(ServerCatalog value) => value
        .copyWith(sortOrder: ServerSortOrder.defaultOrder)
        .servers
        .where(
          (row) =>
              ServerCatalog.isManual(row) &&
              row.manualGroupId == group.manualGroupId,
        )
        .map((row) => ManualOrderItem(row.id, value.display(row).name))
        .toList();
    Future<List<ManualOrderItem>> load() async => items(
      ServerCatalog(
        servers: await db.coreConfigDao.allActiveServerRows(),
        manualGroups: await db.manualServerGroupDao.allRows,
      ),
    );
    await context.pushScoped(
      AppPageDestination.manualServerOrder,
      extra: ManualOrderParams(
        title:
            '${AppLocalizations.of(context)!.manualServerOrder} · ${group.name}',
        description: AppLocalizations.of(context)!.manualOrderDisplayHint,
        items: items(catalog),
        reload: load,
        save: (expected, ordered) => manualGroupService.reorderServers(
          groupId: group.manualGroupId,
          expectedIds: expected,
          orderedIds: ordered,
        ),
      ),
    );
  }

  bool manualGroupBusy(ServerGroup group) =>
      _pending.contains('manual-group:${group.manualGroupId}') ||
      group.rows.any(serverBusy);

  Future<void> createManualGroup(BuildContext context) async {
    final name = await showAppDialog<String>(
      context,
      (_) => const ManualGroupNameDialog(),
    );
    if (name == null || !context.mounted || !isPageActive) return;
    await perform(context, () async {
      await manualGroupService.create(name);
      if (context.mounted) ContextAlert.settingsSaved(context);
    });
  }

  Future<void> moveServer(BuildContext context, CoreConfigData row) async {
    if (!ServerCatalog.isManual(row)) return;
    final target = await showAppDialog<ManualGroupTarget>(
      context,
      (_) => ManualGroupMoveDialog(
        groups: catalog.orderedManualGroups,
        currentId: row.manualGroupId,
      ),
    );
    if (target == null ||
        target.id == row.manualGroupId ||
        !context.mounted ||
        !isPageActive) {
      return;
    }
    await perform(context, () async {
      await manualGroupService.move({row.id}, targetGroupId: target.id);
      if (context.mounted) ContextAlert.settingsSaved(context);
    }, ids: {row.id});
  }

  Future<void> openManualGroupMenu(
    BuildContext context,
    ServerGroup group, {
    bool closeAfterDeletion = false,
  }) async {
    final id = group.manualGroupId;
    if (!group.manual || id == null || manualGroupBusy(group)) return;
    final action = await showAppDialog<ManualGroupAction>(
      context,
      (_) => ManualGroupActionsDialog(name: group.name),
    );
    if (action == null || !context.mounted || !isPageActive) return;
    switch (action) {
      case ManualGroupAction.rename:
        final name = await showAppDialog<String>(
          context,
          (_) => ManualGroupNameDialog(initialName: group.name),
        );
        if (name == null ||
            name == group.name ||
            !context.mounted ||
            !isPageActive) {
          return;
        }
        await _manualGroupAction(context, group, () async {
          await manualGroupService.rename(id, name);
          if (context.mounted) ContextAlert.settingsSaved(context);
        });
      case ManualGroupAction.dissolve:
        await _manualGroupAction(context, group, () async {
          final l = AppLocalizations.of(context)!;
          if (!await showDestructiveConfirmationDialog(
            context,
            title: l.manualGroupDissolve,
            subtitle: group.name,
            warning: l.manualGroupDissolveWarning(group.rows.length),
            confirmLabel: l.manualGroupDissolve,
          )) {
            return;
          }
          await manualGroupService.dissolve(id);
          if (context.mounted && isPageActive) {
            _manualGroupRemoved(context, group, closeAfterDeletion);
          }
        });
      case ManualGroupAction.delete:
        await _manualGroupAction(context, group, () async {
          final preview = await assets.previewRemoval(manualGroupId: id);
          if (!context.mounted || !isPageActive) return;
          final l = AppLocalizations.of(context)!;
          final reconnect = preview.affectsRuntime && !preview.disconnect;
          if (!await showDestructiveConfirmationDialog(
            context,
            title: l.manualGroupDelete,
            subtitle: group.name,
            warning:
                '${l.manualGroupDeleteWarning(preview.ids.length)}'
                '${preview.ids.isEmpty ? '' : '\n\n${l.prototypeDeletedServerSelectionNotice}'}'
                '${reconnect ? '\n\n${l.prototypeReconnectNotice}' : ''}',
            confirmLabel: preview.disconnect
                ? l.prototypeDeleteAndDisconnect
                : reconnect
                ? l.prototypeDeleteAndReconnect
                : l.prototypeDelete,
          )) {
            return;
          }
          await assets.remove(preview);
          if (context.mounted && isPageActive) {
            _manualGroupRemoved(context, group, closeAfterDeletion);
          }
        });
    }
  }

  void _manualGroupRemoved(
    BuildContext context,
    ServerGroup group,
    bool closePage,
  ) {
    if (!context.mounted) return;
    ContextAlert.showToast(
      context,
      AppLocalizations.of(context)!.prototypeNameRemoved(group.name),
    );
    if (closePage) Navigator.of(context).maybePop();
  }

  Future<void> _manualGroupAction(
    BuildContext context,
    ServerGroup group,
    Future<void> Function() action,
  ) async {
    if (manualGroupBusy(group)) return;
    final key = 'manual-group:${group.manualGroupId}';
    emit(state.copyWith(pendingServerActions: {..._pending, key}));
    try {
      await perform(
        context,
        action,
        ids: group.rows.map((row) => row.id).toSet(),
      );
    } finally {
      emit(state.copyWith(pendingServerActions: {..._pending}..remove(key)));
    }
  }

  Future<void> sourceAction(
    BuildContext context,
    SubscriptionData source,
    SourceAction action,
  ) async {
    if (sourceBusy(source.id)) return;
    switch (action) {
      case SourceAction.update:
        await perform(context, () async {
          final result = await SubscriptionService().refreshSubscriptionResult(
            source,
            confirmOrdinary: (name) async {
              if (!isPageActive) return false;
              final confirmed = await confirmOrdinarySubscription(
                context,
                name,
              );
              return isPageActive && confirmed;
            },
          );
          if (!context.mounted) return;
          if (failureCancelled(result.error)) return;
          if (result.superseded) return;
          final l = AppLocalizations.of(context)!;
          if (result.success) {
            setSourceError(source.id, null);
            ContextAlert.showToast(
              context,
              l.prototypeUsableNodes(result.count),
            );
          } else {
            final reason = subscriptionFailureMessage(
              l,
              result.status,
              error: result.error,
              updating: true,
            );
            setSourceError(source.id, reason);
            final navigator = Navigator.of(context);
            final closeSources = ModalRoute.of(context) is PopupRoute;
            final dialogContext = navigator.context;
            if (closeSources) navigator.pop();
            await showAppDialog<void>(
              dialogContext,
              (_) => SourceUpdateErrorDialog(
                sourceName: source.name,
                reason: reason,
                existingNodesKept:
                    result.status != SubscriptionUpdateResult.notFound,
              ),
            );
          }
        }, sourceId: source.id);
      case SourceAction.edit:
        await context.pushScoped(
          AppPageDestination.subscriptionEdit,
          extra: SubscriptionEditParams(id: source.id),
        );
      case SourceAction.share:
        await shareAsset(
          context,
          SharePageParams(ShareType.subscription, source.id),
        );
      case SourceAction.delete:
        await remove(context, source.name, sourceId: source.id);
    }
  }

  Future<void> shareAsset(BuildContext context, SharePageParams params) =>
      context.pushScoped(AppPageDestination.share, extra: params);

  Future<void> remove(
    BuildContext context,
    String name, {
    Set<int> ids = const {},
    int? sourceId,
  }) async {
    await perform(
      context,
      () async {
        final preview = await assets.previewRemoval(
          ids: ids,
          sourceId: sourceId,
        );
        if (!context.mounted) return;
        final l = AppLocalizations.of(context)!;
        final reconnect = preview.affectsRuntime && !preview.disconnect;
        if (!await showDestructiveConfirmationDialog(
          context,
          title: sourceId == null
              ? l.prototypeDeleteServer
              : l.prototypeDeleteSource,
          subtitle: name,
          warning:
              '${sourceId == null ? l.prototypeDeletedServerSelectionNotice : l.prototypeSourceDeleteWarning(preview.ids.length)}'
              '${reconnect ? '\n\n${l.prototypeReconnectNotice}' : ''}',
          confirmLabel: preview.disconnect
              ? l.prototypeDeleteAndDisconnect
              : reconnect
              ? l.prototypeDeleteAndReconnect
              : l.prototypeDelete,
        )) {
          return;
        }
        await assets.remove(preview);
        if (context.mounted) {
          ContextAlert.showToast(context, l.prototypeNameRemoved(name));
        }
      },
      ids: ids,
      sourceId: sourceId,
    );
  }

  Future<void> openServerHelp(BuildContext context) async {
    final add = await showAppDialog<bool>(
      context,
      (_) => ServerHelpDialog(canScanQr: AppPlatform.isMobile),
    );
    if (add == true && context.mounted && isPageActive) {
      await addServers(context);
    }
  }

  Future<void> perform(
    BuildContext context,
    Future<void> Function() action, {
    Set<int> ids = const {},
    int? sourceId,
  }) async {
    final keys = <String>{
      for (final id in ids) 'server:$id',
      if (sourceId != null) 'source:$sourceId',
    };
    if (keys.any(_pending.contains) ||
        (sourceId != null && sourceBusy(sourceId)) ||
        servers.any(
          (row) =>
              ids.contains(row.id) && _pending.contains('source:${row.subId}'),
        )) {
      return;
    }
    emit(state.copyWith(pendingServerActions: {..._pending, ...keys}));
    try {
      await run(context, action);
    } finally {
      emit(
        state.copyWith(pendingServerActions: {..._pending}..removeAll(keys)),
      );
    }
  }

  @override
  Future<void> disposePageResources() async {
    search.removeListener(_searchChanged);
    search.dispose();
    coordinator.state.removeListener(_connectionChanged);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
