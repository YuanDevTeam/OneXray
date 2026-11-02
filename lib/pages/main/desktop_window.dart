import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/shared/menu/window/service.dart';
import 'package:window_manager/window_manager.dart';

/// Native macOS controls use local safe areas, not a second full-width bar.
/// Other desktops retain their separate caption outside the Router.
class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({
    super.key,
    required this.child,
    this.windowService,
  });

  final Widget child;
  final WindowService? windowService;

  static bool hasNativeSidebar(BuildContext context) {
    final frame = context.findAncestorWidgetOfExactType<DesktopWindowFrame>();
    final service = frame?.windowService ?? WindowService();
    return Theme.of(context).platform == TargetPlatform.macOS &&
        service.hasSidebarMaterial;
  }

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame> {
  double? _titlebarHeight;
  Window? _listeningWindow;
  ListenerId? _listenerId;

  WindowService get _windowService => widget.windowService ?? WindowService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateWindowListener();
  }

  @override
  void didUpdateWidget(covariant DesktopWindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowService != widget.windowService) {
      _updateWindowListener();
    }
  }

  void _updateWindowListener() {
    final theme = Theme.of(context);
    final macOS = theme.platform == TargetPlatform.macOS;
    if (macOS) {
      unawaited(_windowService.updateAppearance(theme.brightness));
    }
    final window = macOS && _windowService.hasSidebarMaterial
        ? _windowService.mainWindow
        : null;
    if (_listeningWindow == window) return;
    _removeWindowListener();
    _titlebarHeight = _windowService.titlebarHeight;
    if (window != null) {
      _listeningWindow = window;
      _listenerId = window.addListener(_onWindowEvent);
    }
  }

  void _removeWindowListener() {
    final listenerId = _listenerId;
    if (listenerId != null) _listeningWindow?.removeListener(listenerId);
    _listenerId = null;
    _listeningWindow = null;
  }

  Future<void> _refreshTitlebar() async {
    final height = await _windowService.refreshTitlebarHeight();
    if (mounted && height != _titlebarHeight) {
      setState(() => _titlebarHeight = height);
    }
  }

  void _onWindowEvent(WindowEvent event) {
    switch (event) {
      case WindowResizedEvent():
      case WindowEnteredFullScreenEvent():
      case WindowExitedFullScreenEvent():
        unawaited(_refreshTitlebar());
      default:
        break;
    }
  }

  @override
  void dispose() {
    _removeWindowListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.platform != TargetPlatform.macOS &&
        theme.platform != TargetPlatform.windows &&
        theme.platform != TargetPlatform.linux) {
      return widget.child;
    }
    final palette = ColorManager.palette(context);
    final macOS = theme.platform == TargetPlatform.macOS;
    final nativeSidebar = macOS && _windowService.hasSidebarMaterial;
    if (nativeSidebar) {
      final height = _titlebarHeight ?? AppLayout.macOSTitlebarHeight;
      final media = MediaQuery.of(context);
      return MacOSWindowInsets(
        titlebarHeight: height,
        child: MediaQuery(
          // Scaffold backgrounds can extend behind the controls; AppBars,
          // SafeAreas and dialogs still avoid them unless the shell opts out.
          data: media.copyWith(
            padding: media.padding.copyWith(top: height),
            viewPadding: media.viewPadding.copyWith(top: height),
          ),
          child: widget.child,
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          key: const ValueKey('desktop-window-caption'),
          height: macOS
              ? _windowService.titlebarHeight ?? AppLayout.macOSTitlebarHeight
              : kWindowCaptionHeight,
          width: double.infinity,
          child: macOS
              ? DragToMoveArea(
                  window: _windowService.mainWindow,
                  child: ColoredBox(color: palette.header),
                )
              : Directionality(
                  // OS caption buttons stay on the right in RTL languages.
                  textDirection: TextDirection.ltr,
                  // window_manager still uses Flutter's legacy Material theme.
                  // ignore: deprecated_member_use
                  child: MaterialUiCompatibilityBridge(
                    child: WindowCaption(
                      window: _windowService.mainWindow,
                      onClose: () => unawaited(_windowService.hide()),
                      backgroundColor: palette.header,
                      brightness: theme.brightness,
                      title: Text(
                        'OneXray',
                        style: AppTypography.supporting.copyWith(
                          color: palette.foreground,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => MediaQuery(
              // Viewport-based page and dialog sizing excludes window chrome.
              data: MediaQuery.of(context).copyWith(size: constraints.biggest),
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}

/// Geometry shared by the native window, shell and toolbar controls.
class MacOSWindowInsets extends InheritedWidget {
  const MacOSWindowInsets({
    super.key,
    required this.titlebarHeight,
    required super.child,
  });

  final double titlebarHeight;

  static MacOSWindowInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MacOSWindowInsets>();

  @override
  bool updateShouldNotify(MacOSWindowInsets oldWidget) =>
      titlebarHeight != oldWidget.titlebarHeight;
}
