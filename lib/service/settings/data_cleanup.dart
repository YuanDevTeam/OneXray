import 'dart:io';

import 'package:onexray/core/errors/failure.dart';

import 'package:flutter/foundation.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/launch/app_startup.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/advanced/local_api/service.dart';
import 'package:onexray/service/advanced/xray/data_update/service.dart';
import 'package:onexray/service/servers/import.dart';
import 'package:onexray/service/servers/manual_groups.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/settings/backup/service.dart';
import 'package:onexray/service/advanced/tunnel/android/automation/service.dart';
import 'package:path_provider/path_provider.dart';

final class AppDataCleanupService {
  static final AppDataCleanupService _singleton = AppDataCleanupService._(
    ConnectionCoordinator.instance,
    GeoDataService(),
    SubscriptionService(),
    PingService(),
    null,
    BackupService(),
    AndroidAutomationService(),
  );

  factory AppDataCleanupService() => _singleton;

  AppDataCleanupService._(
    this._coordinator,
    this._geodata,
    this._subscriptions,
    this._ping,
    this._clearOverride,
    this._backup,
    this._automation,
  );

  @visibleForTesting
  factory AppDataCleanupService.forTesting({
    required ConnectionCoordinator coordinator,
    required GeoDataService geodata,
    required SubscriptionService subscriptions,
    required PingService ping,
    required Future<void> Function() clear,
    BackupService? backup,
    AndroidAutomationService? automation,
  }) => AppDataCleanupService._(
    coordinator,
    geodata,
    subscriptions,
    ping,
    clear,
    backup,
    automation ?? AndroidAutomationService(),
  );

  final ConnectionCoordinator _coordinator;
  final GeoDataService _geodata;
  final SubscriptionService _subscriptions;
  final PingService _ping;
  final Future<void> Function()? _clearOverride;
  final BackupService? _backup;
  final AndroidAutomationService _automation;
  bool _clearing = false;

  Future<bool> clearFromSettings() async {
    if (_clearing) return false;
    _clearing = true;
    var deleting = false;
    var blocked = false;
    try {
      // Pause every producer before awaiting any one of them. In-flight imports
      // may finish their current write, but cannot start another source/probe.
      await Future.wait([
        _automation.setStartBlocked(true).then((_) => blocked = true),
        _pauseProducers(pauseBackup: true),
      ]);
      await _geodata.withFiles(() async {
        await _coordinator.stopForMaintenance();
        deleting = true;
        await _automation.clear();
        await (_clearOverride ?? _clear)();
      });
      return true;
    } catch (e, stackTrace) {
      ygLogger("clear app data error: $e\n$stackTrace");
      throw AppFailure(
        failureCategory(e),
        deleting ? 'cleanup' : 'cleanupBeforeDelete',
        cause: e,
      );
    } finally {
      await _finishDataChange(blocked: blocked, resumeBackup: true);
    }
  }

  /// Same admission/drain boundary as clear, without deleting preferences,
  /// default resources, runtime permissions or startup setup. The backup
  /// transaction may restore VPN settings for the current platform.
  Future<void> runForRestore(Future<void> Function() commit) async {
    if (_clearing) throw StateError('App data is being cleared or restored.');
    _clearing = true;
    var blocked = false;
    try {
      // The caller already owns the backup operation. Waiting for it here
      // would wait for this very restore; clear claims _clearing first instead.
      await Future.wait([
        _automation.setStartBlocked(true).then((_) => blocked = true),
        _pauseProducers(pauseBackup: false),
      ]);
      await _geodata.withFiles(() async {
        await _coordinator.stopForMaintenance();
        await commit();
      });
    } finally {
      await _finishDataChange(blocked: blocked, resumeBackup: false);
    }
  }

  Future<void> _finishDataChange({
    required bool blocked,
    required bool resumeBackup,
  }) async {
    try {
      if (blocked) await _automation.setStartBlocked(false);
    } finally {
      _resumeProducers(resumeBackup: resumeBackup);
      _clearing = false;
    }
  }

  Future<void> _pauseProducers({required bool pauseBackup}) => Future.wait([
    LocalApiService.instance.pauseForDataClear(),
    if (pauseBackup && _backup != null) _backup.pauseForDataClear(),
    DataUpdateService().pauseForDataClear(),
    ServerImportService.pauseForDataClear(),
    ManualServerGroupService.pauseForDataClear(),
    _subscriptions.pauseForDataClear(),
    _ping.pauseForDataClear(),
    _coordinator.pauseForDataClear(),
    _geodata.pauseForDataClear(),
  ]);

  void _resumeProducers({required bool resumeBackup}) {
    LocalApiService.instance.resumeAfterDataClear();
    _geodata.resumeAfterDataClear();
    _coordinator.resumeAfterDataClear();
    _ping.resumeAfterDataClear();
    _subscriptions.resumeAfterDataClear();
    ServerImportService.resumeAfterDataClear();
    ManualServerGroupService.resumeAfterDataClear();
    DataUpdateService().resumeAfterDataClear();
    if (resumeBackup) _backup?.resumeAfterDataClear();
  }

  Future<void> _clear() async {
    await AppStartupService().unregisterForDataCleanup();
    await PreferencesKey().clearUserDataPreferences();
    AppEventBus.instance.resetServerSort();
    await LocalApiService.instance.clearAfterDataClear();
    await _clearDatabase();
    await _clearRuntimeFiles();
    _coordinator.clearTrafficView();
    AppEventBus.instance.clearPingFailures();
    await _geodata.resetAfterDataClear();
    await _clearCache();
  }

  Future<void> _clearDatabase() async {
    final db = AppDatabase();
    await db.transaction(() async {
      await db.geoDataDao.clear();
      await db.coreConfigDao.clear();
      await db.manualServerGroupDao.clear();
      await db.subscriptionDao.clear();
      await db.routingProfileDao.clear();
      await db.connectionConfigDao.reset();
    });
  }

  Future<void> _clearRuntimeFiles() async {
    final directory = Directory(VpnConstants.runDir);
    if (!await directory.exists()) return;
    await for (final entry in directory.list(followLinks: false)) {
      await entry.delete(recursive: true);
    }
  }

  Future<void> _clearCache() async {
    final cacheDir = await getApplicationCacheDirectory();
    if (!await cacheDir.exists()) {
      return;
    }
    await for (final entity in cacheDir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (e) {
        ygLogger("delete cache failed: ${entity.path}, $e");
      }
    }
  }
}
