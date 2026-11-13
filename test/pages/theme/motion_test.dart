import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/motion.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _app(ValueNotifier<MediaQueryData> preferences, Widget content) =>
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => ValueListenableBuilder<MediaQueryData>(
        valueListenable: preferences,
        builder: (context, data, _) => MediaQuery(
          data: data,
          child: Builder(
            builder: (context) => ShadTheme(
              data: AppTheme.shad(
                Brightness.light,
                reduceMotion: AppMotion.reducedOf(context),
              ),
              child: child!,
            ),
          ),
        ),
      ),
      home: Scaffold(body: Center(child: content)),
    );

void main() {
  testWidgets(
    'system motion changes preserve switch interaction and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final preferences = ValueNotifier(const MediaQueryData());
        final selected = ValueNotifier(false);
        addTearDown(preferences.dispose);
        addTearDown(selected.dispose);
        final changes = <bool>[];
        await tester.pumpWidget(
          _app(
            preferences,
            ValueListenableBuilder<bool>(
              valueListenable: selected,
              builder: (context, value, _) => Semantics(
                label: 'Feature',
                child: AppSwitch(
                  value: value,
                  onChanged: (next) {
                    selected.value = next;
                    changes.add(next);
                  },
                ),
              ),
            ),
          ),
        );

        for (final data in const [
          MediaQueryData(),
          MediaQueryData(reduceMotion: true),
          MediaQueryData(disableAnimations: true),
          MediaQueryData(),
        ]) {
          preferences.value = data;
          await tester.pump();
          final theme = ShadTheme.of(tester.element(find.byType(AppSwitch)));
          expect(
            theme.switchTheme.duration,
            data.reduceMotion || data.disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 100),
          );
          final before = changes.length;
          final next = !selected.value;
          await tester.tap(find.byType(ShadSwitch));
          await tester.pumpAndSettle();
          expect(changes.length, before + 1);
          expect(changes.last, next);
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
              isToggled: next,
              hasTapAction: true,
            ),
          );
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('choice feedback is immediate under either motion preference', (
    tester,
  ) async {
    final preferences = ValueNotifier(const MediaQueryData(reduceMotion: true));
    final selected = ValueNotifier(false);
    addTearDown(preferences.dispose);
    addTearDown(selected.dispose);
    await tester.pumpWidget(
      _app(
        preferences,
        ValueListenableBuilder<bool>(
          valueListenable: selected,
          builder: (context, value, _) => SettingsChoiceRow(
            title: 'Choose this option',
            selected: value,
            onTap: () => selected.value = !value,
          ),
        ),
      ),
    );

    Color? indicatorColor() {
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(SettingsChoiceIndicator),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      return decoration.color;
    }

    for (final data in const [
      MediaQueryData(reduceMotion: true),
      MediaQueryData(disableAnimations: true),
    ]) {
      preferences.value = data;
      selected.value = false;
      await tester.pump();
      expect(indicatorColor(), Colors.transparent);
      await tester.tap(find.text('Choose this option'));
      await tester.pump();
      expect(selected.value, isTrue);
      expect(
        indicatorColor(),
        Theme.of(tester.element(find.byType(SettingsChoiceIndicator)))
            .colorScheme
            .primary,
      );
      expect(tester.takeException(), isNull);
    }

    preferences.value = const MediaQueryData();
    selected.value = false;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose this option'));
    await tester.pump();
    expect(indicatorColor(), Colors.transparent);
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      indicatorColor(),
      Theme.of(tester.element(find.byType(SettingsChoiceIndicator)))
          .colorScheme
          .primary,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
