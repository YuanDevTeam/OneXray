import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/pages/settings/app_update/params.dart';
import 'package:onexray/service/settings/app_update/service.dart';

/// Root tabs choose their entry page from the same business-page registry.
enum AppPrimaryDestination {
  connect(AppPageDestination.connect),
  servers(AppPageDestination.servers),
  advanced(AppPageDestination.advanced),
  settings(AppPageDestination.settings);

  final AppPageDestination page;

  const AppPrimaryDestination(this.page);

  String get rootPath => "/${page.segment}";

  static AppPrimaryDestination fromPath(String path) {
    for (final destination in values) {
      if (path == destination.rootPath ||
          path.startsWith("${destination.rootPath}/")) {
        return destination;
      }
    }
    return connect;
  }
}

/// Every business page can be pushed inside the current tab, including roots.
/// Launch and Setup routes are registered separately.
enum AppPageDestination {
  connect("connect"),
  servers("servers"),
  advanced("advanced"),
  settings("settings"),
  serversImport("servers-import"),
  serverGroup("server-group"),
  manualServerOrder("manual-server-order"),
  serverEditor("server-editor"),
  serverFinalExitPicker("server-final-exit-picker"),
  rawEditor("raw-editor"),
  smartRouting("smart-routing"),
  directRegions("direct-regions"),
  customRouting("custom-routing"),
  advancedRouting("advanced-routing"),
  customRule("custom-rule"),
  appleVpn("apple-vpn"),
  appleWifi("apple-wifi"),
  androidVpn("android-vpn"),
  androidAutomation("android-automation"),
  androidApps("android-apps"),
  windowsVpn("windows-vpn"),
  outboundInterface("outbound-interface"),
  routingData("routing-data"),
  routingDataFile("routing-data-file"),
  share("share"),
  subscriptionEdit("subscription-edit"),
  ping("ping"),
  logFile("log-file"),
  configFileViewer("config-file-viewer"),
  lanProxy("lan-proxy"),
  serverDialing("server-dialing"),
  autoUpdate("auto-update"),
  localApi("local-api"),
  backup("backup"),
  desktopSettings("desktop-settings"),
  appIcon("app-icon"),
  theme("theme"),
  language("language"),
  aboutOneXray("about-onexray"),
  appUpdate("app-update");

  final String segment;

  const AppPageDestination(this.segment);

  static const adaptiveDialogs = {
    serversImport,
    serverEditor,
    share,
    subscriptionEdit,
  };
}

extension AppNavigationContext on BuildContext {
  AppPrimaryDestination get currentPrimaryDestination {
    final path = GoRouterState.of(this).uri.path;
    return AppPrimaryDestination.fromPath(path);
  }

  String scopedPath(AppPageDestination destination) {
    final primary = currentPrimaryDestination;
    return "${primary.rootPath}/${destination.segment}";
  }

  void goPrimary(
    StatefulNavigationShell navigationShell,
    AppPrimaryDestination destination,
  ) {
    final index = AppPrimaryDestination.values.indexOf(destination);
    navigationShell.goBranch(
      index,
      initialLocation: navigationShell.currentIndex == index,
    );
  }

  void goPrimaryRoot(AppPrimaryDestination destination) {
    go(destination.rootPath);
  }

  Future<T?> pushScoped<T>(AppPageDestination destination, {Object? extra}) {
    return push<T>(scopedPath(destination), extra: extra);
  }

  Future<T?> pushAppUpdateDialog<T>(AppUpdateInfo updateInfo) {
    return pushScoped<T>(
      AppPageDestination.appUpdate,
      extra: AppUpdateDialogParams(updateInfo: updateInfo),
    );
  }
}
