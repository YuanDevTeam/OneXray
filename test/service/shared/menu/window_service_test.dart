import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:onexray/service/shared/menu/window/service.dart';

import '../../../support/fake_desktop_window.dart';

const _materialChannel = MethodChannel('macos_window_utils/window_manipulator');

Future<void> _prepare(WindowService service) => service.prepare(
  size: const Size(1160, 720),
  minimumSize: const Size(480, 600),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_materialChannel, (call) async {
          return call.method == 'getTitlebarHeight' ? 28.0 : null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_materialChannel, null);
  });

  test('preparation configures one shared window without showing it', () async {
    final materialCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_materialChannel, (call) async {
          materialCalls.add(call);
          return call.method == 'getTitlebarHeight' ? 28.0 : null;
        });
    final window = FakeDesktopWindow();
    var resolveCount = 0;
    final service = WindowService.forTesting(
      resolveWindow: () async {
        resolveCount++;
        return window;
      },
    );
    addTearDown(service.dispose);
    await _prepare(service);
    await _prepare(service);

    expect(resolveCount, 1);
    expect(service.mainWindow, same(window));
    expect(window.listeners.length, 1);
    expect(window.calls.where((call) => call == 'addListener').length, 1);
    expect(window.size, const nativeapi.Size(width: 1160, height: 720));
    expect(window.minimumSize, const nativeapi.Size(width: 480, height: 600));
    expect(window.sizeAnimated, isFalse);
    expect(window.titleBarStyle, nativeapi.TitleBarStyle.hidden);
    expect(window.isWindowControlButtonsVisible, isTrue);
    expect(window.calls, contains('center'));
    expect(window.visible, isFalse);
    if (Platform.isMacOS) {
      expect(
        materialCalls
            .singleWhere((call) => call.method == 'initialize')
            .arguments,
        {'enableWindowDelegate': false},
      );
    }
    expect(
      window.calls.where((call) => call == 'show' || call == 'focus'),
      isEmpty,
    );
  });

  test('ordinary close is cancelled before hiding the same window', () async {
    final window = FakeDesktopWindow();
    final service = WindowService.forTesting(resolveWindow: () async => window);
    addTearDown(service.dispose);
    await _prepare(service);
    window.calls.clear();
    final request = _CloseRequest(cancelable: true, calls: window.calls);

    await window.emit(
      nativeapi.WindowCloseRequestedEvent(
        windowId: window.id,
        request: request,
      ),
    );

    expect(request.isCancelled, isTrue);
    expect(window.calls, ['cancel', 'hide']);
  });

  test(
    'mandatory close remains available to application termination',
    () async {
      final window = FakeDesktopWindow();
      final service = WindowService.forTesting(
        resolveWindow: () async => window,
      );
      addTearDown(service.dispose);
      await _prepare(service);
      window.calls.clear();
      final request = _CloseRequest(cancelable: false, calls: window.calls);

      await window.emit(
        nativeapi.WindowCloseRequestedEvent(
          windowId: window.id,
          request: request,
        ),
      );

      expect(request.isCancelled, isFalse);
      expect(window.calls, isEmpty);
    },
  );

  test(
    'show restores a minimized window before showing and focusing it',
    () async {
      final window = FakeDesktopWindow();
      final service = WindowService.forTesting(
        resolveWindow: () async => window,
      );
      addTearDown(service.dispose);
      await _prepare(service);
      window.calls.clear();
      window.minimized = true;

      await service.showAndFocus();

      expect(window.calls, ['restore', 'show', 'focus']);
      expect(window.minimized, isFalse);
      expect(window.visible, isTrue);
      expect(window.focused, isTrue);
      window.calls.clear();
      await service.showAndFocus();
      expect(window.calls, ['show', 'focus']);
    },
  );

  test(
    'service restart retains its main window and replaces its listener',
    () async {
      final window = FakeDesktopWindow();
      var resolveCount = 0;
      final service = WindowService.forTesting(
        resolveWindow: () async {
          resolveCount++;
          return window;
        },
      );
      addTearDown(service.dispose);
      await _prepare(service);
      final previousListenerId = window.listeners.keys.single;

      service.dispose();

      expect(window.listeners, isEmpty);
      expect(service.mainWindow, same(window));
      expect(window.disposed, isFalse);
      await _prepare(service);
      expect(resolveCount, 1);
      expect(window.listeners.length, 1);
      expect(window.listeners.keys.single, isNot(previousListenerId));
      expect(window.calls.where((call) => call == 'dispose'), isEmpty);
    },
  );

  test(
    'macOS material recovers without replacing the host delegate or window',
    () async {
      final calls = <MethodCall>[];
      var materialAvailable = false;
      var measuredHeight = 28.0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_materialChannel, (call) async {
            calls.add(call);
            if (call.method == 'setMaterial' && !materialAvailable) {
              throw MissingPluginException('material unavailable');
            }
            return call.method == 'getTitlebarHeight' ? measuredHeight : null;
          });
      final window = FakeDesktopWindow();
      final service = WindowService.forTesting(
        resolveWindow: () async => window,
      );
      addTearDown(service.dispose);

      await _prepare(service);
      expect(service.hasSidebarMaterial, isFalse);
      expect(service.titlebarHeight, isNull);
      materialAvailable = true;
      calls.clear();
      await _prepare(service);

      expect(service.mainWindow, same(window));
      expect(service.hasSidebarMaterial, isTrue);
      expect(service.titlebarHeight, 28);
      expect(
        calls.singleWhere((call) => call.method == 'setMaterial').arguments,
        {'material': NSVisualEffectViewMaterial.sidebar.index},
      );
      expect(
        window.backgroundColor,
        const nativeapi.Color(r: 0, g: 0, b: 0, a: 0),
      );
      expect(
        window.calls.where((call) => call == 'show' || call == 'focus'),
        isEmpty,
      );

      await service.updateAppearance(Brightness.dark);
      await service.updateAppearance(Brightness.dark);
      await service.updateAppearance(Brightness.light);
      expect(
        calls
            .where((call) => call.method == 'overrideMacOSBrightness')
            .map((call) => call.arguments),
        [
          {'dark': true},
          {'dark': false},
        ],
      );
      window.fullScreen = true;
      expect(await service.refreshTitlebarHeight(), 0);
      window.fullScreen = false;
      measuredHeight = 32;
      expect(await service.refreshTitlebarHeight(), 32);
    },
    skip: !Platform.isMacOS,
  );

  test(
    'macOS Dock preference maps to visibility and reports native failure',
    () async {
      final visibility = <bool>[];
      var allowed = true;
      final service = WindowService.forTesting(
        resolveWindow: () async => FakeDesktopWindow(),
        setDockIconVisible: (visible) {
          visibility.add(visible);
          return allowed;
        },
      );
      addTearDown(service.dispose);

      await service.setHideDockIcon(true);
      await service.setHideDockIcon(false);
      expect(visibility, [false, true]);
      allowed = false;
      await expectLater(service.setHideDockIcon(true), throwsStateError);
      expect(visibility, [false, true, false]);
    },
    skip: !Platform.isMacOS,
  );
}

class _CloseRequest extends nativeapi.EventRequest {
  _CloseRequest({required this.cancelable, required this.calls})
    : super.borrowed(0);

  final bool cancelable;
  final List<String> calls;
  var _cancelled = false;

  @override
  bool get isCancelable => cancelable;

  @override
  bool get isCancelled => _cancelled;

  @override
  bool cancel() {
    calls.add('cancel');
    _cancelled = true;
    return true;
  }
}
