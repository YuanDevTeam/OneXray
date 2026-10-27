import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:onexray/core/backup/codec.dart';
import 'package:onexray/core/backup/model.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/db/dao/routing_profile.dart';
import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/core/network/model.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/custom/document.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/settings/backup/platform_settings.dart';

/// Connection assets and same-platform VPN settings cross this boundary.
/// Runtime choices, local bindings, identities and resource bytes stay local.
class BackupAssets {
  BackupAssets(this.db, this.geodata, {ConnectionPlatform? platform})
    : platform = platform ?? connectionPlatform;
  final AppDatabase db;
  final GeoDataService geodata;
  final ConnectionPlatform platform;
  late final _platformSettings = BackupPlatformSettings(platform);

  Future<void> validatePlatformSettings(BackupDocument document) async {
    final original = ConnectionConfiguration.fromJson(
      jsonDecode((await db.connectionConfigDao.read()).configurationJson)
          as Map<String, dynamic>,
    );
    _platformSettings.restore(document, original.policy);
  }

  Future<BackupDocument> capture() => db.transaction(() async {
    final nodes =
        await (db.select(db.coreConfig)
              ..where(
                (row) =>
                    row.subId.equals(0) & row.type.isIn(['outbound', 'raw']),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    final subscriptions = await db.subscriptionDao.allRows;
    final groups = await db.manualServerGroupDao.allRows;
    final groupKeys = <int, String>{
      for (var index = 0; index < groups.length; index++)
        groups[index].id: 'g${index + 1}',
    };
    final routes = await db.routingProfileDao.allRows;
    final sources = await db.geoDataDao.allRows;
    final configuration = ConnectionConfiguration.fromJson(
      jsonDecode((await db.connectionConfigDao.read()).configurationJson)
          as Map<String, dynamic>,
    );
    final settings = configuration.connection.smart;
    return BackupDocument(
      createdAt: DateTime.now().millisecondsSinceEpoch,
      platformSettings: _platformSettings.capture(configuration.policy),
      manualGroups: [
        for (final group in groups)
          BackupManualGroup(groupKeys[group.id]!, group.name, group.sortOrder),
      ],
      coreConfigs: [
        for (final row in nodes)
          BackupCoreConfig(
            row.name,
            row.type,
            row.tags,
            row.data ??
                (throw const FormatException('A configuration has no data')),
            manualGroupKey: row.type == 'outbound'
                ? groupKeys[row.manualGroupId]
                : null,
            manualSortOrder: row.type == 'outbound' ? row.manualSortOrder : 0,
          ),
      ],
      subscriptions: [
        for (final row in subscriptions)
          BackupSubscription(
            row.name,
            row.url,
            _optional(row.ageSecretKey),
            _optional(row.agePublicKey),
            row.hwidEnabled,
            _optional(row.hwid),
            panel: row.panel,
            mode: row.mode,
            userAgent: _optional(row.userAgent),
          ),
      ],
      routingProfiles: [
        for (final row in routes)
          BackupRoutingProfile(row.name, row.advanced, row.data),
      ],
      smartRouting: BackupSmartRouting(
        entryCount: settings.entryCount,
        directRegions: settings.directRegions,
        directPrivate: settings.directPrivate,
        directApple: settings.directApple,
        directWindows: settings.directWindows,
        directDns: settings.directDns,
        dns: settings.dns.toJson(),
        sniffing: settings.sniffing.toJson(),
        selection: settings.selection.toJson(),
        fakeDns: settings.fakeDns,
        fragment: settings.fragment,
        blockAds: settings.blockAds,
      ),
      geoData: [
        for (final row in sources) BackupGeoData(row.name, row.type, row.url),
      ],
    );
  });

  /// Caller has drained mutating modules and confirmed VPN stopped. This method
  /// owns one DB commit plus the Geodata rollback boundary, never a download.
  Future<void> restore(BackupDocument document, GeoDataRestorePlan preview) =>
      geodata.restoreSources(preview, (writeMetadata) async {
        final original = ConnectionConfiguration.fromJson(
          jsonDecode((await db.connectionConfigDao.read()).configurationJson)
              as Map<String, dynamic>,
        );
        final restored = ConnectionConfiguration(
          connection: ConnectionSettings(
            smart: SmartRoutingSettings.fromJson(
              document.smartRouting.toJson(),
            ),
          ),
          policy: _platformSettings.restore(document, original.policy),
        );
        await db.connectionConfigDao.commit(
          configurationJson: restored.encode(),
          writeAssets: () async {
            await db.coreConfigDao.clear();
            await db.manualServerGroupDao.clear();
            await db.subscriptionDao.clear();
            await db.routingProfileDao.clear();
            final groupIds = <String, int>{};
            for (final group in document.manualGroups) {
              groupIds[group.key] = await db.manualServerGroupDao.insertRow(
                ManualServerGroupCompanion.insert(
                  name: group.name,
                  sortOrder: Value(group.sortOrder),
                ),
              );
            }
            for (final row in document.coreConfigs) {
              await db.coreConfigDao.insertRow(
                CoreConfigCompanion.insert(
                  name: row.name,
                  type: row.type,
                  tags: row.tags,
                  data: Value(row.data),
                  delay: PingDelayConstants.unknown,
                  subId: 0,
                  manualGroupId: Value(groupIds[row.manualGroupKey]),
                  manualSortOrder: Value(row.manualSortOrder),
                ),
              );
            }
            for (final row in document.subscriptions) {
              await db.subscriptionDao.insertRow(
                SubscriptionCompanion.insert(
                  name: row.name,
                  url: row.url,
                  userAgent: Value(_optional(row.userAgent)),
                  panel: Value(row.panel),
                  mode: Value(row.mode),
                  ageSecretKey: Value(_optional(row.ageSecretKey)),
                  agePublicKey: Value(_optional(row.agePublicKey)),
                  hwidEnabled: Value(row.hwidEnabled),
                  hwid: Value(_optional(row.hwid)),
                  timestamp: DateTime.fromMillisecondsSinceEpoch(0),
                ),
              );
            }
            for (final row in document.routingProfiles) {
              await db.routingProfileDao.insertRow(
                RoutingProfileCompanion.insert(
                  name: row.name,
                  advanced: Value(row.advanced),
                  data: row.data,
                ),
              );
            }
            await writeMetadata();
          },
        );
      });
}

List<GeoDataInput> backupSources(BackupDocument document) => [
  for (final row in document.geoData)
    GeoDataInput(
      fileName: '${row.name}.dat',
      type: GeoDataType.values.byName(row.type),
      url: row.url,
    ),
];

/// Structural/import checks only; missing files do not prevent restoration.
/// Xray semantics are left to the existing editor/runtime validation paths.
void validateBackupAssets(BackupDocument document) {
  validateBackupManualGroups(document);
  for (final row in document.coreConfigs) {
    _name(row.name);
    if (row.type != 'outbound' && row.type != 'raw') {
      throw const FormatException(
        'Only local outbound and Raw assets can be restored',
      );
    }
    decodeBackupConfiguration(row.data);
  }
  final urls = <String>{};
  for (final row in document.subscriptions) {
    _name(row.name);
    GeoDataInput.httpsUri(row.url);
    if (!DownloadRequestHeaders.isValidUserAgent(_optional(row.userAgent))) {
      throw const FormatException('Invalid subscription User-Agent');
    }
    if (SubscriptionPanel.fromString(row.panel) == null ||
        SubscriptionMode.fromString(row.mode) == null) {
      throw const FormatException('Unsupported subscription panel or mode');
    }
    if (!urls.add(row.url)) {
      throw const FormatException('Duplicate subscription URL');
    }
    if ((_optional(row.ageSecretKey) == null) !=
        (_optional(row.agePublicKey) == null)) {
      throw const FormatException('Both Age keys are required');
    }
    if (row.hwidEnabled && _optional(row.hwid) == null) {
      throw const FormatException('The enabled subscription HWID is missing');
    }
  }
  if (document.routingProfiles.length > RoutingProfileDao.maxProfiles) {
    throw const FormatException(
      'At most three custom routing profiles are allowed',
    );
  }
  final names = <String>{};
  for (final row in document.routingProfiles) {
    _name(row.name);
    if (row.name.trim().runes.length > 32 ||
        !names.add(row.name.trim().toLowerCase())) {
      throw const FormatException(
        'Custom routing names must be unique and contain 1–32 characters',
      );
    }
    final json = decodeBackupConfiguration(row.data);
    if (row.advanced) {
      ConfigurationTransferService.routingDocumentFromJson(
        json,
        ConfigurationKind.customAdvanced,
        name: row.name,
        allowMetadata: false,
      );
    } else {
      RoutingProfileDocument.fromJson(
        json,
        name: row.name,
        allowMetadata: false,
        ignoreRetiredFields: true,
      );
    }
  }
  SmartRoutingSettings.fromJson(document.smartRouting.toJson()).validate();
  final files = <String>{};
  for (final row in document.geoData) {
    final name = GeoDataInput.referenceFileName('${row.name}.dat');
    GeoDataInput.httpsUri(row.url);
    if (!['domain', 'ip'].contains(row.type) ||
        !files.add(name.toLowerCase())) {
      throw const FormatException('Invalid or duplicate Geodata source');
    }
  }
}

void _name(String name) {
  if (name.trim().isEmpty) {
    throw const FormatException('A backup asset name is missing');
  }
}

String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value;
