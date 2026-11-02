import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/main/desktop_window.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isMaximized' ? false : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
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
      Size? pageViewport;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: DesktopWindowFrame(child: child!),
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
        expect(
          Directionality.of(tester.element(find.byType(WindowCaption))),
          TextDirection.ltr,
        );
      }
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Dialog'), findsOneWidget);
      expect(caption.hitTestable(at: const Alignment(0.8, 0)), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }
}
