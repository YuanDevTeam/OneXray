import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart' show RenderSliver;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/order/controller.dart';
import 'package:onexray/pages/servers/order/page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;

void main() {
  Future<void> open(
    WidgetTester tester,
    ManualOrderParams params, {
    double width = 390,
    double height = 844,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.material(Brightness.light, mobile: width < 700),
        locale: locale,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: ShadToaster(child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ManualOrderPage(params: params),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 1200.0]) {
    testWidgets('dragging changes the local draft and Save commits at $width', (
      tester,
    ) async {
      final saved = <List<int>>[];
      const items = [
        ManualOrderItem(1, 'First'),
        ManualOrderItem(2, 'Second'),
        ManualOrderItem(3, 'Third'),
      ];
      await open(
        tester,
        ManualOrderParams(
          title: 'Arrange',
          items: items,
          reload: () async => items,
          save: (expected, ordered) async {
            expect(expected, [1, 2, 3]);
            saved.add(ordered);
          },
        ),
        width: width,
      );
      final controller = tester
          .element(find.byType(SliverReorderableList))
          .read<ManualOrderController>();
      final handle = find.byIcon(LucideIcons.gripVertical).first;
      final start = tester.getCenter(handle);
      final dragDistance = tester.getRect(find.byType(ListTile).first).height;
      final gesture = await tester.startGesture(
        start,
        kind: width < 700 ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
      );
      if (width < 700) {
        await tester.pump(const Duration(milliseconds: 600));
      }
      for (var step = 1; step <= 20; step++) {
        await gesture.moveTo(start + Offset(0, dragDistance * step / 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.state.items.map((item) => item.id), [2, 1, 3]);
      expect(saved, isEmpty);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, [
        [2, 1, 3],
      ]);
      expect(find.byType(ManualOrderPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'node arranging explains display order without changing its draft',
    (tester) async {
      const items = [ManualOrderItem(1, 'First'), ManualOrderItem(2, 'Second')];
      const hint =
          'Saved positions are shown by Default; Name and Latency stay unchanged.';
      var saves = 0;
      await open(
        tester,
        ManualOrderParams(
          title: 'Arrange node order',
          description: hint,
          items: items,
          reload: () async => items,
          save: (_, _) async {
            saves++;
          },
        ),
      );
      expect(find.text(hint), findsOneWidget);
      expect(
        tester
            .element(find.byType(SliverReorderableList))
            .read<ManualOrderController>()
            .state
            .items
            .map((item) => item.id),
        [1, 2],
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.byType(ManualOrderPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cancel discards accessible position changes', (tester) async {
    final saved = <List<int>>[];
    const items = [ManualOrderItem(1, 'First'), ManualOrderItem(2, 'Second')];
    await open(
      tester,
      ManualOrderParams(
        title: 'Arrange',
        items: items,
        reload: () async => items,
        save: (_, ordered) async => saved.add(ordered),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('move-down-1')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Second')).dy,
      lessThan(tester.getTopLeft(find.text('First')).dy),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.byType(ManualOrderPage), findsNothing);
  });

  for (final title in ['Group order', 'Arrange server order']) {
    testWidgets('desktop $title card hugs its two rows', (tester) async {
      const items = [ManualOrderItem(1, 'First'), ManualOrderItem(2, 'Second')];
      final saved = <List<int>>[];
      await open(
        tester,
        ManualOrderParams(
          title: title,
          items: items,
          reload: () async => items,
          save: (_, ordered) async => saved.add(List<int>.of(ordered)),
        ),
        width: 1160,
        height: 720,
      );
      final card = tester.renderObject<RenderSliver>(
        find.byKey(const ValueKey('manual-order-card')),
      );
      final rowsHeight =
          tester.getRect(find.byType(ListTile).last).bottom -
          tester.getRect(find.byType(ListTile).first).top;
      expect(card.geometry!.scrollExtent, closeTo(rowsHeight + 36, .1));
      final viewportHeight = tester
          .getSize(find.byKey(const PageStorageKey('manual-order')))
          .height;
      expect(card.geometry!.scrollExtent, lessThan(viewportHeight / 2));
      expect(
        tester.getRect(find.text('Save')).top,
        greaterThan(tester.getRect(find.byType(ListTile).last).bottom + 28),
      );
      await tester.tap(find.byKey(const ValueKey('move-down-1')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Second')).dy,
        lessThan(tester.getTopLeft(find.text('First')).dy),
      );
      expect(card.geometry!.scrollExtent, closeTo(rowsHeight + 36, .1));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, [
        [2, 1],
      ]);
      expect(find.byType(ManualOrderPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a long list builds lazily and scrolls while dragging', (
    tester,
  ) async {
    final items = [for (var i = 0; i < 200; i++) ManualOrderItem(i, 'Node $i')];
    await open(
      tester,
      ManualOrderParams(
        title: 'Arrange',
        items: items,
        reload: () async => items,
        save: (_, _) async {},
      ),
    );
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(LucideIcons.gripVertical).first),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final scrollable = find.descendant(
      of: find.byKey(const PageStorageKey('manual-order')),
      matching: find.byType(Scrollable),
    );
    final listBottom = tester
        .getRect(find.byKey(const PageStorageKey('manual-order')))
        .bottom;
    await gesture.moveTo(Offset(36, listBottom - 10));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final scroll = tester.state<ScrollableState>(scrollable);
    expect(scroll.position.pixels, greaterThan(100));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Node 199'),
      500,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Node 199'), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
    final controller = tester
        .element(find.byType(SliverReorderableList))
        .read<ManualOrderController>();
    await tester.tap(find.byKey(const ValueKey('move-up-199')));
    await tester.pumpAndSettle();
    expect(
      controller.state.items.indexWhere((item) => item.id == 199),
      items.length - 2,
    );
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [Locale('ru'), Locale('fa')]) {
    testWidgets('long names and actions fit a narrow $locale screen', (
      tester,
    ) async {
      const items = [
        ManualOrderItem(
          1,
          'Cloud servers and a very long descriptive group name',
        ),
        ManualOrderItem(2, 'Home'),
      ];
      await open(
        tester,
        ManualOrderParams(
          title: 'Arrange',
          items: items,
          reload: () async => items,
          save: (_, _) async {},
        ),
        width: 320,
        locale: locale,
      );
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
}
