import 'package:macos_window_utils/widgets/macos_toolbar_passthrough.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/main/desktop_window.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/theme/layout.dart';
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
  });

  final Widget title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  // Retain AppBar's theme-aware preferred size, including its optional tabs.
  @override
  Size get preferredSize => AppBar(bottom: bottom).preferredSize;

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
        effectiveActions.add(
          IconButton(
            key: const ValueKey('mobile-settings-action'),
            tooltip: AppLocalizations.of(context)!.prototypeSettings,
            icon: const Icon(LucideIcons.settings2),
            onPressed: () => router.push<void>(
              '$path/${AppPageDestination.settings.segment}',
            ),
          ),
        );
      }
    }
    return AppBar(
      title: title,
      leading: forwardClicks && effectiveLeading != null
          ? _AnimatedToolbarPassthrough(child: effectiveLeading)
          : effectiveLeading,
      actions: forwardClicks
          ? effectiveActions
                .map((child) => _AnimatedToolbarPassthrough(child: child))
                .toList()
          : effectiveActions,
      bottom: bottom,
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
