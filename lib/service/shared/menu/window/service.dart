import 'dart:ffi' as ffi;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:nativeapi/nativeapi.dart' as native;
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/desktop_window/handle.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/core/tools/platform.dart';

final class WindowService {
  static final WindowService _singleton = WindowService._internal();
  static Future<void>? _materialInitialization;

  factory WindowService() => _singleton;

  WindowService._internal()
    : _resolveWindow = _resolveMainWindow,
      _setDockIconVisible = ((visible) =>
          native.Application.instance.setDockIconVisible(visible));

  @visibleForTesting
  WindowService.forTesting({
    required this._resolveWindow,
    bool Function(bool)? setDockIconVisible,
  }) : _setDockIconVisible = setDockIconVisible ?? ((_) => true);

  final Future<native.Window> Function() _resolveWindow;
  final bool Function(bool) _setDockIconVisible;
  native.Window? _window;
  native.ListenerId? _closeListenerId;

  native.Window? get mainWindow => _window;

  static Future<native.Window> _resolveMainWindow() async {
    final window = AppPlatform.isWindows
        ? native.Window.createWithNativeWindow(
            ffi.Pointer<ffi.Void>.fromAddress(await DesktopWindowHandle.read()),
          )
        : native.WindowManager.instance.getCurrent();
    if (window == null) {
      throw StateError('The main desktop window is unavailable.');
    }
    return window;
  }

  //==========================
  var _initialized = false;
  var _hasSidebarMaterial = false;
  double? _titlebarHeight;
  Brightness? _brightness;

  bool get hasSidebarMaterial => _hasSidebarMaterial;
  double? get titlebarHeight => _titlebarHeight;

  static Future<void> _initializeMaterial() async {
    try {
      // macos_window_utils completes a process-wide completer exactly once.
      await (_materialInitialization ??= WindowManipulator.initialize(
        enableWindowDelegate: false,
      ));
    } catch (_) {
      _materialInitialization = null;
      rethrow;
    }
  }

  /// Configure the window before showing either Setup or the main shell.
  Future<void> prepare({required Size size, required Size minimumSize}) async {
    if (!AppPlatform.isDesktop) return;
    _hasSidebarMaterial = false;
    _titlebarHeight = null;
    _brightness = null;
    final window = _window ??= await _resolveWindow();
    if (AppPlatform.isMacOS) {
      try {
        // Native window events preserve the existing host delegate.
        await _initializeMaterial();
        await WindowManipulator.setMaterial(NSVisualEffectViewMaterial.sidebar);
        _hasSidebarMaterial = true;
      } catch (error, stackTrace) {
        ygLogger('initialize window material failed: $error\n$stackTrace');
      }
    }
    window.titleBarStyle = native.TitleBarStyle.hidden;
    window.isWindowControlButtonsVisible = true;
    window.setSize(native.Size(width: size.width, height: size.height), false);
    window.minimumSize = native.Size(
      width: minimumSize.width,
      height: minimumSize.height,
    );
    window.center();
    if (_hasSidebarMaterial) {
      window.backgroundColor = const native.Color(r: 0, g: 0, b: 0, a: 0);
    }
    await refreshTitlebarHeight();
    _listen();
  }

  /// Window geometry changes on resize and fullscreen transitions, not a timer.
  Future<double?> refreshTitlebarHeight() async {
    if (!_hasSidebarMaterial) return _titlebarHeight;
    try {
      _titlebarHeight = _window?.isFullScreen == true
          ? 0
          : await WindowManipulator.getTitlebarHeight();
    } catch (error, stackTrace) {
      ygLogger('read window titlebar height failed: $error\n$stackTrace');
    }
    return _titlebarHeight;
  }

  void _listen() {
    final window = _window;
    if (window == null || _closeListenerId != null) return;
    _closeListenerId = window.addListener((event) {
      if (event is native.WindowCloseRequestedEvent &&
          event.request.isCancelable) {
        event.request.cancel();
        window.hide();
      }
    });
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
    _listen();
    if (AppPlatform.isMacOS) {
      await setHideDockIcon(await PreferencesKey().readHideDockIcon());
    }
    _initialized = true;
  }

  Future<void> setHideDockIcon(bool hidden) async {
    if (!AppPlatform.isMacOS) return;
    if (!_setDockIconVisible(!hidden)) {
      throw StateError('Could not change Dock icon visibility.');
    }
  }

  Future<void> showAndFocus() async {
    if (!AppPlatform.isDesktop) {
      return;
    }
    final window = _window;
    if (window == null) return;
    if (window.isMinimized) window.restore();
    window.show();
    window.focus();
  }

  Future<void> hide() async {
    if (!AppPlatform.isDesktop) {
      return;
    }
    _window?.hide();
  }

  void dispose() {
    final listenerId = _closeListenerId;
    if (listenerId != null) _window?.removeListener(listenerId);
    _closeListenerId = null;
    _initialized = false;
    // Services can restart without recreating the runner or its UI frame.
    // Keep their shared main-window wrapper alive for that host lifetime.
  }
}
