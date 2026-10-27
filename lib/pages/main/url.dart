import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/log/page.dart';
import 'package:onexray/pages/advanced/xray/log/params.dart';
import 'package:onexray/pages/advanced/xray/config/page.dart';
import 'package:onexray/pages/advanced/xray/config/params.dart';
import 'package:onexray/pages/advanced/xray/ping/page.dart';
import 'package:onexray/pages/advanced/xray/lan_proxy/page.dart';
import 'package:onexray/pages/advanced/xray/dialing/page.dart';
import 'package:onexray/pages/advanced/local_api/page.dart';
import 'package:onexray/pages/settings/about/page.dart';
import 'package:onexray/pages/settings/backup/page.dart';
import 'package:onexray/pages/advanced/tunnel/apple/page.dart';
import 'package:onexray/pages/advanced/tunnel/apple/wifi.dart';
import 'package:onexray/pages/advanced/tunnel/android/page.dart';
import 'package:onexray/pages/advanced/tunnel/android/automation/page.dart';
import 'package:onexray/pages/advanced/tunnel/android/apps.dart';
import 'package:onexray/pages/advanced/tunnel/windows/page.dart';
import 'package:onexray/pages/advanced/tunnel/interface/page.dart';
import 'package:onexray/pages/advanced/xray/geodata/page.dart';
import 'package:onexray/pages/advanced/xray/geodata/detail.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/pages/shared/share/page.dart';
import 'package:onexray/pages/shared/share/params.dart';
import 'package:onexray/pages/launch/splash/page.dart';
import 'package:onexray/pages/main/adaptive_shell.dart';
import 'package:onexray/pages/main/advanced.dart';
import 'package:onexray/pages/main/dialog_page.dart';
import 'package:onexray/pages/main/modal_route_observer.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/launch/setup/page.dart';
import 'package:onexray/pages/launch/setup/selectors.dart';
import 'package:onexray/pages/servers/import/page.dart';
import 'package:onexray/pages/servers/page.dart';
import 'package:onexray/pages/servers/order/controller.dart';
import 'package:onexray/pages/servers/order/page.dart';
import 'package:onexray/pages/connect/page.dart';
import 'package:onexray/pages/settings/page.dart';
import 'package:onexray/pages/connect/routing/smart/exit_picker.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/connect/routing/smart/exit_picker_controller.dart';
import 'package:onexray/pages/servers/editor/page.dart';
import 'package:onexray/pages/servers/subscription/page.dart';
import 'package:onexray/pages/connect/json_editor/page.dart';
import 'package:onexray/pages/connect/routing/smart/page.dart';
import 'package:onexray/pages/connect/routing/smart/regions.dart';
import 'package:onexray/pages/connect/routing/custom/page.dart';
import 'package:onexray/pages/connect/routing/custom/rule_page.dart';
import 'package:onexray/pages/settings/app_update/dialog.dart';
import 'package:onexray/pages/settings/app_update/params.dart';
import 'package:onexray/pages/settings/app_icon/page.dart';
import 'package:onexray/pages/advanced/xray/data_update/page.dart';
import 'package:onexray/pages/settings/desktop/page.dart';
import 'package:onexray/pages/settings/language/page.dart';
import 'package:onexray/pages/settings/theme/page.dart';
import 'package:onexray/pages/servers/subscription/params.dart';
import 'package:onexray/pages/theme/theme.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: "root",
);

final _rootModalObserver = AppModalRouteObserver();
final _primaryModalObservers = {
  for (final primary in AppPrimaryDestination.values)
    primary: AppModalRouteObserver(),
};
final _modalChanges = Listenable.merge([
  _rootModalObserver,
  ..._primaryModalObservers.values,
]);

abstract final class RouterPath {
  static const splash = "/splash";
  static const privacy = "/privacy";
  static const firstRun = "/firstRun";
  static const setup = "/setup";
  static const connect = "/connect";

