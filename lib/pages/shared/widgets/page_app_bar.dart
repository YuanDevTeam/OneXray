import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:macos_window_utils/widgets/macos_toolbar_passthrough.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/main/desktop_window.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Keeps the themed AppBar while forwarding clicks on controls that overlap
/// the native macOS titlebar. Empty titlebar space keeps native window gestures.
class PageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PageAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.bottom,
  }) : description = null,
       headingAction = null,
       inlineHeadingAction = false,
       _headingHeight = null;

  const PageAppBar._({
    super.key,
    required this.title,
    this.description,
    this.headingAction,
    this.inlineHeadingAction = false,
    this.leading,
    this.actions,
    this.bottom,
    required this._headingHeight,
  });

  factory PageAppBar.forPage(
    BuildContext context, {
    Key? key,
    required Widget title,
    String? description,
    Widget? headingAction,
    bool inlineHeadingAction = false,
    Widget? leading,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
  }) {
    final viewport = MediaQuery.sizeOf(context);
    final mobile = viewport.width <= AppLayout.mobileBreakpoint;
    final hasShell = GoRouter.maybeOf(context) != null;
    final sidebar = !mobile && hasShell
        ? (viewport.width <= AppLayout.compactDesktopBreakpoint
                  ? AppLayout.compactSidebarWidth
                  : AppLayout.desktopSidebarWidth) +
              8
        : 0.0;
    final width = (viewport.width - sidebar - (mobile ? 32 : 56)).clamp(
      1.0,
      double.infinity,
    );
    final effectiveDescription =
        description ?? _defaultDescription(context, title);
    final style = mobile
        ? AppTypography.mobilePageTitle
        : AppTypography.pageTitle;
    double textHeight(String text, TextStyle textStyle) {
      final painter =
          TextPainter(
            text: TextSpan(
              text: text,
              style: textStyle.copyWith(fontFamily: AppFontFamily.sans),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(
            maxWidth:
                headingAction != null && (width >= 540 || inlineHeadingAction)
                ? (width - 20) / 2
                : width,
          );
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final titleHeight = title is Text && title.data != null
        ? textHeight(title.data!, style.merge(title.style))
        : MediaQuery.textScalerOf(context).scale(style.fontSize!) * 1.45;
    final blockHeight =
        titleHeight +
        (effectiveDescription == null || effectiveDescription.isEmpty
            ? 0
            : 6 + textHeight(effectiveDescription, AppTypography.rowValue));
    final scaledExtra =
        math.max(0, MediaQuery.textScalerOf(context).scale(14) - 14) * 1.45;
    final actionHeight = AppLayout.touchExtent(
      (mobile ? 48 : 42) + scaledExtra,
      platform: Theme.of(context).platform,
    );
    final naturalHeadingHeight =
        (mobile ? 20.0 : 24.0) +
        8 +
        (headingAction == null
            ? blockHeight
            : width < 540 && !inlineHeadingAction
            ? blockHeight + 16 + actionHeight
            : math.max(blockHeight, actionHeight));
    final media = MediaQuery.of(context);
    final headingBudget = math.max(
      44.0,
      viewport.height -
          media.padding.vertical -
          media.viewInsets.bottom -
          56 -
          180 -
          (bottom?.preferredSize.height ?? 0),
    );
    final headingHeight = math.min(naturalHeadingHeight, headingBudget);
    return PageAppBar._(
      key: key,
      title: title,
      description: effectiveDescription,
      headingAction: headingAction,
      inlineHeadingAction: inlineHeadingAction,
      leading: leading,
      actions: actions,
      bottom: bottom,
      headingHeight: headingHeight,
    );
  }

  final Widget title;
  final String? description;
  final Widget? headingAction;

  /// Keeps a compact page action beside a wrapping title on narrow screens.
  /// The action is constrained to half the heading so identity remains visible.
  final bool inlineHeadingAction;
  final double? _headingHeight;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  // Retain AppBar's theme-aware preferred size, including its optional tabs.
  @override
  Size get preferredSize => _headingHeight == null
      ? AppBar(bottom: bottom).preferredSize
      : Size.fromHeight(
          56 + _headingHeight + (bottom?.preferredSize.height ?? 0),
        );

  @override
  Widget build(BuildContext context) {
    final insets = MacOSWindowInsets.maybeOf(context);
    final route = ModalRoute.of(context);
    final forwardClicks =
        insets != null &&
        insets.titlebarHeight > 0 &&
        MediaQuery.paddingOf(context).top == 0 &&
        TickerMode.valuesOf(context).enabled &&
        (route?.isCurrent ?? true);
    var effectiveLeading = leading;
    if (forwardClicks && effectiveLeading == null) {
      if (Scaffold.maybeOf(context)?.hasDrawer ?? false) {
        effectiveLeading = const DrawerButton();
      } else if (route?.impliesAppBarDismissal ?? false) {
        effectiveLeading = route!.fullscreenDialog
            ? const CloseButton()
            : const BackButton();
      }
    }
    final effectiveActions = <Widget>[...?actions];
    Widget? mobileSettingsAction;
    final router = GoRouter.maybeOf(context);
    if (router != null &&
        route != null &&
        route.isFirst &&
        route.isCurrent &&
        TickerMode.valuesOf(context).enabled &&
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint) {
      final match = router.routerDelegate.currentConfiguration.lastOrNull;
      final settings = route.settings;
      // Imperative routes (including Page-backed routes not owned by GoRouter)
      // have no GoRouterState association. Its ancestor lookup can loop on a
      // nested Navigator, so read the active match without walking ancestors.
      final path = match?.matchedLocation;
      if (settings is Page<Object?> &&
          match != null &&
          settings.key == match.pageKey &&
          AppPrimaryDestination.values.any(
            (p) => p != AppPrimaryDestination.settings && p.rootPath == path,
          )) {
        mobileSettingsAction = IconButton(
          key: const ValueKey('mobile-settings-action'),
          tooltip: AppLocalizations.of(context)!.prototypeSettings,
          icon: const Icon(LucideIcons.settings2),
          onPressed: () =>
              router.push<void>('$path/${AppPageDestination.settings.segment}'),
        );
      }
    }
    if (_headingHeight != null) {
      final mobile =
          MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
      final palette = ColorManager.palette(context);
      final routeLeading =
          effectiveLeading ??
          ((Scaffold.maybeOf(context)?.hasDrawer ?? false)
              ? const DrawerButton()
              : (route?.impliesAppBarDismissal ?? false)
              ? route!.fullscreenDialog
                    ? const CloseButton()
                    : const BackButton()
              : null);
      final bus = context.read<AppEventBus?>();
      final toolbarActions = [
        ...effectiveActions,
        if (bus != null) _PageThemeToggle(bus: bus),
        ?mobileSettingsAction,
      ];
      Widget passThrough(Widget child) =>
          forwardClicks ? _AnimatedToolbarPassthrough(child: child) : child;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            Theme.of(context).appBarTheme.systemOverlayStyle ??
            SystemUiOverlayStyle.dark,
        child: Material(
          color: palette.header,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 56,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 24),
                    child: Row(
                      children: [
                        if (routeLeading != null) passThrough(routeLeading),
                        Expanded(child: _toolbarIdentity(context, mobile)),
                        for (final action in toolbarActions)
                          passThrough(action),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: _headingHeight,
                  child: SingleChildScrollView(
                    key: const ValueKey('page-heading'),
                    primary: false,
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 16 : 28,
                      mobile ? 20 : 24,
                      mobile ? 16 : 28,
                      8,
                    ),
                    child: _pageHeading(context, mobile),
                  ),
                ),
                ?bottom,
              ],
            ),
          ),
        ),
      );
    }
    return AppBar(
      title: title,
      leading: forwardClicks && effectiveLeading != null
          ? _AnimatedToolbarPassthrough(child: effectiveLeading)
          : effectiveLeading,
      actions: forwardClicks
          ? [
              ...effectiveActions,
              ?mobileSettingsAction,
            ].map((child) => _AnimatedToolbarPassthrough(child: child)).toList()
          : [...effectiveActions, ?mobileSettingsAction],
      bottom: bottom,
    );
  }

  Widget _pageHeading(BuildContext context, bool mobile) {
    final palette = ColorManager.palette(context);
    final identity = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: DefaultTextStyle(
            style:
                (mobile
                        ? AppTypography.mobilePageTitle
                        : AppTypography.pageTitle)
                    .copyWith(
                      color: palette.foreground,
                      fontFamily: AppFontFamily.sans,
                    ),
            child: title,
          ),
        ),
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            style: AppTypography.rowValue.copyWith(
              color: palette.mutedForeground,
            ),
          ),
        ],
      ],
    );
    if (headingAction == null) return identity;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 540 && !inlineHeadingAction) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [identity, const SizedBox(height: 16), headingAction!],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: identity),
            const SizedBox(width: 20),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (constraints.maxWidth - 20) / 2,
              ),
              child: headingAction!,
            ),
          ],
        );
      },
    );
  }

  static String? _defaultDescription(BuildContext context, Widget title) {
    if (title is! Text) return null;
    final l = AppLocalizations.of(context);
    if (l == null) return null;
    return switch (title.data) {
      final value when value == l.prototypeSettings =>
        l.settingsOverviewDescription,
      final value when value == l.prototypeVpnTunnel => l.pageTunnelDescription,
      final value when value == l.prototypeXrayRuntimeDiagnostics =>
        l.pageXrayDescription,
      final value when value == l.navigationRouting => l.pageRoutingDescription,
      _ => null,
    };
  }

  Widget _toolbarIdentity(BuildContext context, bool mobile) {
    final palette = ColorManager.palette(context);
    if (mobile) {
      return Row(
        children: [
          Image.asset(
            'assets/logo.png',
            width: 26,
            height: 26,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'OneXray',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.headerBrand.copyWith(
                color: palette.foreground,
              ),
            ),
          ),
        ],
      );
    }
    final l = AppLocalizations.of(context)!;
    final path = GoRouter.maybeOf(context)
        ?.routerDelegate
        .currentConfiguration
        .uri
        .path;
    final destination = path == null
        ? null
        : AppPrimaryDestination.fromPath(path);
    final (icon, label) = switch (destination) {
      AppPrimaryDestination.connect => (LucideIcons.power, l.prototypeConnect),
      AppPrimaryDestination.servers => (LucideIcons.server, l.prototypeServers),
      AppPrimaryDestination.routing => (LucideIcons.route, l.navigationRouting),
      AppPrimaryDestination.tunnel => (
        LucideIcons.shieldCheck,
        l.prototypeVpnTunnel,
      ),
      AppPrimaryDestination.xray => (LucideIcons.activity, 'Xray'),
      AppPrimaryDestination.settings => (
        LucideIcons.settings2,
        l.prototypeSettings,
      ),
      null => (LucideIcons.panelTop, 'OneXray'),
    };
    return Row(
      children: [
        Icon(icon, size: 16, color: palette.mutedForeground),
        const SizedBox(width: 10),
        Text(
          l.navigationWorkspace,
          style: AppTypography.breadcrumb.copyWith(
            color: palette.mutedForeground,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '/',
          style: AppTypography.breadcrumb.copyWith(
            color: palette.mutedForeground,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.breadcrumbCurrent.copyWith(
              color: palette.foreground,
            ),
          ),
        ),
      ],
    );
  }
}

