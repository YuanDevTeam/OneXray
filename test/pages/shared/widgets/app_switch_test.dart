import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  for (final (platform, minimum) in const [
    (TargetPlatform.iOS, 44.0),
    (TargetPlatform.android, 48.0),
    (TargetPlatform.macOS, 0.0),
  ]) {
    for (final (trackWidth, trackHeight) in const [
      (44.0, 26.0),
      (60.0, 30.0),
    ]) {
      testWidgets(
        'switch keeps its track and one semantic toggle with a $platform touch target ($trackWidth x $trackHeight)',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            var value = false;
            var enabled = true;
            late StateSetter update;
            final changes = <bool>[];
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light.copyWith(platform: platform),
                home: ShadTheme(
                  data: AppTheme.shad(Brightness.light),
                  child: Scaffold(
                    body: Center(
                      child: StatefulBuilder(
                        builder: (context, setState) {
                          update = setState;
                          return Semantics(
                            label: 'Feature',
                            child: AppSwitch(
                              value: value,
                              enabled: enabled,
                              width: trackWidth,
                              height: trackHeight,
                              onChanged: (next) => setState(() {
                                value = next;
                                changes.add(next);
                              }),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final control = find.byType(AppSwitch);
            final track = find.byType(ShadSwitch);
            final bounds = tester.getRect(control);
            final trackBounds = tester.getRect(track);
            expect(trackBounds.width, trackWidth);
            expect(trackBounds.height, trackHeight);
            expect(bounds.width, greaterThanOrEqualTo(minimum));
            expect(bounds.height, greaterThanOrEqualTo(minimum));
            final toggles = find.semantics.byPredicate(
              (node) =>
                  node.getSemanticsData().flagsCollection.isToggled !=
                  Tristate.none,
            );
            expect(toggles, findsOneWidget);
            expect(
              toggles.evaluate().single,
              isSemantics(
                label: 'Feature',
                isEnabled: true,
                isToggled: false,
                hasTapAction: true,
              ),
            );

            final edge = Offset(bounds.center.dx, bounds.top + .5);
            if (minimum > 0) {
              expect(trackBounds.contains(edge), isFalse);
              await tester.tapAt(edge);
              await tester.pumpAndSettle();
              expect(changes, [true]);
            } else {
              expect(bounds.size, trackBounds.size);
            }
            final beforeTrack = changes.length;
            final nextTrackValue = !value;
            await tester.tap(track);
            await tester.pumpAndSettle();
            expect(changes.length, beforeTrack + 1);
            expect(changes.last, nextTrackValue);

            final focus = tester.widget<Focus>(
              find.descendant(
                of: control,
                matching: find.byWidgetPredicate(
                  (widget) => widget is Focus && widget.focusNode != null,
                ),
              ),
            );
            focus.focusNode!.requestFocus();
            await tester.pump();
            final beforeKeyboard = changes.length;
            final nextKeyboardValue = !value;
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pumpAndSettle();
            expect(changes.length, beforeKeyboard + 1);
            expect(changes.last, nextKeyboardValue);

            update(() => enabled = false);
            await tester.pumpAndSettle();
            expect(toggles, findsOneWidget);
            expect(
              toggles.evaluate().single,
              isSemantics(
                label: 'Feature',
                isEnabled: false,
                isToggled: value,
                hasTapAction: false,
              ),
            );
            final beforeDisabled = List<bool>.of(changes);
            await tester.tapAt(edge);
            await tester.tap(track, warnIfMissed: false);
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(changes, beforeDisabled);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

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