  static final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    observers: [_rootModalObserver],
    initialLocation: RouterPath.splash,
    debugLogDiagnostics: true,
    routes: [
      GoRoute(path: RouterPath.splash, builder: (_, _) => const SplashPage()),
      GoRoute(path: RouterPath.setup, builder: (_, _) => const SetupPage()),
      GoRoute(
        path: '/setup/privacy',
        builder: (_, _) => const SetupPrivacyPage(),
      ),
      GoRoute(
        path: '/setup/interface',
        redirect: (_, state) =>
            state.extra is SetupInterfaceParams ? null : RouterPath.setup,
        builder: (_, state) =>
            SetupInterfacePage(params: state.extra as SetupInterfaceParams),
      ),
      GoRoute(
        path: '/setup/region',
        redirect: (_, state) =>
            state.extra is List<String> ? null : RouterPath.setup,
        builder: (_, state) =>
            DirectRegionsPage(selectedCodes: state.extra as List<String>),
      ),
      GoRoute(path: RouterPath.privacy, redirect: (_, _) => RouterPath.setup),
      GoRoute(path: RouterPath.firstRun, redirect: (_, _) => RouterPath.setup),
      StatefulShellRoute.indexedStack(
        // Forwarded branch events would overwrite the root modal state.
        notifyRootObserver: false,
        builder: (_, _, navigationShell) {
          return AdaptiveMainShell(
            navigationShell: navigationShell,
            modalChanges: _modalChanges,
            hasActiveModal: (primary) =>
                _rootModalObserver.hasPopupRoute ||
                _primaryModalObservers[primary]!.hasPopupRoute,
          );
        },
        branches: AppPrimaryDestination.values
            .map(_buildPrimaryBranch)
            .toList(),
      ),
    ],
  );
}

final _primaryNavigatorKeys = {
  for (final primary in AppPrimaryDestination.values)
    primary: GlobalKey<NavigatorState>(debugLabel: "${primary.name}Branch"),
};

StatefulShellBranch _buildPrimaryBranch(AppPrimaryDestination primary) {
  final root = _pageRoutes.firstWhere(
    (route) => route.destination == primary.page,
  );
  return StatefulShellBranch(
    navigatorKey: _primaryNavigatorKeys[primary],
    observers: [_primaryModalObservers[primary]!],
    routes: [
      GoRoute(
        path: primary.rootPath,
        builder: root.builder,
        routes: buildScopedPageRoutes(),
      ),
    ],
  );
}

List<GoRoute> buildScopedPageRoutes({bool? desktop, bool? android}) {
  final onDesktop = desktop ?? AppPlatform.isDesktop;
  final onAndroid = android ?? AppPlatform.isAndroid;
  return _pageRoutes
      .where(
        (route) =>
            (onDesktop || route.destination != AppPageDestination.localApi) &&
            (onAndroid ||
                route.destination != AppPageDestination.androidAutomation),
      )
      .map((route) {
        if (route.destination == AppPageDestination.appUpdate) {
          return GoRoute(
            path: route.destination.segment,
            pageBuilder: (context, state) => AppDialogPage<void>(
              key: state.pageKey,
              builder: (context) => route.builder(context, state),
            ),
          );
        }
        if (AppPageDestination.adaptiveDialogs.contains(route.destination)) {
          return GoRoute(
            path: route.destination.segment,
            pageBuilder: (context, state) => AppDialogPage<dynamic>(
              key: state.pageKey,
              barrierColor: ColorManager.palette(context).overlay,
              useSafeArea: false,
              builder: (context) =>
                  AppDialogFrame(child: route.builder(context, state)),
            ),
          );
        }
        return GoRoute(
          path: route.destination.segment,
          builder: (context, state) => Theme(
            data: AppTheme.secondaryPage(context),
            child: Builder(builder: (context) => route.builder(context, state)),
          ),
        );
      })
      .toList();
}

typedef _PageRouteBuilder = Widget Function(
  BuildContext context,
  GoRouterState state,
);

class _PageRoute {
  final AppPageDestination destination;
  final _PageRouteBuilder builder;

  const _PageRoute(this.destination, this.builder);
}

_PageRoute _route(AppPageDestination destination, _PageRouteBuilder builder) {
  return _PageRoute(destination, builder);
}

