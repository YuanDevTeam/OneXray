import 'dart:async';
import 'dart:convert';

import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/shared/menu/tray/entry.dart';

/// Desktop-only menu content. Database streams keep names, selections and
/// available choices current; native VPN state remains owned by the coordinator.
class TrayMenuData {
  static const _maxDataItems = 10;

  ServerCatalog catalog = ServerCatalog();
  List<CoreConfigData> raws = [];
  List<RoutingProfileData> routes = [];
  List<GeoDataData> geodata = [];
  ConnectionSettings configuration = ConnectionSettings();

  static Stream<TrayMenuData> watch(AppDatabase db) => Stream.multi((sink) {
    final data = TrayMenuData();
    final subscriptions = <StreamSubscription<dynamic>>[
      ServerCatalog.watch(db).listen((catalog) {
        data.catalog = catalog;
        sink.add(data);
      }, onError: sink.addError),
      db.coreConfigDao.allRawRowsWithDataStream.listen((rows) {
        data.raws = rows;
        sink.add(data);
      }, onError: sink.addError),
      db.routingProfileDao.allRowsStream.listen((rows) {
        data.routes = rows;
        sink.add(data);
      }, onError: sink.addError),
      db.geoDataDao.publishedRowsStream.listen((rows) {
        data.geodata = rows.where((row) => row.id > 0).toList();
        sink.add(data);
      }, onError: sink.addError),
      db.connectionConfigDao.watch().listen((row) {
        try {
          data.configuration = ConnectionConfiguration.fromJson(
            jsonDecode(row.configurationJson) as Map<String, dynamic>,
          ).connection;
          sink.add(data);
        } catch (error, stackTrace) {
          sink.addError(error, stackTrace);
        }
      }, onError: sink.addError),
    ];
    sink.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
  });

  List<TrayMenuEntry> selectionItems(
    AppLocalizations l, {
    required bool busy,
    RuntimeProfile? runningProfile,
  }) {
    final selected = configuration.selection;
    final provider =
        runningProfile != null ||
        (!configuration.expert &&
            selected.kind == SelectionKind.server &&
            catalog.servers.any(
              (row) =>
                  row.id == selected.id &&
                  row.type == CoreConfigType.Remnawave.name &&
                  catalog.selectable(row),
            ));
    final trafficEnabled = !configuration.expert && !provider;
    TrayMenuEntry choice(
      String key,
      String label,
      bool checked, {
      bool enabled = true,
    }) => TrayMenuEntry(
      key: key,
      label: label,
      checked: checked,
      disabled: busy || !enabled,
    );
    TrayMenuEntry group(
      String label,
      List<TrayMenuEntry> items, {
      bool enabled = true,
    }) => TrayMenuEntry(
      label: label,
      disabled: busy || !enabled || items.isEmpty,
      children: items,
    );
    bool isSelected(ServerSelection selection) =>
        !configuration.expert &&
        selected.kind == selection.kind &&
        selected.id == selection.id;
    final sources = <int, String>{
      if (catalog.servers.any((row) => row.subId == 0))
        0: l.prototypeManualAdditions,
      for (final source in catalog.sources.take(_maxDataItems))
        source.id: source.name,
    };
    return [
      group(l.prototypeServers, [
        if (runningProfile != null)
          TrayMenuEntry(
            label: '${l.providerConfigurationTitle} · ${runningProfile.name}',
            disabled: true,
          ),
        choice(
          'automatic',
          l.prototypeAutomaticSelection,
          isSelected(const ServerSelection.automatic()),
        ),
        group(l.prototypeBySubscription, [
          for (final source in sources.entries)
            if (catalog.sourcesById[source.key]?.mode ==
                SubscriptionMode.providerManaged.name)
              group(source.value, [
                for (final row
                    in catalog.servers
                        .where((row) => row.subId == source.key)
                        .take(_maxDataItems))
                  choice(
                    'server:${row.id}',
                    catalog.display(row).name,
                    isSelected(ServerSelection.server(row.id)),
                    enabled: catalog.selectable(row),
                  ),
              ])
            else
              choice(
                'source:${source.key}',
                source.value,
                isSelected(ServerSelection.source(source.key)),
              ),
        ]),
        group(l.prototypeServers, [
          for (final row
              in catalog.servers
                  .where((row) => row.type == CoreConfigType.outbound.name)
                  .take(_maxDataItems))
            choice(
              'server:${row.id}',
              catalog.display(row).name,
              isSelected(ServerSelection.server(row.id)),
              enabled: catalog.selectable(row),
            ),
        ]),
      ]),
      group('Raw JSON', [
        for (final row in raws.take(_maxDataItems))
          choice(
            'raw:${row.id}',
            row.name,
            configuration.expert && configuration.rawId == row.id,
          ),
      ]),
      group(
        provider
            ? l.providerConfigurationTitle
            : l.prototypeChooseTrafficMethod,
        [
          choice(
            'traffic:smart',
            l.prototypeSmartRoutingRecommended,
            configuration.trafficMode == TrafficMode.smart,
            enabled: trafficEnabled,
          ),
          choice(
            'traffic:allVpn',
            l.prototypeAllViaVpn,
            configuration.trafficMode == TrafficMode.allVpn,
            enabled: trafficEnabled,
          ),
          group(l.prototypeCustomRouting, [
            for (final route in routes.take(_maxDataItems))
              choice(
                'custom:${route.id}',
                route.name,
                configuration.trafficMode == TrafficMode.custom &&
                    configuration.customId == route.id,
                enabled: trafficEnabled,
              ),
          ], enabled: trafficEnabled),
        ],
        enabled: trafficEnabled,
      ),
    ];
  }

  List<TrayMenuEntry> updateItems(AppLocalizations l, Set<String> pending) {
    TrayMenuEntry update(String key, String label, {String? allKey}) {
      final active = pending.contains(key) || pending.contains(allKey);
      return TrayMenuEntry(
        key: key,
        label: active ? '$label · ${l.prototypePleaseWait}' : label,
        disabled: active,
      );
    }

    return [
      TrayMenuEntry(
        label: l.menuShortcutUpdateSubscriptions,
        disabled: catalog.sources.isEmpty,
        children: [
          update('updateSubscriptions', l.prototypeUpdateAll),
          TrayMenuEntry.separator(),
          for (final source in catalog.sources.take(_maxDataItems))
            update(
              'updateSubscription:${source.id}',
              source.name,
              allKey: 'updateSubscriptions',
            ),
        ],
      ),
      TrayMenuEntry(
        label: l.prototypeRoutingData,
        children: [
          update('updateGeodata', l.prototypeUpdateAll),
          TrayMenuEntry.separator(),
          update(
            'updateDefaultGeodata',
            l.prototypeDefaultRoutingData,
            allKey: 'updateGeodata',
          ),
          for (final file in geodata.take(_maxDataItems))
            update(
              'updateGeodata:${file.id}',
              '${file.name}.dat',
              allKey: 'updateGeodata',
            ),
        ],
      ),
    ];
  }
}
