import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/desktop_window/native_window.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:nativeapi/nativeapi.dart' show Application;
import 'package:window_manager/window_manager.dart';

final class WindowService {
  static final WindowService _singleton = WindowService._internal();

  factory WindowService() => _singleton;

  WindowService._internal()
    : this._(
        resolveDesktopWindow,
        Application.instance.setDockIconVisible,
        AppPlatform.isDesktop,
        AppPlatform.isMacOS,
        AppPlatform.isLinux,
      );

  WindowService._(
    this._readWindow,
    this._setDockIconVisible,
    this._isDesktop,
    this._isMacOS,
    this._isLinux,
  );

  @visibleForTesting
  WindowService.forTesting({
    required Window? Function() readWindow,
    required bool Function(bool) setDockIconVisible,
    bool isDesktop = true,
    bool isMacOS = true,
    bool isLinux = false,
  }) : this._(readWindow, setDockIconVisible, isDesktop, isMacOS, isLinux);

  final Window? Function() _readWindow;
  final bool Function(bool) _setDockIconVisible;
  final bool _isDesktop;
  final bool _isMacOS;
  final bool _isLinux;
  Window? _window;
  ListenerId? _listenerId;
  final _titlebarHeight = ValueNotifier<double?>(null);

  //==========================
  var _initialized = false;
  var _hasSidebarMaterial = false;
  Brightness? _brightness;

  bool get hasSidebarMaterial => _hasSidebarMaterial;
  double? get titlebarHeight => _titlebarHeight.value;
  ValueListenable<double?> get titlebarChanges => _titlebarHeight;
  Window? get nativeWindow => _window;

  Window get _target => _window ??=
      _readWindow() ??
      (throw StateError('The desktop application window is unavailable'));

  /// Configure the window before showing either Setup or the main shell.
  Future<void> prepare({required Size size, required Size minimumSize}) async {
    if (!_isDesktop) return;
    _hasSidebarMaterial = false;
    _titlebarHeight.value = null;
    _brightness = null;
    final window = _target;
    if (_isMacOS) {
      try {
        // nativeapi owns the window events; avoid a second NSWindowDelegate.
        await WindowManipulator.initialize(enableWindowDelegate: false);
        await WindowManipulator.setMaterial(NSVisualEffectViewMaterial.sidebar);
        _hasSidebarMaterial = true;
      } catch (error, stackTrace) {
        ygLogger('initialize window material failed: $error\n$stackTrace');
      }
    }
    // The Linux runner hides GTK's header while retaining its decoration and
    // resize handling. Changing the native style would install core shadows.
    if (!_isLinux) {
      // Native macOS chrome keeps AppKit's drag and double-click handling.
      // The hidden style transfers those gestures to a custom Flutter caption.
      window.titleBarStyle = _hasSidebarMaterial
          ? TitleBarStyle.normal
          : TitleBarStyle.hidden;
      window.isWindowControlButtonsVisible = true;
    }
    if (_hasSidebarMaterial) {
      window.setContentUnderTitleBar(true);
      window.backgroundColor = const Color(0x00000000).toNative();
    }
    window.setSize(size.toNative(), false);
    window.minimumSize = minimumSize.toNative();
    window.center();
    await refreshTitlebarHeight();
    _listen();
  }

  /// Window geometry changes on resize and fullscreen transitions, not a timer.
  Future<double?> refreshTitlebarHeight() async {
    if (!_hasSidebarMaterial) return titlebarHeight;
    try {
      _titlebarHeight.value = _target.isFullScreen
          ? 0
          : await WindowManipulator.getTitlebarHeight();
    } catch (error, stackTrace) {
      ygLogger('read window titlebar height failed: $error\n$stackTrace');
    }
    return titlebarHeight;
  }

  void _listen() {
    _listenerId ??= _target.addListener((event) async {
      if (event is WindowCloseRequestedEvent) {
        event.request.cancel();
        await hide();
      } else if (event is WindowResizedEvent ||
          event is WindowEnteredFullScreenEvent ||
          event is WindowExitedFullScreenEvent) {
        await refreshTitlebarHeight();
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
    if (!_isDesktop || _initialized) {
      return;
    }
    _listen();
    _initialized = true;

    final hideDockIcon = await PreferencesKey().readHideDockIcon();
    await setHideDockIcon(hideDockIcon);
  }

  Future<void> setHideDockIcon(bool hidden) async {
    if (!_isDesktop) return;
    if (_isMacOS) {
      if (!_setDockIconVisible(!hidden)) {
        throw StateError('Unable to update Dock icon visibility');
      }
    } else {
      _target.isVisibleInTaskbar = !hidden;
    }
  }

  Future<void> showAndFocus() async {
    if (!_isDesktop) {
      return;
    }
    final window = _target;
    if (window.isMinimized) window.restore();
    window.show();
    window.focus();
  }

  Future<void> hide() async {
    if (!_isDesktop) {
      return;
    }
    _target.hide();
  }

  void dispose() {
    final listenerId = _listenerId;
    if (listenerId != null) {
      _window?.removeListener(listenerId);
      _listenerId = null;
    }
    _initialized = false;
  }
}
