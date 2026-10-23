import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
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
import 'package:onexray/service/shared/menu/tray/service.dart';
import 'package:onexray/service/shared/share/service.dart';

class AdaptiveMainShell extends StatefulWidget {
  const AdaptiveMainShell({
    super.key,
    required this.navigationShell,
    this.initializeServices,
  });

  final StatefulNavigationShell navigationShell;
  final Future<void> Function(BuildContext context)? initializeServices;

  @override
  State<AdaptiveMainShell> createState() => _AdaptiveMainShellState();
}

class _AdaptiveMainShellState extends State<AdaptiveMainShell> {
  Future<void>? _servicesReady;
  bool _menusAttached = false;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _servicesReady ??= _initializeServices();
    if (_menusAttached) _refreshQuickActions();
  }

  Future<void> _initializeServices() {
    ShareService().onIncomingShare = (text) async {
      if (mounted) {
        await context.pushScoped(AppPageDestination.serversImport, extra: text);
      }
    };
    return (widget.initializeServices ?? ServiceManager.serviceInit)(context);
  }

  void _refreshQuickActions() {
    unawaited(ShortCutService().refresh(AppLocalizations.of(context)!));
  }

  void _attachMenus() {
    if (_menusAttached) return;
    _menusAttached = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TrayService().onConfigurationChange = (values, label, validate) =>
          applyTrayConfiguration(context, values, label, validate);
      TrayService().onSubscriptionFormatConfirmation = (name) =>
          confirmTraySubscriptionFormat(context, name);
      ShortCutService().attach(
        (action) => handleMobileQuickAction(context, action),
      );
      _refreshQuickActions();
    });
  }

  @override
  void dispose() {
    ShortCutService().detach();
    TrayService().onConfigurationChange = null;
    TrayService().onSubscriptionFormatConfirmation = null;
    super.dispose();
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
              return _bottomNavigationScaffold(context, appUpdateInfo != null);
            },
          ),
        );
      },
    );
  }

  Widget _bottomNavigationScaffold(
    BuildContext context,
    bool appUpdateAvailable,
  ) {
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
          : DecoratedBox(
              key: const ValueKey('primary-mobile-navigation'),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: ColorManager.palette(context).border),
                ),
              ),
              child: NavigationBar(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: (index) => context.goPrimary(
                  navigationShell,
                  AppPrimaryDestination.values[index],
                ),
                destinations: [
                  for (final primary in AppPrimaryDestination.values)
                    NavigationDestination(
                      key: ValueKey('primary-navigation-${primary.name}'),
                      icon: _navigationIcon(
                        context,
                        primary,
                        appUpdateAvailable,
                      ),
                      label: _label(context, primary),
                    ),
                ],
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
      backgroundColor: nativeSidebar ? Colors.transparent : null,
      // Keep landscape cutouts outside the sidebar's usable content width.
      body: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            Container(
              key: const ValueKey('primary-desktop-navigation'),
              width: sidebarWidth,
              decoration: BoxDecoration(
                color: nativeSidebar ? Colors.transparent : palette.sidebar,
                border: BorderDirectional(
                  end: BorderSide(color: palette.sidebarBorder),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.sidebarHorizontal,
                    vertical: nativeSidebar
                        ? AppSpacing.macOSSidebarVertical
                        : AppSpacing.sidebarVertical,
                  ),
                  child: _sidebarContent(
                    context,
                    compact: compact,
                    nativeSidebar: nativeSidebar,
                    appUpdateInfo: appUpdateInfo,
                  ),
                ),
              ),
            ),
            Expanded(
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
          ],
        ),
      ),
    );
  }

  Widget _sidebarContent(
    BuildContext context, {
    required bool compact,
    required bool nativeSidebar,
    required AppUpdateInfo? appUpdateInfo,
  }) {
    final palette = ColorManager.palette(context);
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
                    padding: EdgeInsetsDirectional.fromSTEB(
                      compact
                          ? AppSpacing.sidebarCompactBrandStart
                          : AppSpacing.sidebarBrandStart,
                      AppSpacing.sidebarBrandTop,
                      compact
                          ? AppSpacing.sidebarCompactBrandStart
                          : AppSpacing.sidebarBrandStart,
                      nativeSidebar
                          ? AppSpacing.macOSSidebarBrandBottom
                          : AppSpacing.sidebarBrandBottom,
                    ),
                    child: Text(
                      'OneXray',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.desktopBrand.copyWith(
                        color: palette.brand,
                      ),
                    ),
                  ),
                  for (final primary in AppPrimaryDestination.values) ...[
                    if (primary.index > 0)
                      const SizedBox(height: AppSpacing.sidebarRowGap),
                    _desktopDestination(context, primary),
                  ],
                ],
              ),
              if (appUpdateInfo != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sidebarRowGap),
                  child: _DesktopUpdateReminder(
                    onTap: () => _showDesktopUpdate(context, appUpdateInfo),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopDestination(
    BuildContext context,
    AppPrimaryDestination primary,
  ) {
    final palette = ColorManager.palette(context);
    final selected = primary.index == navigationShell.currentIndex;
    final label = _label(context, primary);
    final color = selected ? palette.primary : palette.mutedStrong;
    return Semantics(
      key: ValueKey('primary-navigation-${primary.name}'),
      label: label,
      selected: selected,
      button: true,
      child: Material(
        color: selected ? palette.selectedSurface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(
            color: selected
                ? Color.lerp(palette.border, palette.primary, .2)!
                : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: () => context.goPrimary(navigationShell, primary),
          borderRadius: BorderRadius.circular(AppRadii.card),
          hoverColor: palette.surfaceHover,
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.sidebarRowHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(_icon(primary), size: 22, color: color),
                    const SizedBox(width: 14),
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
    );
  }

  void _showDesktopUpdate(BuildContext context, AppUpdateInfo updateInfo) {
    context.pushAppUpdateDialog(updateInfo);
  }

  Widget _navigationIcon(
    BuildContext context,
    AppPrimaryDestination primary,
    bool appUpdateAvailable,
  ) {
    final icon = Icon(_icon(primary));
    if (primary != AppPrimaryDestination.settings || !appUpdateAvailable) {
      return icon;
    }
    return _UpdateBadge(child: icon);
  }

  IconData _icon(AppPrimaryDestination primary) {
    return switch (primary) {
      AppPrimaryDestination.connect => LucideIcons.link,
      AppPrimaryDestination.servers => LucideIcons.layers3,
      AppPrimaryDestination.advanced => LucideIcons.terminal,
      AppPrimaryDestination.settings => LucideIcons.settings,
    };
  }

  String _label(BuildContext context, AppPrimaryDestination primary) {
    final localizations = AppLocalizations.of(context)!;
    return switch (primary) {
      AppPrimaryDestination.connect => localizations.prototypeConnect,
      AppPrimaryDestination.servers => localizations.prototypeServers,
      AppPrimaryDestination.advanced => localizations.prototypeAdvanced,
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
          child: SizedBox(
            width: double.infinity,
            height: 44,
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
