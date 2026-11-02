import 'dart:ui';

import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:window_manager/window_manager.dart';

final class WindowService with WindowListener {
  static final WindowService _singleton = WindowService._internal();

  factory WindowService() => _singleton;

  WindowService._internal();

  //==========================
  var _initialized = false;
  var _listening = false;
  var _hasSidebarMaterial = false;
  double? _titlebarHeight;
  Brightness? _brightness;

  bool get hasSidebarMaterial => _hasSidebarMaterial;
  double? get titlebarHeight => _titlebarHeight;

  /// Configure the window before showing either Setup or the main shell.
  Future<void> prepare({required Size size, required Size minimumSize}) async {
    if (!AppPlatform.isDesktop) return;
    _hasSidebarMaterial = false;
    _titlebarHeight = null;
    _brightness = null;
    await windowManager.ensureInitialized();
    if (AppPlatform.isMacOS) {
      try {
        // Leave NSWindowDelegate ownership with window_manager.
        await WindowManipulator.initialize(enableWindowDelegate: false);
        await WindowManipulator.setMaterial(NSVisualEffectViewMaterial.sidebar);
        _hasSidebarMaterial = true;
      } catch (error, stackTrace) {
        ygLogger('initialize window material failed: $error\n$stackTrace');
      }
    }
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: size,
        minimumSize: minimumSize,
        center: true,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: true,
        backgroundColor: _hasSidebarMaterial ? const Color(0x00000000) : null,
      ),
    );
    await refreshTitlebarHeight();
    await _listen();
  }

  /// Window geometry changes on resize and fullscreen transitions, not a timer.
  Future<double?> refreshTitlebarHeight() async {
    if (!_hasSidebarMaterial) return _titlebarHeight;
    try {
      _titlebarHeight = await windowManager.isFullScreen()
          ? 0
          : await WindowManipulator.getTitlebarHeight();
    } catch (error, stackTrace) {
      ygLogger('read window titlebar height failed: $error\n$stackTrace');
    }
    return _titlebarHeight;
  }

  Future<void> _listen() async {
    if (_listening) return;
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    _listening = true;
  }

  /// Receives the resolved Flutter brightness, including system-theme changes.
  Future<void> updateAppearance(Brightness brightness) async {
    if (!_hasSidebarMaterial || _brightness == brightness) return;
    _brightness = brightness;
    try {
      await WindowManipulator.overrideMacOSBrightness(
        dark: brightness == Brightness.dark,
      );
    } catch (error, stackTrace) {
      _brightness = null;
      ygLogger('update window appearance failed: $error\n$stackTrace');
    }
  }

  Future<void> asyncInit() async {
    if (!AppPlatform.isDesktop || _initialized) {
      return;
    }
    await _listen();
    _initialized = true;

    final hideDockIcon = await PreferencesKey().readHideDockIcon();
    await windowManager.setSkipTaskbar(hideDockIcon);
  }

  Future<void> showAndFocus() async {
    if (!AppPlatform.isDesktop) {
      return;
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hide() async {
    if (!AppPlatform.isDesktop) {
      return;
    }
    await windowManager.hide();
  }

  void dispose() {
    if (!AppPlatform.isDesktop || !_listening) {
      return;
    }
    windowManager.removeListener(this);
    _listening = false;
    _initialized = false;
  }

  @override
  Future<void> onWindowClose() async {
    super.onWindowClose();
    await windowManager.hide();
  }
}
