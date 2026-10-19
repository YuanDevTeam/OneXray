import 'dart:async';

import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/servers/sort.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

/// Display data is parsed when rows change, never while building node widgets.
class ServerDisplay {
  final String name;
  final String protocol;
  final bool readable;
  final String type;
  const ServerDisplay(
    this.name,
    this.protocol,
    this.readable, {
    this.type = 'outbound',
  });

  factory ServerDisplay.fromRow(CoreConfigData row) {
    try {
      if (row.type == CoreConfigType.Remnawave.name) {
        ResolvedProfile.fromRow(row);
        return ServerDisplay(row.name, '', true, type: row.type);
      }
      final outbound = readOutboundFromDbData(row);
      return ServerDisplay(
        outboundDisplayName(outbound),
        outboundProtocolLabel(outbound),
        row.type == 'outbound',
        type: row.type,
      );
    } on FormatException {
      return ServerDisplay(row.name, '', false, type: row.type);
    }
  }
}

class ServerCatalog {
  final List<CoreConfigData> _rows;
  late final List<CoreConfigData> servers = List.unmodifiable(
    _orderedRows(_rows.where(_active)),
  );
  final ServerSortOrder sortOrder;
  final List<SubscriptionData> sources;
  final Map<int, ServerDisplay> displays;
  final Map<int, SubscriptionData> sourcesById;

  ServerCatalog({
    List<CoreConfigData> servers = const [],
    List<SubscriptionData> sources = const [],
    ServerSortOrder sortOrder = ServerSortOrder.defaultOrder,
  }) : this._(
         List.unmodifiable(servers),
         List.unmodifiable(sources),
         Map.unmodifiable({
           for (final row in servers) row.id: ServerDisplay.fromRow(row),
         }),
         Map.unmodifiable({for (final source in sources) source.id: source}),
         sortOrder,
       );

  ServerCatalog._(
    this._rows,
    this.sources,
    this.displays,
    this.sourcesById,
    this.sortOrder,
  );

  ServerCatalog copyWith({
    List<CoreConfigData>? servers,
    List<SubscriptionData>? sources,
    ServerSortOrder? sortOrder,
  }) => ServerCatalog._(
    servers == null ? _rows : List.unmodifiable(servers),
    sources == null ? this.sources : List.unmodifiable(sources),
    servers == null
        ? displays
        : Map.unmodifiable({
            for (final row in servers) row.id: ServerDisplay.fromRow(row),
          }),
    sources == null
        ? sourcesById
        : Map.unmodifiable({for (final source in sources) source.id: source}),
    sortOrder ?? this.sortOrder,
  );

  ServerDisplay display(CoreConfigData row) =>
      displays[row.id] ?? ServerDisplay.fromRow(row);

  bool _active(CoreConfigData row) {
    final source = sourcesById[row.subId];
    return switch (row.type) {
      'outbound' =>
        source == null || source.mode == SubscriptionMode.appManaged.name,
      'Remnawave' =>
        source != null && source.mode == SubscriptionMode.providerManaged.name,
      _ => false,
    };
  }

  List<CoreConfigData> _orderedRows(Iterable<CoreConfigData> rows) =>
      rows.toList()..sort((a, b) {
        switch (sortOrder) {
          case ServerSortOrder.defaultOrder:
            break;
          case ServerSortOrder.name:
            final name = display(a).name
                .trim()
                .toLowerCase()
                .compareTo(display(b).name.trim().toLowerCase());
            if (name != 0) return name;
            break;
          case ServerSortOrder.delay:
            final categoryA = _delayCategory(a);
            final category = categoryA.compareTo(_delayCategory(b));
            if (category != 0) return category;
            if (categoryA == 0) {
              final delay = a.delay.compareTo(b.delay);
              if (delay != 0) return delay;
            }
            break;
        }
        return a.id.compareTo(b.id);
      });

  static int _delayCategory(CoreConfigData row) {
    if (row.type != CoreConfigType.outbound.name) return 3;
    if (PingDelayConstants.isSuccessful(row.delay)) return 0;
    if (row.delay == PingDelayConstants.unknown) return 1;
    return 2;
  }

  /// Ordinary nodes can be measured again even after a failed measurement.
  bool outboundEligible(CoreConfigData row) =>
      row.type == CoreConfigType.outbound.name &&
      _active(row) &&
      display(row).readable;

  bool selectable(CoreConfigData row) =>
      _active(row) &&
      display(row).readable &&
      (row.type == CoreConfigType.Remnawave.name ||
          row.delay == PingDelayConstants.unknown ||
          PingDelayConstants.isSuccessful(row.delay));

  static Stream<ServerCatalog> watch(AppDatabase db, {AppEventBus? eventBus}) =>
      Stream.multi((sink) {
        final bus = eventBus ?? AppEventBus.instance;
        var catalog = ServerCatalog(sortOrder: bus.state.serverSort);
        final subscriptions = [
          db.coreConfigDao.watchServers().listen((rows) {
            catalog = catalog.copyWith(servers: rows);
            sink.add(catalog);
          }, onError: sink.addError),
          db.subscriptionDao.allRowsStream.listen((rows) {
            catalog = catalog.copyWith(sources: rows);
            sink.add(catalog);
          }, onError: sink.addError),
          bus.stream.map((state) => state.serverSort).distinct().listen((
            order,
          ) {
            if (order == catalog.sortOrder) return;
            catalog = catalog.copyWith(sortOrder: order);
            sink.add(catalog);
          }, onError: sink.addError),
        ];
        sink.onCancel = () async {
          for (final subscription in subscriptions) {
            await subscription.cancel();
          }
        };
      });
}
