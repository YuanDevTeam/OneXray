import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/launch/app_startup.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:onexray/service/advanced/xray/data_update/scheduler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/platform_requirements.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/advanced/local_api/service.dart';
import 'package:onexray/service/launch/storage_preparation.dart';
import 'package:onexray/service/shared/menu/short_cut/service.dart';
import 'package:onexray/service/shared/menu/tray/service.dart';
import 'package:onexray/service/shared/menu/window/service.dart';
import 'package:onexray/service/shared/notification/service.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:onexray/service/shared/share/service.dart';
import 'package:onexray/service/shared/apple_widget/service.dart';
import 'package:onexray/service/advanced/tunnel/android/automation/service.dart';

abstract final class ServiceManager {
  static Future<void>? _initFuture;
  static var _initialized = false;

  static Future<void> serviceInit(BuildContext context) {
    if (_initialized) {
      return Future.value();
    }
    final initFuture = _initFuture;
    if (initFuture != null) {
      return initFuture;
    }

    final nextInitFuture = _serviceInitWithFailureRecovery(context);
    _initFuture = nextInitFuture;
    return nextInitFuture;
  }

  static Future<void> _serviceInitWithFailureRecovery(
    BuildContext context,
  ) async {
    try {
      await _serviceInit(context);
    } catch (error, stackTrace) {
      _initFuture = null;
      try {
        await AppStartupService().showMainWindow();
      } catch (windowError, windowStackTrace) {
        ygLogger(
          "show window after startup failure error: "
          "$windowError\n$windowStackTrace",
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<void> _serviceInit(BuildContext context) async {
    await AppleWidgetService().initialize();
    final databaseWasMissing = await StoragePreparation.ensureReady();
    await _runInit("NetClient", () => NetClient().asyncInit());
    await GeoDataService().ensureInstalled(
      resetOrphanedFiles: databaseWasMissing,
    );
    await ConnectionPlatformRequirements().ensureRuntime();
    // Recovery must succeed before external commands or automatic connection
    // are enabled. The legacy Profile runtime must not initialize alongside it.
    await ConnectionCoordinator.instance.initialize(
      requestPermission: AppHostApi().requestPlatformPermission,
    );
    // Recover only the admission marker after storage and runtime are ready.
    await AndroidAutomationService().setStartBlocked(false);
    await _runInit(
      "NotificationService",
      () => NotificationService().asyncInit(),
    );
    await _runInit("TrayService", () => TrayService().init());
    await _runInit("WindowService", () => WindowService().asyncInit());
    await _runInit("ShareService", () => ShareService().init());
    await _runInit(
      "AppStartupService",
      () => AppStartupService().handleServicesReady(),
    );
    BackgroundTaskService().init(
      vpnConnected:
          ConnectionCoordinator.instance.state.value.phase ==
          ConnectionPhase.connected,
    );
    _initialized = true;
    await _runInit('LocalApiService', LocalApiService.instance.start);
    PingService().startAutomatic();
    unawaited(_checkUpdate());
  }

  static Future<void> _checkUpdate() async {
    try {
      final service = AppUpdateService();
      if (!await service.shouldRunAutomaticCheck()) return;
      await service.recordAutomaticCheck();
      final result = await service.checkForUpdate();
      if (result.status == AppUpdateCheckStatus.upToDate) {
        AppEventBus.instance.updateAppUpdateInfo(null);
      } else if (result.updateInfo case final update?) {
        AppEventBus.instance.updateAppUpdateInfo(
          await service.shouldShowAutomaticReminder(update) ? update : null,
        );
      }
    } catch (_) {
      /* Update checks never block connection readiness. */
    }
  }

  static Future<void> _runInit(
    String name,
    FutureOr<void> Function() init,
  ) async {
    try {
      await init();
    } catch (e, stackTrace) {
      ygLogger("$name init error: $e\n$stackTrace");
    }
  }

  static void serviceDispose() {
    unawaited(LocalApiService.instance.stop());
    PingService().stopAutomatic();
    _initFuture = null;
    _initialized = false;
    TrayService().dispose();
    ShareService().dispose();
    AppleWidgetService().dispose();
    ShortCutService().detach();
    WindowService().dispose();
    BackgroundTaskService().dispose();
  }
}
