import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/connect/settings.dart';

class ServerGroup {
  final String id;
  final String name;
  final SubscriptionData? source;
  final ServerSelection selection;
  final List<CoreConfigData> rows;
  final List<CoreConfigData> visibleRows;
  const ServerGroup({
    required this.id,
    required this.name,
    this.source,
    required this.selection,
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
      catalog.sourcesById[row.subId]?.name ?? l.prototypeManualAdditions;

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
    final buckets = <String, List<CoreConfigData>>{};
    for (final row in servers) {
      final key = '${row.subId}';
      buckets.putIfAbsent(key, () => []).add(row);
    }
    final result = <ServerGroup>[];
    for (final entry in buckets.entries) {
      final source = catalog.sourcesById[int.parse(entry.key)];
      final name = source?.name ?? l.prototypeManualAdditions;
      final query = this.query.trim().toLowerCase();
      final wholeGroup = !filter || name.toLowerCase().contains(query);
      final visible = wholeGroup
          ? entry.value
          : entry.value.where((row) => matches(l, row)).toList();
      if (filter && query.isNotEmpty && visible.isEmpty && !wholeGroup) {
        continue;
      }
      result.add(
        ServerGroup(
          id: 'subscription:${entry.key}',
          name: name,
          source: source,
          selection: ServerSelection.source(int.parse(entry.key)),
          rows: entry.value,
          visibleRows: visible,
        ),
      );
    }
    result.sort((a, b) => a.selection.id!.compareTo(b.selection.id!));
    return result;
  }
}
