import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:onexray/service/shared/menu/window/service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'macOS preparation preserves visibility policy and window ownership',
    () async {
      final calls = <MethodCall>[];
      var materialAvailable = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const managerChannel = MethodChannel('window_manager');
      const materialChannel = MethodChannel(
        'macos_window_utils/window_manipulator',
      );
      const screenChannel = MethodChannel(
        'dev.leanflutter.plugins/screen_retriever',
      );
      const display = {
        'id': 'test-display',
        'size': {'width': 1920.0, 'height': 1080.0},
        'visiblePosition': {'dx': 0.0, 'dy': 0.0},
      };
      messenger.setMockMethodCallHandler(screenChannel, (call) async {
        return switch (call.method) {
          'getPrimaryDisplay' => display,
          'getAllDisplays' => {
            'displays': [display],
          },
          'getCursorScreenPoint' => {'dx': 100.0, 'dy': 100.0},
          _ => null,
        };
      });
      messenger.setMockMethodCallHandler(managerChannel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'isFullScreen' || 'isMaximized' || 'isMinimized' => false,
          'getBounds' => {'x': 0.0, 'y': 0.0, 'width': 1160.0, 'height': 720.0},
          _ => null,
        };
      });
      messenger.setMockMethodCallHandler(materialChannel, (call) async {
        calls.add(call);
        if (!materialAvailable) {
          throw MissingPluginException('material unavailable');
        }
        return call.method == 'getTitlebarHeight' ? 28.0 : null;
      });
      final service = WindowService();
      addTearDown(() {
        service.dispose();
        messenger.setMockMethodCallHandler(managerChannel, null);
        messenger.setMockMethodCallHandler(materialChannel, null);
        messenger.setMockMethodCallHandler(screenChannel, null);
      });

      await service.prepare(
        size: const Size(1160, 720),
        minimumSize: const Size(480, 600),
      );
      expect(service.hasSidebarMaterial, isFalse);
      expect(
        calls.where((call) => call.method == 'show' || call.method == 'focus'),
        isEmpty,
      );

      materialAvailable = true;
      calls.clear();
      await service.prepare(
        size: const Size(1160, 720),
        minimumSize: const Size(480, 600),
      );
      expect(service.hasSidebarMaterial, isTrue);
      expect(service.titlebarHeight, 28);
      expect(
        calls.singleWhere((call) => call.method == 'initialize').arguments,
        {'enableWindowDelegate': false},
      );
      expect(
        calls.singleWhere((call) => call.method == 'setMaterial').arguments,
        {'material': NSVisualEffectViewMaterial.sidebar.index},
      );
      expect(
        calls
            .singleWhere((call) => call.method == 'setTitleBarStyle')
            .arguments,
        {'titleBarStyle': 'hidden', 'windowButtonVisibility': true},
      );
      expect(
        calls.where((call) => call.method == 'show' || call.method == 'focus'),
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
      calls.clear();
      await service.onWindowClose();
      expect(calls.map((call) => call.method), ['hide']);
      calls.clear();
      await service.showAndFocus();
      expect(calls.map((call) => call.method), [
        'isMinimized',
        'show',
        'focus',
      ]);
    },
    skip: !Platform.isMacOS,
  );
}
