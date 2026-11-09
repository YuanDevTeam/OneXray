import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:nativeapi/nativeapi.dart' as native;
import 'package:onexray/service/shared/menu/window/service.dart';

class TestWindow implements native.Window {
  final calls = <String>[];
  FutureOr<void> Function(native.WindowEvent)? listener;
  native.TitleBarStyle? style;
  bool? controlsVisible;
  bool? contentUnderTitleBar;
  native.Size? preparedSize;
  native.Size? minSize;
  native.Color? background;
  bool? taskbarVisible;
  @override
  bool isFullScreen = false;
  @override
  bool isMinimized = false;
  @override
  bool isVisible = false;
  @override
  bool isFocused = false;

  @override
  set titleBarStyle(native.TitleBarStyle value) => style = value;
  @override
  set isWindowControlButtonsVisible(bool value) => controlsVisible = value;
  @override
  bool setContentUnderTitleBar(bool value) {
    contentUnderTitleBar = value;
    return true;
  }

  @override
  set backgroundColor(native.Color value) => background = value;
  @override
  set minimumSize(native.Size value) => minSize = value;
  @override
  set isVisibleInTaskbar(bool value) => taskbarVisible = value;
  @override
  void setSize(native.Size value, bool animate) => preparedSize = value;
  @override
  void center() => calls.add('center');
  @override
  void show() {
    calls.add('show');
    isVisible = true;
  }

  @override
  void focus() {
    calls.add('focus');
    isFocused = isVisible && !isMinimized;
  }

  @override
  void hide() {
    calls.add('hide');
    isVisible = false;
    isFocused = false;
  }

  @override
  void restore() {
    calls.add('restore');
    isMinimized = false;
  }

  @override
  native.ListenerId addListener(
    FutureOr<void> Function(native.WindowEvent) callback,
  ) {
    calls.add('listen');
    listener = callback;
    return 1;
  }

