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
  const DesktopWindowFrame({super.key, required this.child});

  final Widget child;

  static bool hasNativeSidebar(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.macOS &&
      WindowService().hasSidebarMaterial;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  double? _titlebarHeight;
  bool _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Theme.of(context).platform == TargetPlatform.macOS) {
      unawaited(WindowService().updateAppearance(Theme.of(context).brightness));
      if (!_listening && WindowService().hasSidebarMaterial) {
        _titlebarHeight = WindowService().titlebarHeight;
        windowManager.addListener(this);
        _listening = true;
      }
    }
  }

  Future<void> _refreshTitlebar() async {
    final height = await WindowService().refreshTitlebarHeight();
    if (mounted && height != _titlebarHeight) {
      setState(() => _titlebarHeight = height);
    }
  }

  @override
  void onWindowResize() => unawaited(_refreshTitlebar());

  @override
  void onWindowResized() => unawaited(_refreshTitlebar());

  @override
  void onWindowEnterFullScreen() => unawaited(_refreshTitlebar());

  @override
  void onWindowLeaveFullScreen() => unawaited(_refreshTitlebar());

  @override
  void dispose() {
    if (_listening) windowManager.removeListener(this);
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
    final nativeSidebar = DesktopWindowFrame.hasNativeSidebar(context);
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
              ? WindowService().titlebarHeight ?? AppLayout.macOSTitlebarHeight
              : kWindowCaptionHeight,
          width: double.infinity,
          child: macOS
              ? DragToMoveArea(child: ColoredBox(color: palette.header))
              : Directionality(
                  // OS caption buttons stay on the right in RTL languages.
                  textDirection: TextDirection.ltr,
                  // window_manager still uses Flutter's legacy Material theme.
                  // ignore: deprecated_member_use
                  child: MaterialUiCompatibilityBridge(
                    child: WindowCaption(
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
