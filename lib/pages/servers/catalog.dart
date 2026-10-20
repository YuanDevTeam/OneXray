import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/connect/settings.dart';

class ServerGroup {
  final String id;
  final String name;
  final SubscriptionData? source;
  final ServerSelection? selection;
  final int? manualGroupId;
  bool get manual => source == null;
  final List<CoreConfigData> rows;
  final List<CoreConfigData> visibleRows;
  const ServerGroup({
    required this.id,
    required this.name,
    this.source,
    this.selection,
    this.manualGroupId,
    required this.rows,
    required this.visibleRows,
  });
}

mixin ServerLabels {
  String selectionName(AppLocalizations l10n, ServerSelection selection) =>
      switch (selection.kind) {
        SelectionKind.automatic => l10n.prototypeAutomaticSelection,
        SelectionKind.source =>
          selection.id == 0
              ? l10n.prototypeManualAdditions
              : catalog.sourcesById[selection.id]?.name ??
                    l10n.prototypeTemporarilyUnavailable,
        SelectionKind.server =>
          catalog.servers
                  .where((row) => row.id == selection.id)
                  .map(serverName)
                  .firstOrNull ??
              l10n.prototypeTemporarilyUnavailable,
      };

  ServerCatalog get catalog;
  String serverName(CoreConfigData row) => catalog.display(row).name;
  String protocol(CoreConfigData row) => catalog.display(row).protocol;
  String health(AppLocalizations l, CoreConfigData row) =>
      row.delay == PingDelayConstants.unknown
      ? l.prototypeNotTested
      : !PingDelayConstants.isSuccessful(row.delay)
      ? l.prototypeTemporarilyUnavailable
      : row.delay <= 500
      ? l.prototypeFastLatency(row.delay)
      : row.delay <= 1000
      ? l.prototypeSlowLatency(row.delay)
      : l.prototypeAvailableLatency(row.delay);
}

mixin ServerGroups on ServerLabels {
  String get query;
  List<CoreConfigData> get servers => catalog.servers;
  List<SubscriptionData> get sources => catalog.sources;
  String sourceName(AppLocalizations l, CoreConfigData row) =>
      ServerCatalog.isManual(row)
      ? catalog.manualGroups
                .where((group) => group.id == row.manualGroupId)
                .firstOrNull
                ?.name ??
            l.manualGroupUngrouped
      : catalog.sourcesById[row.subId]?.name ?? l.prototypeManualAdditions;

  int sourceCount(int id) => servers.where((row) => row.subId == id).length;

  bool matches(AppLocalizations l, CoreConfigData row) {
    final query = this.query.trim().toLowerCase();
    return query.isEmpty ||
        [
          serverName(row),
          sourceName(l, row),
        ].any((value) => value.toLowerCase().contains(query));
  }

  List<CoreConfigData> favorites(AppLocalizations l) =>
      servers.where((row) => row.favorite && matches(l, row)).toList();

  List<ServerGroup> groups(AppLocalizations l, {bool filter = true}) {
    final query = filter ? this.query.trim().toLowerCase() : '';
    final result = <ServerGroup>[];
    void add({
      required String id,
      required String name,
      SubscriptionData? source,
      ServerSelection? selection,
      int? manualGroupId,
      required List<CoreConfigData> rows,
    }) {
      final wholeGroup = query.isEmpty || name.toLowerCase().contains(query);
      final visible = wholeGroup
          ? rows
          : rows.where((row) => matches(l, row)).toList();
      if (!wholeGroup && visible.isEmpty) return;
      result.add(
        ServerGroup(
          id: id,
          name: name,
          source: source,
          selection: selection,
          manualGroupId: manualGroupId,
          rows: rows,
          visibleRows: visible,
        ),
      );
    }

    final manual = servers.where(ServerCatalog.isManual).toList();
    final knownIds = catalog.manualGroups.map((group) => group.id).toSet();
    if (manual.isNotEmpty || catalog.manualGroups.isNotEmpty) {
      add(
        id: 'manual:ungrouped',
        name: l.manualGroupUngrouped,
        rows: manual
            .where((row) => !knownIds.contains(row.manualGroupId))
            .toList(),
      );
    }
    for (final group in catalog.orderedManualGroups) {
      add(
        id: 'manual:${group.id}',
        name: group.name,
        manualGroupId: group.id,
        rows: manual.where((row) => row.manualGroupId == group.id).toList(),
      );
    }
    final sourceIds =
        servers
            .where((row) => !ServerCatalog.isManual(row))
            .map((row) => row.subId)
            .toSet()
            .toList()
          ..sort();
    for (final sourceId in sourceIds) {
      final source = catalog.sourcesById[sourceId];
      add(
        id: 'subscription:$sourceId',
        name: source?.name ?? l.prototypeManualAdditions,
        source: source,
        selection: ServerSelection.source(sourceId),
        rows: servers.where((row) => row.subId == sourceId).toList(),
      );
    }
    return result;
  }
}
