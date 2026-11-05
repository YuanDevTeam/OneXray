import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/json_editor.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('JSON frame stays continuous when content scrolls: $brightness', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 320);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = CodeLineEditingController.fromText(
        '{\n${List.generate(100, (i) => '  "line$i": "${'x' * 100}"').join(',\n')}\n}',
      );
      addTearDown(controller.dispose);
      final frame = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.material(brightness),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: RepaintBoundary(
                key: frame,
                child: AppJsonEditor(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AppJsonEditor));
      final expected = ColorManager.palette(context).input;
      Future<void> expectFrame() async => tester.runAsync(() async {
        final boundary =
            frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (final (x, y) in [
          for (var y = 20; y < image.height - 20; y += 20) (0, y),
          for (var y = 20; y < image.height - 20; y += 20) (image.width - 1, y),
          for (var x = 20; x < image.width - 20; x += 20) (x, 0),
          for (var x = 20; x < image.width - 20; x += 20) (x, image.height - 1),
        ]) {
          final offset = (y * image.width + x) * 4;
          final actual = Color.fromARGB(
            bytes.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          );
          expect(actual, expected, reason: 'Missing frame at ($x, $y)');
        }
        image.dispose();
      });

      await expectFrame();
      final scroll = tester
          .widget<CodeEditor>(find.byType(CodeEditor))
          .scrollController!;
      scroll.verticalScroller.jumpTo(250);
      scroll.horizontalScroller.jumpTo(100);
      await tester.pumpAndSettle();
      await expectFrame();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
