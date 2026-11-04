import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/main/desktop_window.dart';
import 'package:onexray/pages/main/menu_actions.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';
import 'package:onexray/service/manager.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/shared/menu/short_cut/service.dart';
import 'package:onexray/service/shared/menu/settings/service.dart';
import 'package:onexray/service/shared/menu/tray/service.dart';
import 'package:onexray/service/shared/share/service.dart';

class AdaptiveMainShell extends StatefulWidget {
  const AdaptiveMainShell({
    super.key,
    required this.navigationShell,
    required this.hasActiveModal,
    this.initializeServices,
    this.settingsMenuService,
    this.shareService,
    this.modalChanges,
  });

  final StatefulNavigationShell navigationShell;
  final bool Function(AppPrimaryDestination) hasActiveModal;
  final Future<void> Function(BuildContext context)? initializeServices;
  final MacOSSettingsMenuService? settingsMenuService;
  final ShareService? shareService;
  final Listenable? modalChanges;

  @override
  State<AdaptiveMainShell> createState() => _AdaptiveMainShellState();
}

class _AdaptiveMainShellState extends State<AdaptiveMainShell> {
  Future<void>? _servicesReady;
  bool _menusAttached = false;
  late final _settingsMenu =
      widget.settingsMenuService ?? MacOSSettingsMenuService();
  late final _shareService = widget.shareService ?? ShareService();
  StreamSubscription<void>? _appLinkSubscription;
  GoRouter? _router;
  IncomingAppLink? _activeAppLink;
  bool _appLinkDrainScheduled = false;
  bool _settingsNavigationScheduled = false;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _servicesReady ??= _initializeServices();
    if (_menusAttached) _refreshQuickActions();
  }

  Future<void> _initializeServices() {
    return (widget.initializeServices ?? ServiceManager.serviceInit)(context);
  }

  void _scheduleAppLinkDrain() {
    if (!mounted || _appLinkDrainScheduled) return;
    _appLinkDrainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appLinkDrainScheduled = false;
      if (mounted) unawaited(_drainAppLink());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _drainAppLink() async {
    if (_activeAppLink != null || !_canOpenAppLink()) return;
    final event = _shareService.claimNextAppLink();
    if (event == null) return;
    _activeAppLink = event;
    try {
      await context.pushScoped(
        AppPageDestination.serversImport,
        extra: event.uri.toString(),
      );
    } catch (_) {
      ygLogger('open incoming share failed');
    } finally {
      _shareService.finishAppLink(event);
      if (identical(_activeAppLink, event)) _activeAppLink = null;
      if (mounted) _scheduleAppLinkDrain();
    }
  }

  void _refreshQuickActions() {
    unawaited(ShortCutService().refresh(AppLocalizations.of(context)!));
  }

  void _attachMenus() {
    if (_menusAttached) return;
    _menusAttached = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _router = GoRouter.of(context);
      _router!.routerDelegate.addListener(_scheduleAppLinkDrain);
      widget.modalChanges?.addListener(_scheduleAppLinkDrain);
      _appLinkSubscription = _shareService.pendingAppLinksChanged.listen(
        (_) => _scheduleAppLinkDrain(),
      );
      // Links received during Setup or service initialization precede this
      // subscription. Read once after the main navigation has rendered.
      _scheduleAppLinkDrain();
      TrayService().onConfigurationChange = (values, label, validate) =>
          applyTrayConfiguration(context, values, label, validate);
      TrayService().onSubscriptionFormatConfirmation = (name) =>
          confirmTraySubscriptionFormat(context, name);
      ShortCutService().attach(
        (action) => handleMobileQuickAction(context, action),
      );
      _settingsMenu.attach(
        owner: this,
        canNavigate: _canOpenSettings,
        openSettings: _openSettings,
      );
      _refreshQuickActions();
    });
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_scheduleAppLinkDrain);
    widget.modalChanges?.removeListener(_scheduleAppLinkDrain);
    unawaited(_appLinkSubscription?.cancel());
    final activeAppLink = _activeAppLink;
    if (activeAppLink != null) _shareService.finishAppLink(activeAppLink);
    _settingsMenu.detach(this);
    ShortCutService().detach();
    TrayService().onConfigurationChange = null;
    TrayService().onSubscriptionFormatConfirmation = null;
    super.dispose();
  }

  bool _canOpenAppLink() {
    if (!_canOpenSettings()) return false;
    final location = GoRouter.of(context)
        .routerDelegate
        .currentConfiguration
        .last
        .matchedLocation;
    // These workflows used to be routed dialogs. Their full-page presentation
    // permits Settings branch changes, but an incoming import must still wait
    // rather than push another form over the active manual draft.
    return !{
      AppPageDestination.serversImport,
      AppPageDestination.serverEditor,
      AppPageDestination.subscriptionEdit,
    }.any((page) => location.endsWith('/${page.segment}'));
  }

  bool _canOpenSettings() {
    if (!mounted || !_menusAttached) return false;
    final location = GoRouter.of(context)
        .routerDelegate
        .currentConfiguration
        .last
        .matchedLocation;
    if ({
      ...AppPageDestination.adaptiveDialogs,
      AppPageDestination.appUpdate,
    }.any((page) => location.endsWith('/${page.segment}'))) {
      return false;
    }
    for (final primary in AppPrimaryDestination.values) {
      if (location == primary.rootPath ||
          location.startsWith('${primary.rootPath}/')) {
        return !widget.hasActiveModal(primary);
      }
    }
    return false;
  }

  void _openSettings() {
    if (_settingsNavigationScheduled || !_canOpenSettings()) return;
    _settingsNavigationScheduled = true;
    // go_router saves a branch's latest match list when its Shell widget is
    // updated. Switching before a pending push builds would save the old stack
    // and discard that page. Let it commit, then recheck popup admission.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settingsNavigationScheduled = false;
      if (!_canOpenSettings()) return;
      navigationShell.goBranch(
        AppPrimaryDestination.settings.index,
        initialLocation: false,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _retry() {
    final servicesReady = _initializeServices();
    setState(() {
      _servicesReady = servicesReady;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _servicesReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      appFailureMessage(
                        AppLocalizations.of(context)!,
                        snapshot.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('service-initialization-retry'),
                      onPressed: _retry,
                      child: Text(AppLocalizations.of(context)!.buttonRetry),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        _attachMenus();
        return BlocSelector<AppEventBus, AppEventBusState, AppUpdateInfo?>(
          selector: (state) => state.appUpdateInfo,
          builder: (context, appUpdateInfo) => LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > AppLayout.mobileBreakpoint) {
                return _railScaffold(
                  context,
                  constraints.maxWidth,
                  appUpdateInfo,
                );
              }
              return _bottomNavigationScaffold(context);
            },
          ),
        );
      },
    );
  }

  Widget _bottomNavigationScaffold(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar:
          navigationShell
                  .shellRouteContext
                  .match
                  .matches
                  .last
                  .matchedLocation !=
              AppPrimaryDestination
                  .values[navigationShell.currentIndex]
                  .rootPath
          ? null
          : navigationShell.currentIndex == AppPrimaryDestination.settings.index
          ? null
          : SafeArea(
              top: false,
              child: Container(
                key: const ValueKey('primary-mobile-navigation'),
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final primary in AppPrimaryDestination.values.where(
                        (p) => p != AppPrimaryDestination.settings,
                      ))
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: _mobileDestination(context, primary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _mobileDestination(
    BuildContext context,
    AppPrimaryDestination primary,
  ) {
    final palette = ColorManager.palette(context);
    final selected = primary.index == navigationShell.currentIndex;
    final color = selected
        ? palette.primaryForeground
        : palette.mutedForeground;
    return Semantics(
      key: ValueKey('primary-navigation-${primary.name}'),
      label: _label(context, primary),
      selected: selected,
      button: true,
      child: Material(
        color: selected ? palette.primarySolid : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: InkWell(
          onTap: () => context.goPrimary(navigationShell, primary),
          borderRadius: BorderRadius.circular(AppRadii.control),
          hoverColor: selected ? palette.primarySolid : palette.secondary,
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: AppLayout.touchExtent(
                  56,
                  platform: Theme.of(context).platform,
                ),
                minWidth: AppLayout.touchExtent(
                  0,
                  platform: Theme.of(context).platform,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_icon(primary), size: 19, color: color),
                    const SizedBox(height: 5),
                    Text(
                      _label(context, primary),
                      textAlign: TextAlign.center,
                      style:
                          (selected
                                  ? AppTypography.selectedMobileNavigationLabel
                                  : AppTypography.mobileNavigationLabel)
                              .copyWith(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _railScaffold(
    BuildContext context,
    double width,
    AppUpdateInfo? appUpdateInfo,
  ) {
    final compact = width <= AppLayout.compactDesktopBreakpoint;
    final sidebarWidth = !compact
        ? AppLayout.desktopSidebarWidth
        : AppLayout.compactSidebarWidth;
    final palette = ColorManager.palette(context);
    final nativeSidebar = DesktopWindowFrame.hasNativeSidebar(context);
    return Scaffold(
      backgroundColor: palette.sidebar,
      // Keep landscape cutouts outside the sidebar's usable content width.
      body: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            Container(
              key: const ValueKey('primary-desktop-navigation'),
              width: sidebarWidth,
              color: palette.sidebar,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sidebarHorizontal,
                    AppSpacing.sidebarVertical,
                    AppSpacing.sidebarHorizontal,
                    AppSpacing.sidebarBottom,
                  ),
                  child: _sidebarContent(context, appUpdateInfo: appUpdateInfo),
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(
                key: const ValueKey('primary-content'),
                color: palette.background,
                child:
                    nativeSidebar &&
                        Directionality.of(context) == TextDirection.ltr
                    ? MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: navigationShell,
                      )
                    // In RTL the content, not the sidebar, is below the native
                    // controls on the physical left. Keep its local top inset.
                    : navigationShell,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarContent(
    BuildContext context, {
    required AppUpdateInfo? appUpdateInfo,
  }) {
    final palette = ColorManager.palette(context);
    final localizations = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        primary: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.sidebarBrandStart,
                      0,
                      0,
                      AppSpacing.sidebarBrandBottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Image.asset(
                              'assets/logo.png',
                              width: 32,
                              height: 32,
                              excludeFromSemantics: true,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'OneXray',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.desktopBrand.copyWith(
                                  color: palette.foreground,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        Text(
                          localizations.navigationTagline,
                          style: AppTypography.sidebarTagline.copyWith(
                            color: palette.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _sidebarLabel(context, localizations.navigationWorkspace),
                  for (final primary in const [
                    AppPrimaryDestination.connect,
                    AppPrimaryDestination.servers,
                    AppPrimaryDestination.routing,
                  ])
                    _desktopDestination(context, primary),
                  const SizedBox(height: 22),
                  _sidebarLabel(context, localizations.navigationSystemAndCore),
                  for (final primary in const [
                    AppPrimaryDestination.tunnel,
                    AppPrimaryDestination.xray,
                  ])
                    _desktopDestination(context, primary),
                ],
              ),
              Column(
                children: [
                  _desktopDestination(context, AppPrimaryDestination.settings),
                  if (appUpdateInfo != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: AppSpacing.sidebarRowGap,
                      ),
                      child: _DesktopUpdateReminder(
                        onTap: () => _showDesktopUpdate(context, appUpdateInfo),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebarLabel(BuildContext context, String label) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 0, 8),
    child: Text(
      label,
      style: AppTypography.sidebarGroupLabel.copyWith(
        color: ColorManager.palette(context).mutedForeground,
      ),
    ),
  );

  Widget _desktopDestination(
    BuildContext context,
    AppPrimaryDestination primary,
  ) {
    final palette = ColorManager.palette(context);
    final selected = primary.index == navigationShell.currentIndex;
    final label = _label(context, primary);
    final color = selected ? palette.primary : palette.foreground;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sidebarRowGap),
      child: Semantics(
        key: ValueKey('primary-navigation-${primary.name}'),
        label: label,
        selected: selected,
        button: true,
        child: Material(
          color: selected ? palette.card : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: InkWell(
            onTap: () => context.goPrimary(navigationShell, primary),
            borderRadius: BorderRadius.circular(AppRadii.control),
            hoverColor: palette.surfaceHover,
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: AppLayout.touchExtent(
                    AppSpacing.sidebarRowHeight,
                    platform: Theme.of(context).platform,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(_icon(primary), size: 18, color: color),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          label,
                          style:
                              (selected
                                      ? AppTypography.selectedNavigationLabel
                                      : AppTypography.navigationLabel)
                                  .copyWith(color: color),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDesktopUpdate(BuildContext context, AppUpdateInfo updateInfo) {
    context.pushAppUpdateDialog(updateInfo);
  }

  IconData _icon(AppPrimaryDestination primary) {
    return switch (primary) {
      AppPrimaryDestination.connect => LucideIcons.power,
      AppPrimaryDestination.servers => LucideIcons.server,
      AppPrimaryDestination.routing => LucideIcons.route,
      AppPrimaryDestination.tunnel => LucideIcons.shieldCheck,
      AppPrimaryDestination.xray => LucideIcons.activity,
      AppPrimaryDestination.settings => LucideIcons.settings2,
    };
  }

  String _label(BuildContext context, AppPrimaryDestination primary) {
    final localizations = AppLocalizations.of(context)!;
    return switch (primary) {
      AppPrimaryDestination.connect => localizations.prototypeConnect,
      AppPrimaryDestination.servers => localizations.prototypeServers,
      AppPrimaryDestination.routing => localizations.navigationRouting,
      AppPrimaryDestination.tunnel => localizations.prototypeVpnTunnel,
      AppPrimaryDestination.xray => 'Xray',
      AppPrimaryDestination.settings => localizations.prototypeSettings,
    };
  }
}

class _DesktopUpdateReminder extends StatelessWidget {
  const _DesktopUpdateReminder({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)!.appUpdateAvailable;
    final palette = ColorManager.palette(context);
    return Tooltip(
      message: label,
      child: Material(
        color: palette.sidebarAccent,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: AppLayout.touchExtent(
                44,
                platform: Theme.of(context).platform,
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.controlHorizontal,
                ),
                child: Row(
                  children: [
                    const _UpdateBadge(
                      child: Icon(LucideIcons.download, size: 19),
                    ),
                    const SizedBox(width: AppSpacing.actionGap),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.desktopUpdateLabel.copyWith(
                          color: palette.sidebarAccentForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Badge(
      smallSize: 8,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: child,
    );
  }
}