class _PageThemeToggle extends StatefulWidget {
  const _PageThemeToggle({required this.bus});
  final AppEventBus bus;
  @override
  State<_PageThemeToggle> createState() => _PageThemeToggleState();
}

class _PageThemeToggleState extends State<_PageThemeToggle> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final l = AppLocalizations.of(context)!;
    return IconButton(
      tooltip: dark ? l.headerSwitchToLight : l.headerSwitchToDark,
      icon: Icon(dark ? LucideIcons.sun : LucideIcons.moon, size: 18),
      onPressed: _saving
          ? null
          : () async {
              setState(() => _saving = true);
              try {
                await widget.bus.updateThemeCode(
                  dark ? ThemeCode.light : ThemeCode.dark,
                );
              } catch (error) {
                if (context.mounted) {
                  ContextAlert.showToast(context, appFailureMessage(l, error));
                }
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
    );
  }
}

/// Route transitions transform the page without laying out its buttons again.
class _AnimatedToolbarPassthrough extends StatefulWidget {
  const _AnimatedToolbarPassthrough({required this.child});

  final Widget child;

  @override
  State<_AnimatedToolbarPassthrough> createState() =>
      _AnimatedToolbarPassthroughState();
}

class _AnimatedToolbarPassthroughState
    extends State<_AnimatedToolbarPassthrough> {
  final _passthrough = GlobalKey<MacosToolbarPassthroughState>();
  List<Animation<double>> _animations = [];
  bool _updateScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final animation in _animations) {
      animation.removeListener(_updateAfterFrame);
    }
    final route = ModalRoute.of(context);
    _animations = [?route?.animation, ?route?.secondaryAnimation];
    for (final animation in _animations) {
      animation.addListener(_updateAfterFrame);
    }
  }

  void _updateAfterFrame() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (mounted) _passthrough.currentState?.requestUpdate();
    });
  }

  @override
  void dispose() {
    for (final animation in _animations) {
      animation.removeListener(_updateAfterFrame);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MacosToolbarPassthrough(key: _passthrough, child: widget.child);
}
