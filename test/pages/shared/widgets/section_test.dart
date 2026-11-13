import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/pages/shared/widgets/section.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('header, description, action and body share one card', (
    tester,
  ) async {
    var actions = 0;
    const body = ValueKey('section-body');
    await _pumpSection(
      tester,
      SectionView(
        title: 'Connection resources',
        description: 'Resources saved on this device',
        padding: EdgeInsets.zero,
        action: OutlinedButton(
          onPressed: () => actions++,
          child: const Text('Manage resources'),
        ),
        child: const SizedBox(key: body, height: 32, width: double.infinity),
      ),
    );

    final card = find.byType(ShadCard);
    expect(card, findsOneWidget);
    for (final content in [
      find.text('Connection resources'),
      find.text('Resources saved on this device'),
      find.text('Manage resources'),
      find.byKey(body),
    ]) {
      expect(find.descendant(of: card, matching: content), findsOneWidget);
    }
    expect(
      find.ancestor(
        of: find.text('Connection resources'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.header == true,
        ),
      ),
      findsOneWidget,
    );
    expect(find.byType(Divider), findsNothing);
    expect(
      _cardInnerRect(tester).right -
          tester
              .getRect(find.widgetWithText(OutlinedButton, 'Manage resources'))
              .right,
      closeTo(18, .01),
    );
    await tester.tap(find.text('Manage resources'));
    await tester.pumpAndSettle();
    expect(actions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header and body use their own prototype insets', (tester) async {
    const body = ValueKey('inset-body');
    await _pumpSection(
      tester,
      const SectionView(
        title: 'Title',
        description: 'Description',
        padding: EdgeInsets.zero,
        child: SizedBox(key: body, height: 32, width: double.infinity),
      ),
    );

    final inner = _cardInnerRect(tester);
    final title = tester.getRect(find.text('Title'));
    final description = tester.getRect(find.text('Description'));
    final content = tester.getRect(find.byKey(body));
    expect(title.left - inner.left, closeTo(18, .01));
    expect(title.top - inner.top, closeTo(16, .01));
    expect(description.top - title.bottom, closeTo(4, .01));
    expect(content.top - description.bottom, closeTo(16, .01));
    expect(content.left - inner.left, closeTo(18, .01));
    expect(inner.right - content.right, closeTo(18, .01));
    expect(inner.bottom - content.bottom, closeTo(18, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer remains outside the card and empty headers add no gap', (
    tester,
  ) async {
    const body = ValueKey('headerless-body');
    await _pumpSection(
      tester,
      const SectionView(
        title: '',
        description: 'Applies to the next connection',
        descriptionBelow: true,
        padding: EdgeInsets.zero,
        child: SizedBox(key: body, height: 32, width: double.infinity),
      ),
    );
    final card = find.byType(ShadCard);
    final footer = find.text('Applies to the next connection');
    expect(find.descendant(of: card, matching: footer), findsNothing);
    expect(
      tester.getRect(footer).top,
      greaterThan(tester.getRect(card).bottom),
    );
    final inner = _cardInnerRect(tester);
    final content = tester.getRect(find.byKey(body));
    expect(content.top - inner.top, closeTo(18, .01));
    expect(inner.bottom - content.bottom, closeTo(18, .01));
    expect(
      find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.header == true,
        ),
      ),
      findsNothing,
    );

    await _pumpSection(
      tester,
      const SectionView(
        title: '',
        padding: EdgeInsets.zero,
        child: SizedBox(key: body, height: 32, width: double.infinity),
      ),
    );
    expect(find.byType(Text), findsNothing);
    expect(
      tester.getRect(find.byKey(body)).top - _cardInnerRect(tester).top,
      closeTo(18, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'action wraps below the identity at the internal width boundary',
    (tester) async {
      for (final (width, stacked) in [(317.0, true), (318.0, false)]) {
        await _pumpSection(
          tester,
          SectionView(
            title: 'Title',
            padding: EdgeInsets.zero,
            action: OutlinedButton(onPressed: () {}, child: const Text('Edit')),
            child: const SizedBox(height: 20, width: double.infinity),
          ),
          width: width,
        );
        // ShadCard's 1px border and the two 18px header insets leave 279/280px.
        expect(
          _cardInnerRect(tester).width - 36,
          closeTo(stacked ? 279 : 280, .01),
        );
        final title = tester.getRect(find.text('Title'));
        final action = tester.getRect(
          find.widgetWithText(OutlinedButton, 'Edit'),
        );
        if (stacked) {
          expect(action.top - title.bottom, closeTo(12, .01));
        } else {
          expect(action.top, lessThan(title.bottom));
          expect(action.left, greaterThan(title.right));
          expect(_cardInnerRect(tester).right - action.right, closeTo(18, .01));
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'large text keeps long header and action reachable in $direction',
      (tester) async {
        var actions = 0;
        const title = 'Настройки соединения и сохранённые ресурсы';
        const description = 'إعدادات الاتصال والموارد المحفوظة على هذا الجهاز';
        const actionLabel = 'Управление';
        await _pumpSection(
          tester,
          SectionView(
            title: title,
            description: description,
            padding: EdgeInsets.zero,
            action: OutlinedButton(
              onPressed: () => actions++,
              child: const Text(actionLabel),
            ),
            child: const Text('Body'),
          ),
          width: 390,
          scale: 2,
          direction: direction,
        );
        final inner = _cardInnerRect(tester);
        final action = find.widgetWithText(OutlinedButton, actionLabel);
        expect(
          tester.getRect(action).top,
          greaterThanOrEqualTo(
            tester.getRect(find.text(description)).bottom + 12,
          ),
        );
        for (final finder in [
          find.text(title),
          find.text(description),
          action,
        ]) {
          final bounds = tester.getRect(finder);
          expect(bounds.left, greaterThanOrEqualTo(inner.left));
          expect(bounds.right, lessThanOrEqualTo(inner.right));
        }
        _expectCompleteText(tester, find.text(title));
        _expectCompleteText(tester, find.text(description));
        _expectCompleteText(tester, find.text(actionLabel));
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(actions, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('sections separate rows only when explicitly requested', (
    tester,
  ) async {
    for (final separated in [false, true]) {
      await _pumpSection(
        tester,
        separated
            ? const SettingSection(
                title: 'Explicit separators',
                separated: true,
                children: [
                  SettingRow(title: 'One'),
                  SettingRow(title: 'Two'),
                ],
              )
            : const SettingSection(
                title: 'Default rows',
                children: [
                  SettingRow(title: 'One'),
                  SettingRow(title: 'Two'),
                ],
              ),
      );
      expect(find.byType(Divider), separated ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a title-only section has balanced edges without an empty body', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      const SettingSection(
        title: 'No custom routes',
        padding: EdgeInsets.zero,
        children: [],
      ),
    );
    final card = _cardInnerRect(tester);
    final title = tester.getRect(find.text('No custom routes'));
    expect(title.top - card.top, closeTo(card.bottom - title.bottom, .01));
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('section icons and rows share an edge in $direction', (
      tester,
    ) async {
      var opened = 0;
      await _pumpSection(
        tester,
        SettingSection(
          title: 'Connection tools',
          icon: LucideIcons.settings,
          padding: EdgeInsets.zero,
          children: [
            SettingRow(
              title: 'Network',
              leading: const Icon(LucideIcons.network),
              showChevron: true,
              onTap: () => opened++,
            ),
          ],
        ),
        direction: direction,
      );
      final heading = tester.getRect(find.text('Connection tools'));
      final row = tester.getRect(find.text('Network'));
      final headingIcon = tester.getRect(find.byIcon(LucideIcons.settings));
      final rowIcon = tester.getRect(find.byIcon(LucideIcons.network));
      if (direction == TextDirection.ltr) {
        expect(row.left, closeTo(heading.left, .01));
        expect(rowIcon.left, closeTo(headingIcon.left, .01));
      } else {
        expect(row.right, closeTo(heading.right, .01));
        expect(rowIcon.right, closeTo(headingIcon.right, .01));
      }
      await tester.tap(find.text('Network'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('page gutters stay inside the responsive content width', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [390.0, 834.0, 1160.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPageScroll(
              padding: const EdgeInsets.all(28),
              child: const SizedBox(
                key: ValueKey('page-content'),
                height: 80,
                width: double.infinity,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final content = tester.getRect(
        find.byKey(const ValueKey('page-content')),
      );
      final outer = width >= 840 ? (width - 960) / 2 : 0;
      expect(content.left, closeTo(outer + 28, .01));
      expect(width - content.right, closeTo(outer + 28, .01));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('rows use plain leading icons and 12px padding unless opted in', (
    tester,
  ) async {
    const leading = ValueKey('leading-icon');
    const trailing = ValueKey('trailing-icon');
    Rect? plainIcon;
    for (final decorate in [false, true]) {
      await _pumpSection(
        tester,
        decorate
            ? const SettingRow(
                title: 'Decorated',
                decorateLeading: true,
                leading: Icon(LucideIcons.settings, key: leading, size: 20),
                trailing: Icon(
                  LucideIcons.chevronRight,
                  key: trailing,
                  size: 20,
                ),
              )
            : const SettingRow(
                title: 'Plain',
                leading: Icon(LucideIcons.settings, key: leading, size: 20),
                trailing: Icon(
                  LucideIcons.chevronRight,
                  key: trailing,
                  size: 20,
                ),
              ),
      );
      final row = find.byType(SettingRow);
      final rowBounds = tester.getRect(row);
      final icon = tester.getRect(find.byKey(leading));
      expect(
        rowBounds.right - tester.getRect(find.byKey(trailing)).right,
        closeTo(12, .01),
      );
      if (decorate) {
        expect(icon.left, greaterThan(plainIcon!.left));
      } else {
        plainIcon = icon;
        expect(icon.left - rowBounds.left, closeTo(12, .01));
        expect(
          tester.getRect(find.text('Plain')).left - icon.right,
          closeTo(12, .01),
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'a switch inside the card activates once from either hit target',
    (tester) async {
      var value = false;
      final changes = <bool>[];
      await _pumpSection(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SettingSection(
            title: 'Controls',
            children: [
              SwitchSettingRow(
                title: 'Enable feature',
                value: value,
                onChanged: (next) => setState(() {
                  value = next;
                  changes.add(next);
                }),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Enable feature'));
      await tester.pumpAndSettle();
      expect(changes, [true]);
      expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isTrue);
      await tester.tap(find.byType(ShadSwitch));
      await tester.pumpAndSettle();
      expect(changes, [true, false]);
      expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('setting section exposes Material ink for native switch rows', (
    tester,
  ) async {
    var enabled = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ShadTheme(
          data: ShadThemeData(colorScheme: const ShadBlueColorScheme.light()),
          child: child!,
        ),
        home: Scaffold(
          body: SettingSection(
            title: 'Logs',
            children: [
              SwitchListTile(
                title: const Text('Record logs'),
                value: enabled,
                onChanged: (value) => enabled = value,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Record logs'));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSection(
  WidgetTester tester,
  Widget section, {
  double width = 600,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final scaler = TextScaler.linear(scale);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.material(Brightness.light, mobile: width < 720),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: ShadTheme(
          data: AppTheme.shad(
            Brightness.light,
            mobile: width < 720,
            textScaler: scaler,
          ),
          child: Directionality(textDirection: direction, child: child!),
        ),
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: section),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _cardInnerRect(WidgetTester tester) {
  final card = find.byType(ShadCard);
  final container = find
      .descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).border != null,
        ),
      )
      .first;
  final decoration =
      tester.widget<Container>(container).decoration! as BoxDecoration;
  final border = decoration.border!.dimensions.resolve(TextDirection.ltr);
  return border.deflateRect(tester.getRect(card));
}

void _expectCompleteText(WidgetTester tester, Finder finder) {
  final richText = find.descendant(of: finder, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(richText);
  expect(paragraph.didExceedMaxLines, isFalse);
  final text = paragraph.text.toPlainText();
  // Selection boxes include invisible trailing spaces beyond the paint bounds.
  // Check every non-whitespace run so real glyph clipping still fails.
  for (final word in RegExp(r'\S+', unicode: true).allMatches(text)) {
    final diagnostic =
        'word=${word.group(0)} text=$text '
        'size=${paragraph.size} constraints=${paragraph.constraints} '
        'scaler=${tester.widget<RichText>(richText).textScaler}';
    for (final box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: word.start, extentOffset: word.end),
    )) {
      expect(box.left, greaterThanOrEqualTo(-.5), reason: diagnostic);
      expect(
        box.right,
        lessThanOrEqualTo(paragraph.size.width + .5),
        reason: diagnostic,
      );
      expect(box.top, greaterThanOrEqualTo(-.5), reason: diagnostic);
      expect(
        box.bottom,
        lessThanOrEqualTo(paragraph.size.height + .5),
        reason: diagnostic,
      );
    }
  }
}
