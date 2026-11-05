import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Future<void> _mount(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: ShadTheme(
      data: AppTheme.shad(Brightness.light),
      child: Scaffold(body: child),
    ),
  ),
);

SemanticsFinder _button(String label) => find.semantics.byPredicate((node) {
  final data = node.getSemanticsData();
  return data.flagsCollection.isButton &&
      (data.label.contains(label) || data.tooltip == label);
});

void _testWithSemantics(
  String description,
  Future<void> Function(WidgetTester) body,
) => testWidgets(description, (tester) async {
  final semantics = tester.ensureSemantics();
  try {
    await body(tester);
  } finally {
    // The widget tester verifies handles before test package tearDown runs.
    semantics.dispose();
  }
});

void main() {
  _testWithSemantics(
    'action row exposes its role, context and one tap action',
    (tester) async {
      var calls = 0;
      await _mount(
        tester,
        SettingRow(
          title: 'Routing data',
          subtitle: 'Two datasets',
          value: 'Current',
          showChevron: true,
          onTap: () => calls++,
        ),
      );
      final action = _button('Routing data');
      expect(action, findsOneWidget);
      final node = tester.getSemantics(find.byType(SettingRow));
      expect(
        node,
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      expect(node.getSemanticsData().label, contains('Two datasets'));
      expect(node.getSemanticsData().label, contains('Current'));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('Routing data'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  _testWithSemantics(
    'disabled actions retain their role and read-only rows do not',
    (tester) async {
      var calls = 0;
      await _mount(
        tester,
        Column(
          children: [
            SettingRow(
              title: 'Disabled action',
              enabled: false,
              onTap: () => calls++,
            ),
            const SettingRow(title: 'Read only', value: 'Current'),
          ],
        ),
      );
      expect(_button('Disabled action'), findsOneWidget);
      final node = tester.getSemantics(
        find.widgetWithText(SettingRow, 'Disabled action'),
      );
      expect(
        node,
        isSemantics(isButton: true, isEnabled: false, hasTapAction: false),
      );
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.tap(find.text('Disabled action'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(_button('Read only'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  _testWithSemantics(
    'trailing button keeps its own name and independent action',
    (tester) async {
      var opens = 0;
      var more = 0;
      await _mount(
        tester,
        SettingRow(
          title: 'Source details',
          onTap: () => opens++,
          trailing: IconButton(
            tooltip: 'More source actions',
            onPressed: () => more++,
            icon: const Icon(LucideIcons.ellipsis),
          ),
        ),
      );
      final row = _button('Source details');
      final trailing = _button('More source actions');
      expect(row, findsOneWidget);
      expect(trailing, findsOneWidget);
      final rowNode = tester.getSemantics(find.byType(SettingRow));
      final trailingNode = tester.getSemantics(find.byType(IconButton));
      expect(rowNode.id, isNot(trailingNode.id));
      expect(
        trailingNode,
        isSemantics(
          isButton: true,
          tooltip: 'More source actions',
          hasTapAction: true,
        ),
      );
      rowNode.owner!.performAction(rowNode.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(more, 0);
      trailingNode.owner!.performAction(trailingNode.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(more, 1);
      await tester.tap(find.byTooltip('More source actions'));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(more, 2);
      expect(tester.takeException(), isNull);
    },
  );

  _testWithSemantics('switch row keeps one toggle without a button role', (
    tester,
  ) async {
    var value = false;
    final changes = <bool>[];
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) => SwitchSettingRow(
          title: 'Enable feature',
          value: value,
          onChanged: (next) => setState(() {
            value = next;
            changes.add(next);
          }),
        ),
      ),
    );
    final toggles = find.semantics.byPredicate(
      (node) =>
          node.getSemanticsData().flagsCollection.isToggled != Tristate.none,
    );
    expect(toggles, findsOneWidget);
    expect(
      find.semantics.byPredicate(
        (node) => node.getSemanticsData().flagsCollection.isButton,
      ),
      findsNothing,
    );
    final node = tester.getSemantics(find.byType(ShadSwitch));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(changes, [true]);
    await tester.tap(find.text('Enable feature'));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(toggles, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _testWithSemantics(
    'navigation and trailing switch expose independent semantic actions',
    (tester) async {
      var opens = 0;
      var value = false;
      final changes = <bool>[];
      await _mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SettingRow(
            title: 'LAN details',
            onTap: () => opens++,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppSwitch(
                  value: value,
                  onChanged: (next) => setState(() {
                    value = next;
                    changes.add(next);
                  }),
                ),
                const Icon(LucideIcons.chevronRight),
              ],
            ),
          ),
        ),
      );
      final navigation = _button('LAN details');
      final toggles = find.semantics.byPredicate(
        (node) =>
            node.getSemanticsData().flagsCollection.isToggled != Tristate.none,
      );
      expect(navigation, findsOneWidget);
      expect(toggles, findsOneWidget);
      final navigationNode = tester.getSemantics(find.byType(SettingRow));
      final toggleNode = tester.getSemantics(find.byType(ShadSwitch));
      expect(navigationNode.id, isNot(toggleNode.id));
      expect(
        toggleNode,
        isSemantics(isButton: false, isToggled: false, hasTapAction: true),
      );
      navigationNode.owner!.performAction(
        navigationNode.id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(changes, isEmpty);
      toggleNode.owner!.performAction(toggleNode.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(changes, [true]);
      expect(tester.takeException(), isNull);
    },
  );
}