final _pageRoutes = <_PageRoute>[
  _route(AppPageDestination.connect, (_, _) => const ConnectPage()),
  _route(AppPageDestination.servers, (_, _) => const ServersPage()),
  _route(AppPageDestination.advanced, (_, _) => const AdvancedRootPage()),
  _route(AppPageDestination.settings, (_, _) => const SettingsPage()),
  _route(AppPageDestination.localApi, (_, _) => const LocalApiPage()),
  _route(AppPageDestination.lanProxy, (_, _) => const LanProxyPage()),
  _route(AppPageDestination.serverDialing, (_, _) => const ServerDialingPage()),
  _route(
    AppPageDestination.androidAutomation,
    (_, _) => const AndroidAutomationPage(),
  ),
  _route(
    AppPageDestination.appleVpn,
    (_, state) => _withExtra<PolicyEditorDraft>(
      state,
      (draft) => AppleVpnPage(
        draft: draft,
        openWifi: (context, draft) => context.pushScoped<bool>(
          AppPageDestination.appleWifi,
          extra: draft,
        ),
      ),
    ),
  ),
  _route(
    AppPageDestination.appleWifi,
    (_, state) => _withExtra<PolicyEditorDraft>(
      state,
      (draft) => AppleWifiPage(draft: draft),
    ),
  ),
  _route(
    AppPageDestination.androidVpn,
    (_, state) => _withExtra<PolicyEditorDraft>(
      state,
      (draft) => AndroidVpnPage(
        draft: draft,
        openAutomation: AppPlatform.isAndroid
            ? (context) =>
                  context.pushScoped(AppPageDestination.androidAutomation)
            : null,
        openApps: (context, mode, selected) => context.pushScoped<List<String>>(
          AppPageDestination.androidApps,
          extra: (mode, selected),
        ),
      ),
    ),
  ),
  _route(
    AppPageDestination.androidApps,
    (_, state) => _withExtra<(String, List<String>)>(
      state,
      (params) => AndroidAppsPage(mode: params.$1, selected: params.$2),
    ),
  ),
  _route(
    AppPageDestination.windowsVpn,
    (_, state) => _withExtra<PolicyEditorDraft>(
      state,
      (draft) => WindowsVpnPage(
        draft: draft,
        openInterface: (context, draft) => context.pushScoped<bool>(
          AppPageDestination.outboundInterface,
          extra: draft,
        ),
      ),
    ),
  ),
  _route(
    AppPageDestination.outboundInterface,
    (_, state) => _withExtra<PolicyEditorDraft>(
      state,
      (draft) => OutboundInterfacePage(draft: draft),
    ),
  ),
  _route(
    AppPageDestination.routingData,
    (_, _) => GeoDataPage(
      openFile: (context, id) =>
          context.pushScoped(AppPageDestination.routingDataFile, extra: id),
    ),
  ),
  _route(
    AppPageDestination.routingDataFile,
    (_, state) => _withExtra<int>(state, (id) => GeoDataFilePage(fileId: id)),
  ),
  _route(
    AppPageDestination.serversImport,
    (_, state) => ServersImportPage(initialText: state.extra as String?),
  ),
  _route(
    AppPageDestination.serverGroup,
    (_, state) => _withExtra<ServerGroupParams>(
      state,
      (params) => ServerGroupPage(params: params),
    ),
  ),
  _route(
    AppPageDestination.manualServerOrder,
    (_, state) => _withExtra<ManualOrderParams>(
      state,
      (params) => ManualOrderPage(params: params),
    ),
  ),
  _route(
    AppPageDestination.serverEditor,
    (_, state) =>
        _withExtra<int>(state, (id) => ServerEditorPage(serverId: id)),
  ),
  _route(
    AppPageDestination.serverFinalExitPicker,
    (_, state) => _withExtra<ServerExitPickerParams>(
      state,
      (params) => ServerExitPickerPage(params: params),
    ),
  ),
  _route(
    AppPageDestination.rawEditor,
    (_, state) =>
        JsonConfigurationEditorPage(configurationId: state.extra as int?),
  ),
  _route(
    AppPageDestination.smartRouting,
    (_, _) => SmartRoutingEditorPage(
      openRegions: (context, selected) => context.pushScoped<List<String>>(
        AppPageDestination.directRegions,
        extra: selected,
      ),
      openFinalExit: (context, params) => context.pushScoped<ServerExitChoice>(
        AppPageDestination.serverFinalExitPicker,
        extra: params,
      ),
    ),
  ),
  _route(
    AppPageDestination.directRegions,
    (_, state) => DirectRegionsPage(
      selectedCodes: (state.extra as List?)?.cast<String>() ?? [],
    ),
  ),
  _route(
    AppPageDestination.customRouting,
    (_, state) => CustomRoutingEditorPage(
      profileId: state.extra as int?,
      openRule: (context, rule) => context.pushScoped<RoutingRuleState>(
        AppPageDestination.customRule,
        extra: rule,
      ),
    ),
  ),
  _route(
    AppPageDestination.advancedRouting,
    (_, state) => JsonConfigurationEditorPage(
      configurationId: state.extra as int?,
      kind: ConfigurationKind.customAdvanced,
    ),
  ),
  _route(
    AppPageDestination.customRule,
    (_, state) => CustomRoutingRulePage(rule: state.extra as RoutingRuleState?),
  ),
  _route(
    AppPageDestination.share,
    (_, state) => _withExtra<SharePageParams>(
      state,
      (params) => SharePage(params: params),
    ),
  ),
  _route(
    AppPageDestination.subscriptionEdit,
    (_, state) => _withExtra<SubscriptionEditParams>(
      state,
      (params) => SubscriptionEditorPage(subscriptionId: params.id),
    ),
  ),
  _route(AppPageDestination.ping, (_, _) => const PingPage()),
  _route(
    AppPageDestination.logFile,
    (_, state) => _withExtra<LogFileViewerParams>(
      state,
      (params) => LogFileViewerPage(params: params),
    ),
  ),
  _route(
    AppPageDestination.configFileViewer,
    (_, state) => _withExtra<ConfigFileViewerParams>(
      state,
      (params) => ConfigFileViewerPage(params: params),
    ),
  ),
  _route(AppPageDestination.autoUpdate, (_, _) => const AutoUpdatePage()),
  _route(AppPageDestination.backup, (_, _) => const BackupPage()),
  _route(
    AppPageDestination.desktopSettings,
    (_, _) => const DesktopSettingsPage(),
  ),
  _route(AppPageDestination.appIcon, (_, _) => const AppIconPage()),
  _route(AppPageDestination.theme, (_, _) => const ThemePage()),
  _route(AppPageDestination.language, (_, _) => const LanguagePage()),
  _route(AppPageDestination.aboutOneXray, (_, _) => const AboutOneXrayPage()),
  _route(
    AppPageDestination.appUpdate,
    (_, state) => _withDialogExtra<AppUpdateDialogParams>(
      state,
      (params) => AppUpdateDialog(params: params),
    ),
  ),
];

Widget _withExtra<T>(GoRouterState state, Widget Function(T params) builder) {
  final extra = state.extra;
  if (extra is T) {
    return builder(extra);
  }
  return const _InvalidRoutePage();
}

Widget _withDialogExtra<T>(
  GoRouterState state,
  Widget Function(T params) builder,
) {
  final extra = state.extra;
  if (extra is T) {
    return builder(extra);
  }
  return const _InvalidRouteDialog();
}

class _InvalidRoutePage extends StatelessWidget {
  const _InvalidRoutePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageAppBar(
        title: Text(
          AppLocalizations.of(context)!.prototypeTemporarilyUnavailable,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              AppLocalizations.of(context)!.prototypeTemporarilyUnavailable,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _InvalidRouteDialog extends StatelessWidget {
  const _InvalidRouteDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        AppLocalizations.of(context)!.prototypeTemporarilyUnavailable,
      ),
      content: Text(
        AppLocalizations.of(context)!.prototypeTemporarilyUnavailable,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.prototypeClose),
        ),
      ],
    );
  }
}
