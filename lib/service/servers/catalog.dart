import 'dart:async';

import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';

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
    _rows.where(_active),
  );
  final List<SubscriptionData> sources;
  final Map<int, ServerDisplay> displays;
  final Map<int, SubscriptionData> sourcesById;

  ServerCatalog({
    List<CoreConfigData> servers = const [],
    List<SubscriptionData> sources = const [],
  }) : this._(
         List.unmodifiable(servers),
         List.unmodifiable(sources),
         Map.unmodifiable({
           for (final row in servers) row.id: ServerDisplay.fromRow(row),
         }),
         Map.unmodifiable({for (final source in sources) source.id: source}),
       );

  ServerCatalog._(this._rows, this.sources, this.displays, this.sourcesById);

  ServerCatalog copyWith({
    List<CoreConfigData>? servers,
    List<SubscriptionData>? sources,
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

  static List<CoreConfigData> _orderedRows(List<CoreConfigData> rows) =>
      rows.toList()..sort((a, b) {
        final ordinaryA = a.type == CoreConfigType.outbound.name;
        final ordinaryB = b.type == CoreConfigType.outbound.name;
        if (ordinaryA != ordinaryB) return ordinaryA ? -1 : 1;
        if (ordinaryA) {
          final delay = a.delay.compareTo(b.delay);
          if (delay != 0) return delay;
        }
        return a.id.compareTo(b.id);
      });

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

  static Stream<ServerCatalog> watch(AppDatabase db) => Stream.multi((sink) {
    var catalog = ServerCatalog();
    final subscriptions = [
      db.coreConfigDao.watchServers().listen((rows) {
        catalog = catalog.copyWith(servers: _orderedRows(rows));
        sink.add(catalog);
      }, onError: sink.addError),
      db.subscriptionDao.allRowsStream.listen((rows) {
        catalog = catalog.copyWith(sources: rows);
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
