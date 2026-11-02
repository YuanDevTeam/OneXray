import 'dart:async';

import 'package:nativeapi/nativeapi.dart' as na;

/// Exercises the App's window behavior without creating a native window.
class FakeDesktopWindow extends na.Window {
  FakeDesktopWindow({this.windowId = 1}) : super.borrowed(0);

  final na.WindowId windowId;
  final calls = <String>[];
  final listeners = <na.ListenerId, FutureOr<void> Function(na.WindowEvent)>{};
  var nextListenerId = 1;
  var minimized = false;
  var maximized = false;
  var fullScreen = false;
  var visible = false;
  var focused = false;
  var disposed = false;
  var sizeAnimated = false;
  na.Size _size = const na.Size(width: 0, height: 0);
  na.Size _minimumSize = const na.Size(width: 0, height: 0);
  na.TitleBarStyle _titleBarStyle = na.TitleBarStyle.normal;
  var _windowControlButtonsVisible = true;
  na.Color _backgroundColor = const na.Color(r: 255, g: 255, b: 255, a: 255);
  na.Rectangle? maximizeButtonBoundsValue;

  Future<void> emit(na.WindowEvent event) async {
    for (final listener in listeners.values.toList()) {
      await listener(event);
    }
  }

  @override
  na.WindowId get id => windowId;

  @override
  bool get isMinimized => minimized;

  @override
  bool get isMaximized => maximized;

  @override
  bool get isFullScreen => fullScreen;

  @override
  set isFullScreen(bool value) {
    calls.add('isFullScreen');
    fullScreen = value;
  }

  @override
  bool get isVisible => visible;

  @override
  bool get isFocused => focused;

  @override
  void setSize(na.Size size, bool animate) {
    calls.add('setSize');
    _size = size;
    sizeAnimated = animate;
  }

  @override
  na.Size get size => _size;

  @override
  set minimumSize(na.Size value) {
    calls.add('minimumSize');
    _minimumSize = value;
  }

  @override
  na.Size get minimumSize => _minimumSize;

  @override
  set titleBarStyle(na.TitleBarStyle value) {
    calls.add('titleBarStyle');
    _titleBarStyle = value;
  }

  @override
  na.TitleBarStyle get titleBarStyle => _titleBarStyle;

  @override
  set isWindowControlButtonsVisible(bool value) {
    calls.add('isWindowControlButtonsVisible');
    _windowControlButtonsVisible = value;
  }

  @override
  bool get isWindowControlButtonsVisible => _windowControlButtonsVisible;

  @override
  set backgroundColor(na.Color value) {
    calls.add('backgroundColor');
    _backgroundColor = value;
  }

  @override
  na.Color get backgroundColor => _backgroundColor;

  @override
  void center() => calls.add('center');

  @override
  void restore() {
    calls.add('restore');
    minimized = false;
  }

  @override
  void show() {
    calls.add('show');
    visible = true;
  }

  @override
  void focus() {
    calls.add('focus');
    focused = true;
  }

  @override
  void hide() {
    calls.add('hide');
    visible = false;
    focused = false;
  }

  @override
  bool close() {
    calls.add('close');
    return true;
  }

  @override
  na.ListenerId addListener(FutureOr<void> Function(na.WindowEvent) callback) {
    calls.add('addListener');
    final listenerId = nextListenerId++;
    listeners[listenerId] = callback;
    return listenerId;
  }

  @override
  bool removeListener(na.ListenerId listenerId) {
    calls.add('removeListener');
    return listeners.remove(listenerId) != null;
  }

  @override
  bool setMaximizeButtonBounds(na.Rectangle bounds) {
    calls.add('setMaximizeButtonBounds');
    maximizeButtonBoundsValue = bounds;
    return true;
  }

  @override
  void dispose() {
    calls.add('dispose');
    listeners.clear();
    disposed = true;
  }
}
