import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('setting switch exposes its enabled state and activates once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var value = false;
    final changes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SwitchSettingRow(
                title: 'Enable feature',
                value: value,
                onChanged: (next) => setState(() {
                  value = next;
                  changes.add(next);
                }),
              ),
            ),
          ),
        ),
      ),
    );

    final toggles = find.semantics.byPredicate(
      (node) =>
          node.getSemanticsData().flagsCollection.isToggled != Tristate.none,
    );
    expect(toggles, findsOneWidget);
    final node = toggles.evaluate().single;
    expect(
      node,
      isSemantics(
        hasEnabledState: true,
        isEnabled: true,
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
      ),
    );
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(
      toggles.evaluate().single,
      isSemantics(isEnabled: true, isToggled: true),
    );

    await tester.tap(find.byType(ShadSwitch));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    await tester.tap(find.text('Enable feature'));
    await tester.pumpAndSettle();
    expect(changes, [true, false, true]);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final (enabled, hasCallback) in [(false, true), (true, false)]) {
    testWidgets(
      'switch is disabled for enabled=$enabled callback=$hasCallback',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var changes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: ShadTheme(
              data: AppTheme.shad(Brightness.light),
              child: Scaffold(
                body: Center(
                  child: Semantics(
                    label: 'Disabled feature',
                    child: AppSwitch(
                      value: true,
                      enabled: enabled,
                      onChanged: hasCallback ? (_) => changes++ : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final toggles = find.semantics.byPredicate(
          (node) =>
              node.getSemanticsData().flagsCollection.isToggled !=
              Tristate.none,
        );
        expect(toggles, findsOneWidget);
        final node = toggles.evaluate().single;
        expect(
          node,
          isSemantics(
            label: 'Disabled feature',
            hasEnabledState: true,
            isEnabled: false,
            hasToggledState: true,
            isToggled: true,
            hasTapAction: false,
          ),
        );
        expect(
          tester.widget<ShadSwitch>(find.byType(ShadSwitch)).enabled,
          false,
        );
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.tap(find.byType(AppSwitch), warnIfMissed: false);
        final focus = tester.widget<Focus>(
          find.descendant(
            of: find.byType(AppSwitch),
            matching: find.byWidgetPredicate(
              (widget) => widget is Focus && widget.focusNode != null,
            ),
          ),
        );
        focus.focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(changes, 0);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets('existing labelled semantics keep a single enabled switch', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: Scaffold(
            body: Center(
              child: Semantics(
                label: 'Automatic backup',
                child: AppSwitch(value: true, onChanged: (_) => changes++),
              ),
            ),
          ),
        ),
      ),
    );
    final toggles = find.semantics.byPredicate(
      (node) =>
          node.getSemanticsData().flagsCollection.isToggled != Tristate.none,
    );
    expect(toggles, findsOneWidget);
    expect(
      toggles.evaluate().single,
      isSemantics(
        label: 'Automatic backup',
        hasEnabledState: true,
        isEnabled: true,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    tester.semantics.tap(toggles);
    await tester.pumpAndSettle();
    expect(changes, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
