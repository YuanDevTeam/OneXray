import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/servers/catalog.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/servers/catalog.dart';

class ServerExitChoice {
  final int? id;
  const ServerExitChoice(this.id);
}

class ServerExitPickerParams {
  final int? selectedId;
  final Set<int> excludedIds;
  const ServerExitPickerParams({this.selectedId, this.excludedIds = const {}});
}

const _unchanged = Object();

class ServerExitPickerState {
  final ServerCatalog catalog;
  final String query;
  final int? selectedId;
  final bool ready, failed, busy;
  ServerExitPickerState({
    ServerCatalog? catalog,
    this.query = '',
    this.selectedId,
    this.ready = false,
    this.failed = false,
    this.busy = false,
  }) : catalog = catalog ?? ServerCatalog();

  ServerExitPickerState copyWith({
    ServerCatalog? catalog,
    String? query,
    Object? selectedId = _unchanged,
    bool? ready,
    bool? failed,
    bool? busy,
  }) => ServerExitPickerState(
    catalog: catalog ?? this.catalog,
    query: query ?? this.query,
    selectedId: identical(selectedId, _unchanged)
        ? this.selectedId
        : selectedId as int?,
    ready: ready ?? this.ready,
    failed: failed ?? this.failed,
    busy: busy ?? this.busy,
  );
}

/// Local selection draft; it does not load or mutate connection/route settings.
class ServerExitPickerController extends PageCubit<ServerExitPickerState>
    with ServerLabels, ServerGroups {
  ServerExitPickerController(
    this.params, {
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
  }) : db = database ?? AppDatabase(),
       coordinator = coordinator ?? ConnectionCoordinator.instance,
       super(ServerExitPickerState(selectedId: params.selectedId)) {
    this.coordinator.state.addListener(_connectionChanged);
    _connectionChanged();
    search.addListener(_searchChanged);
  }
  final ServerExitPickerParams params;
  final AppDatabase db;
  final ConnectionCoordinator coordinator;
  final search = TextEditingController();
  StreamSubscription<ServerCatalog>? _subscription;
  @override
  ServerCatalog get catalog => state.catalog;
  @override
  String get query => state.query;
  int? get selectedId => state.selectedId;
  bool get ready => state.ready;
  bool get failed => state.failed;
  bool get busy => state.busy;

  Future<void> initialize() async {
    if (!isPageActive) return;
    _subscription ??= ServerCatalog.watch(db).listen(
      (value) => emit(state.copyWith(catalog: value)),
      onError: (Object error) => emit(state.copyWith(failed: true)),
    );
    emit(state.copyWith(ready: true, failed: false));
  }

  void _connectionChanged() {
    final busy = coordinator.state.value.busy;
    if (busy != state.busy) emit(state.copyWith(busy: busy));
  }

  void _searchChanged() => searchChanged(search.text);
  void searchChanged(String value) {
    if (query != value) emit(state.copyWith(query: value));
  }

  List<ServerGroup> selectionGroups(AppLocalizations l) =>
      groups(l).where((group) => group.visibleRows.isNotEmpty).toList();
  bool canSelect(CoreConfigData row) =>
      catalog.selectable(row) && !params.excludedIds.contains(row.id);
  void selectDraft(CoreConfigData? row) {
    if (busy || !ready || (row != null && !canSelect(row))) return;
    emit(state.copyWith(selectedId: row?.id));
  }

  String exitRowDetail(AppLocalizations l, CoreConfigData row) {
    if (params.excludedIds.contains(row.id)) return l.prototypeEntryServer;
    if (!canSelect(row)) return l.prototypeTemporarilyUnavailable;
    return health(l, row);
  }

  bool get canFinish =>
      ready &&
      !failed &&
      !busy &&
      (selectedId == null ||
          servers.any((row) => row.id == selectedId && canSelect(row)));
  void complete(BuildContext context) {
    if (canFinish) Navigator.of(context).pop(ServerExitChoice(selectedId));
  }

  @override
  Future<void> disposePageResources() async {
    search.dispose();
    coordinator.state.removeListener(_connectionChanged);
    await _subscription?.cancel();
  }
}
