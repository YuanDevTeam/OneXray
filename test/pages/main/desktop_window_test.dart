import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:onexray/pages/main/desktop_window.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/shared/menu/window/service.dart';
import 'package:window_manager/window_manager.dart';

import '../../support/fake_desktop_window.dart';

const _materialChannel = MethodChannel('macos_window_utils/window_manipulator');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_materialChannel, (_) async {
          throw MissingPluginException('material unavailable');
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_materialChannel, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform keeps mobile layout unchanged', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const DesktopWindowFrame(
            child: SizedBox.expand(key: Key('body')),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('desktop-window-caption')),
        findsNothing,
      );
      expect(tester.getTopLeft(find.byKey(const Key('body'))), Offset.zero);
    }, variant: TargetPlatformVariant.only(platform));
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform keeps controls above compact pages and dialogs', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(480, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final window = FakeDesktopWindow();
      final service = WindowService.forTesting(
        resolveWindow: () async => window,
      );
      addTearDown(service.dispose);
      await service.prepare(
        size: const Size(1160, 720),
        minimumSize: const Size(480, 600),
      );
      Size? pageViewport;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: DesktopWindowFrame(windowService: service, child: child!),
          ),
          home: Builder(
            builder: (context) {
              pageViewport = MediaQuery.sizeOf(context);
              return Scaffold(
                key: const Key('body'),
                appBar: AppBar(title: const Text('Page')),
                body: Center(
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const AlertDialog(title: Text('Dialog')),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final caption = find.byKey(const ValueKey('desktop-window-caption'));
      final height = platform == TargetPlatform.macOS
          ? AppLayout.macOSTitlebarHeight
          : kWindowCaptionHeight;
      expect(tester.getTopLeft(caption), Offset.zero);
      expect(tester.getSize(caption), Size(480, height));
      expect(tester.getTopLeft(find.byKey(const Key('body'))).dy, height);
      expect(pageViewport, Size(480, 600 - height));
      if (platform == TargetPlatform.macOS) {
        expect(find.byType(WindowCaption), findsNothing);
      } else {
        final controls = tester.widget<WindowCaption>(
          find.byType(WindowCaption),
        );
        expect(controls.window, same(window));
        expect(
          Directionality.of(tester.element(find.byType(WindowCaption))),
          TextDirection.ltr,
        );
      }
      for (final dragArea in tester.widgetList<DragToMoveArea>(
        find.byType(DragToMoveArea),
      )) {
        expect(dragArea.window, same(window));
      }
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Dialog'), findsOneWidget);
      expect(caption.hitTestable(at: const Alignment(0.8, 0)), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('$platform caption close hides the prepared window', (
      tester,
    ) async {
      final window = FakeDesktopWindow();
      final service = WindowService.forTesting(
        resolveWindow: () async => window,
      );
      addTearDown(service.dispose);
      await service.prepare(
        size: const Size(1160, 720),
        minimumSize: const Size(480, 600),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DesktopWindowFrame(
            windowService: service,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      window.calls.clear();

      await tester.tap(find.byType(WindowCaptionButton).last);
      await tester.pumpAndSettle();

      expect(window.calls, ['hide']);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets(
    'macOS native frame tracks titlebar geometry and releases its listener',
    (tester) async {
      var measuredHeight = 28.0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_materialChannel, (call) async {
        return call.method == 'getTitlebarHeight' ? measuredHeight : null;
      });
      final window = FakeDesktopWindow();
      final service = WindowService.forTesting(
        resolveWindow: () async => window,
      );
      addTearDown(service.dispose);
      await service.prepare(
        size: const Size(1160, 720),
        minimumSize: const Size(480, 600),
      );
      final serviceListenerCount = window.listeners.length;
      double? titlebarHeight;
      double? topPadding;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DesktopWindowFrame(
            windowService: service,
            child: Builder(
              builder: (context) {
                titlebarHeight = MacOSWindowInsets.maybeOf(context)
                    ?.titlebarHeight;
                topPadding = MediaQuery.paddingOf(context).top;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WindowCaption), findsNothing);
      expect(window.listeners.length, serviceListenerCount + 1);
      expect(titlebarHeight, 28);
      expect(topPadding, 28);

      window.fullScreen = true;
      await window.emit(WindowEnteredFullScreenEvent(windowId: window.id));
      await tester.pumpAndSettle();
      expect(titlebarHeight, 0);
      expect(topPadding, 0);

      window.fullScreen = false;
      await window.emit(WindowExitedFullScreenEvent(windowId: window.id));
      await tester.pumpAndSettle();
      expect(titlebarHeight, 28);
      measuredHeight = 32;
      await window.emit(
        WindowResizedEvent(
          windowId: window.id,
          newSize: const nativeapi.Size(width: 1200, height: 800),
        ),
      );
      await tester.pumpAndSettle();
      expect(titlebarHeight, 32);
      expect(topPadding, 32);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(window.listeners.length, serviceListenerCount);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    skip: !Platform.isMacOS,
  );
}