  @override
  bool removeListener(native.ListenerId id) {
    expect(id, 1);
    calls.add('unlisten');
    listener = null;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CloseRequest implements native.EventRequest {
  bool cancelled = false;
  @override
  bool cancel() => cancelled = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'macOS preparation, close and geometry preserve startup visibility',
    () async {
      final calls = <MethodCall>[];
      var materialAvailable = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('macos_window_utils/window_manipulator');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (!materialAvailable) {
          throw MissingPluginException('material unavailable');
        }
        return call.method == 'getTitlebarHeight' ? 28.0 : null;
      });
      final window = TestWindow();
      final dockVisibility = <bool>[];
      var allowDockChange = true;
      final service = WindowService.forTesting(
        readWindow: () => window,
        setDockIconVisible: (visible) {
          dockVisibility.add(visible);
          return allowDockChange;
        },
      );
      addTearDown(() {
        service.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      });
      Future<void> prepare() => service.prepare(
        size: const Size(1160, 720),
        minimumSize: const Size(480, 600),
      );
      await prepare();
      expect(service.hasSidebarMaterial, isFalse);
      expect(window.style, native.TitleBarStyle.hidden);
      expect(window.contentUnderTitleBar, isNull);
      materialAvailable = true;
      calls.clear();
      await prepare();
      expect(service.hasSidebarMaterial, isTrue);
      expect(service.titlebarHeight, 28);
      expect(calls.singleWhere((c) => c.method == 'initialize').arguments, {
        'enableWindowDelegate': false,
      });
      expect(calls.singleWhere((c) => c.method == 'setMaterial').arguments, {
        'material': NSVisualEffectViewMaterial.sidebar.index,
      });
      expect(window.style, native.TitleBarStyle.normal);
      expect(window.contentUnderTitleBar, isTrue);
      expect(window.controlsVisible, isTrue);
      expect(
        [window.preparedSize!.width, window.preparedSize!.height],
        [1160, 720],
      );
      expect([window.minSize!.width, window.minSize!.height], [480, 600]);
      expect(window.background, isNotNull);
      expect(window.calls.where((c) => c == 'show' || c == 'focus'), isEmpty);
      expect(window.calls.where((c) => c == 'listen'), hasLength(1));

      await service.updateAppearance(Brightness.dark);
      await service.updateAppearance(Brightness.dark);
      await service.updateAppearance(Brightness.light);
      expect(
        calls
            .where((c) => c.method == 'overrideMacOSBrightness')
            .map((c) => c.arguments),
        [
          {'dark': true},
          {'dark': false},
        ],
      );

      final request = CloseRequest();
      window.calls.clear();
      await window.listener!(
        native.WindowCloseRequestedEvent(windowId: 1, request: request),
      );
      expect(request.cancelled, isTrue);
      expect(window.calls, ['hide']);
      window.calls.clear();
      window.isMinimized = true;
      await service.showAndFocus();
      expect(window.calls, ['restore', 'show', 'focus']);

      final heights = <double?>[];
      service.titlebarChanges.addListener(
        () => heights.add(service.titlebarHeight),
      );
      window.isFullScreen = true;
      await window.listener!(
        const native.WindowEnteredFullScreenEvent(windowId: 1),
      );
      window.isFullScreen = false;
      await window.listener!(
        const native.WindowExitedFullScreenEvent(windowId: 1),
      );
      expect(heights, [0, 28]);

      await service.setHideDockIcon(true);
      await service.setHideDockIcon(false);
      expect(dockVisibility, [false, true]);
      expect(window.taskbarVisible, isNull);
      allowDockChange = false;
      await expectLater(service.setHideDockIcon(true), throwsStateError);
      service.dispose();
      expect(window.listener, isNull);
    },
  );

  test('Linux preserves GTK chrome during window actions', () async {
    final window = TestWindow()
      ..style = native.TitleBarStyle.normal
      ..controlsVisible = false;
    final service = WindowService.forTesting(
      readWindow: () => window,
      isMacOS: false,
      isLinux: true,
      setDockIconVisible: (_) => throw StateError('macOS-only API'),
    );
    addTearDown(service.dispose);

    await service.prepare(
      size: const Size(1160, 720),
      minimumSize: const Size(480, 600),
    );

    // GTK retains its decorated window with a hidden native header. Changing
    // either native property would replace that runner-owned chrome policy.
    expect(window.style, native.TitleBarStyle.normal);
    expect(window.controlsVisible, isFalse);
    expect(window.contentUnderTitleBar, isNull);
    expect(window.background, isNull);
    expect(service.hasSidebarMaterial, isFalse);
    expect(service.titlebarHeight, isNull);
    expect(
      [window.preparedSize!.width, window.preparedSize!.height],
      [1160, 720],
    );
    expect([window.minSize!.width, window.minSize!.height], [480, 600]);
    expect(window.isVisible, isFalse);
    expect(window.isFocused, isFalse);
    expect(window.calls.where((c) => c == 'show' || c == 'focus'), isEmpty);

    await service.showAndFocus();
    expect(window.isVisible, isTrue);
    expect(window.isFocused, isTrue);

    final request = CloseRequest();
    await window.listener!(
      native.WindowCloseRequestedEvent(windowId: 1, request: request),
    );
    expect(request.cancelled, isTrue);
    expect(window.isVisible, isFalse);
    expect(window.isFocused, isFalse);

    window.calls.clear();
    window.isMinimized = true;
    await service.showAndFocus();
    expect(window.isMinimized, isFalse);
    expect(window.isVisible, isTrue);
    expect(window.isFocused, isTrue);
    expect(window.calls, ['restore', 'show', 'focus']);
    expect(window.style, native.TitleBarStyle.normal);
    expect(window.controlsVisible, isFalse);
  });

  test('Windows prepares hidden chrome without showing the window', () async {
    final window = TestWindow()
      ..style = native.TitleBarStyle.normal
      ..controlsVisible = false;
    final service = WindowService.forTesting(
      readWindow: () => window,
      isMacOS: false,
      setDockIconVisible: (_) => throw StateError('macOS-only API'),
    );
    addTearDown(service.dispose);

    await service.prepare(
      size: const Size(1160, 720),
      minimumSize: const Size(480, 600),
    );

    expect(window.style, native.TitleBarStyle.hidden);
    expect(window.controlsVisible, isTrue);
    expect(service.hasSidebarMaterial, isFalse);
    expect(window.isVisible, isFalse);
    expect(window.isFocused, isFalse);
  });

  test(
    'other desktops change taskbar visibility without the macOS Dock API',
    () async {
      final window = TestWindow();
      final service = WindowService.forTesting(
        readWindow: () => window,
        isMacOS: false,
        setDockIconVisible: (_) => throw StateError('macOS-only API'),
      );
      await service.setHideDockIcon(true);
      expect(window.taskbarVisible, isFalse);
      await service.setHideDockIcon(false);
      expect(window.taskbarVisible, isTrue);
    },
  );

  test('mobile does not resolve or operate a native desktop window', () async {
    final service = WindowService.forTesting(
      readWindow: () => throw StateError('desktop-only API'),
      isDesktop: false,
      setDockIconVisible: (_) => throw StateError('desktop-only API'),
    );
    await service.prepare(
      size: const Size(1160, 720),
      minimumSize: const Size(480, 600),
    );
    await service.showAndFocus();
    await service.hide();
    await service.setHideDockIcon(true);
  });
}
