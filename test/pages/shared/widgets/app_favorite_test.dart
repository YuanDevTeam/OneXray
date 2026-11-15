import 'dart:ui' show SemanticsAction;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/app_favorite.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/theme.dart';

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  bool mobile = false,
  TextDirection direction = TextDirection.ltr,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.material(brightness, mobile: mobile),
    home: Directionality(
      textDirection: direction,
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

SemanticsFinder _favoriteAction() => find.semantics.byPredicate(
  (node) => node.getSemanticsData().flagsCollection.isButton,
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness favorites share filled and outline state colors', (
      tester,
    ) async {
      final palette = brightness == Brightness.light
          ? AppPalette.light
          : AppPalette.dark;
      await _mount(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFavoriteButton(
              selected: false,
              tooltip: 'Add to favorites',
              onPressed: () {},
              size: 17,
            ),
            AppFavoriteButton(
              selected: true,
              tooltip: 'Remove from favorites',
              onPressed: () {},
              size: 17,
            ),
            const AppFavoriteIcon(selected: false),
            const AppFavoriteIcon(selected: true),
          ],
        ),
        brightness: brightness,
      );
      final outline = tester.widgetList<Icon>(
        find.byIcon(Icons.star_border_rounded),
      );
      final filled = tester.widgetList<Icon>(find.byIcon(Icons.star_rounded));
      expect(outline, hasLength(2));
      expect(filled, hasLength(2));
      expect(
        outline.map((icon) => icon.color),
        everyElement(palette.mutedStrong),
      );
      expect(
        filled.map((icon) => icon.color),
        everyElement(palette.primaryText),
      );
      expect(outline.map((icon) => icon.size), [17, 18]);
      expect(filled.map((icon) => icon.size), [17, 18]);
      expect(
        Icons.star_rounded.codePoint,
        isNot(Icons.star_border_rounded.codePoint),
      );
      expect(Icons.star_rounded.fontFamily, 'MaterialIcons');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('favorite button exposes one selected action in RTL', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var selected = false;
      var calls = 0;
      await _mount(
        tester,
        StatefulBuilder(
          builder: (context, update) => AppFavoriteButton(
            selected: selected,
            tooltip: selected ? 'Remove from favorites' : 'Add to favorites',
            onPressed: () => update(() {
              selected = !selected;
              calls++;
            }),
          ),
        ),
        direction: TextDirection.rtl,
      );
      expect(_favoriteAction(), findsOneWidget);
      expect(
        _favoriteAction().evaluate().single,
        isSemantics(
          isButton: true,
          isEnabled: true,
          isSelected: false,
          tooltip: 'Add to favorites',
          hasTapAction: true,
        ),
      );
      await tester.tap(find.byTooltip('Add to favorites'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(_favoriteAction(), findsOneWidget);
      expect(
        _favoriteAction().evaluate().single,
        isSemantics(
          isButton: true,
          isEnabled: true,
          isSelected: true,
          tooltip: 'Remove from favorites',
          hasTapAction: true,
        ),
      );
      final node = tester.getSemantics(find.byType(AppFavoriteButton));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(selected, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(calls, 3);
      expect(selected, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final selected in [false, true]) {
    testWidgets('busy favorite $selected shows progress and preserves bounds', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var calls = 0;
        var busy = false;
        late StateSetter update;
        await _mount(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return AppFavoriteButton(
                selected: selected,
                tooltip: selected
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                busy: busy,
                size: 17,
                onPressed: () => calls++,
              );
            },
          ),
        );
        final button = find.byType(AppFavoriteButton);
        final glyph = find.byType(AppFavoriteIcon);
        final beforeButton = tester.getRect(button);
        final beforeGlyph = tester.getRect(glyph);
        update(() => busy = true);
        await tester.pump();
        expect(find.byType(ButtonProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.star_rounded), findsNothing);
        expect(find.byIcon(Icons.star_border_rounded), findsNothing);
        expect(tester.getRect(button), beforeButton);
        expect(tester.getRect(glyph), beforeGlyph);
        expect(
          tester.getSize(find.byType(ButtonProgressIndicator)),
          const Size(17, 17),
        );
        expect(_favoriteAction(), findsOneWidget);
        expect(
          _favoriteAction().evaluate().single,
          isSemantics(
            isButton: true,
            isEnabled: false,
            isSelected: selected,
            hasTapAction: false,
          ),
        );
        await tester.tap(button, warnIfMissed: false);
        await tester.pump();
        expect(calls, 0);
        update(() => busy = false);
        await tester.pumpAndSettle();
        expect(find.byType(ButtonProgressIndicator), findsNothing);
        expect(
          find.byIcon(
            selected ? Icons.star_rounded : Icons.star_border_rounded,
          ),
          findsOneWidget,
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('disabled selected favorites use the shared disabled color', (
    tester,
  ) async {
    await _mount(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppFavoriteButton(selected: true, tooltip: 'Remove from favorites'),
          AppFavoriteIcon(selected: true, enabled: false),
        ],
      ),
    );
    final color = Theme.of(tester.element(find.byType(AppFavoriteButton)))
        .disabledColor;
    final icons = tester.widgetList<Icon>(find.byIcon(Icons.star_rounded));
    expect(icons, hasLength(2));
    expect(icons.map((icon) => icon.color), everyElement(color));
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
  });

  for (final (platform, mobile, minimum) in const [
    (TargetPlatform.macOS, false, 42.0),
    (TargetPlatform.macOS, true, 48.0),
    (TargetPlatform.iOS, false, 44.0),
    (TargetPlatform.android, false, 48.0),
  ]) {
    testWidgets('$platform mobile=$mobile keeps the inherited touch target', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(956, 440));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var calls = 0;
      await _mount(
        tester,
        AppFavoriteButton(
          selected: false,
          tooltip: 'Add to favorites',
          onPressed: () => calls++,
          size: 17,
        ),
        mobile: mobile,
      );
      final button = tester.getRect(find.byType(AppFavoriteButton));
      final glyph = tester.getRect(find.byType(AppFavoriteIcon));
      expect(button.width, greaterThanOrEqualTo(minimum));
      expect(button.height, greaterThanOrEqualTo(minimum));
      expect(glyph.size, const Size(17, 17));
      final edge = button.topLeft + const Offset(2, 2);
      expect(glyph.contains(edge), isFalse);
      await tester.tapAt(edge);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }
}
