import 'dart:ui' show Tristate;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSwitch, ShadTheme;

void main() {
  for (final (platform, extent) in const [
    (TargetPlatform.iOS, 44.0),
    (TargetPlatform.android, 48.0),
    (TargetPlatform.macOS, 34.0),
  ]) {
    testWidgets('routing headers align with and without help on $platform', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Column(
              children: [
                RoutingCardHeader(title: 'Direct', help: ['Direct traffic']),
                RoutingCardHeader(title: 'Proxy'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final headers = find.byType(RoutingCardHeader);
      expect(
        tester.getSize(headers.at(0)).height,
        tester.getSize(headers.at(1)).height,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('entry count edges remain actionable on $platform', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var selected = 1;
        final changes = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) => EntryCountPicker(
                    value: selected,
                    onChanged: (value) => setState(() {
                      selected = value;
                      changes.add(value);
                    }),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(EntryCountPicker)),
        )!;
        for (final count in [1, 2, 3]) {
          final target = find.bySemanticsLabel(
            l.prototypeUseEntryServers(count),
          );
          final rect = tester.getRect(target);
          expect(rect.width, greaterThanOrEqualTo(extent));
          expect(rect.height, greaterThanOrEqualTo(extent));
          await tester.tapAt(rect.bottomRight - const Offset(2, 2));
          await tester.pumpAndSettle();
          expect(changes.length, count);
          expect(changes.last, count);
          expect(
            tester
                .getSemantics(target)
                .getSemanticsData()
                .flagsCollection
                .isSelected,
            Tristate.isTrue,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  for (final (locale, mobile) in const [
    (Locale('en'), false),
    (Locale('zh'), true),
    (Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), true),
    (Locale('ru'), false),
    (Locale('fa'), true),
  ]) {
    testWidgets(
      'routing switches toggle without overflow ($locale, mobile=$mobile)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(mobile ? 390 : 1200, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var selected = false;
        var fragmentSelected = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.material(Brightness.light, mobile: mobile),
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            builder: (context, child) => ShadTheme(
              data: AppTheme.shad(Brightness.light, mobile: mobile),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: mobile ? 362 : 440,
                  child: StatefulBuilder(
                    builder: (context, setState) => RoutingCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RoutingFakeDnsRow(
                            value: selected,
                            onChanged: (value) =>
                                setState(() => selected = value),
                          ),
                          RoutingFragmentRow(
                            value: fragmentSelected,
                            onChanged: (value) =>
                                setState(() => fragmentSelected = value),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(RoutingFakeDnsRow)),
        )!;
        expect(find.text(l.routingFakeDns), findsOneWidget);
        expect(find.text(l.routingFakeDnsHint), findsNothing);
        await tester.tap(find.byTooltip('${l.pageHelp} · ${l.routingFakeDns}'));
        await tester.pumpAndSettle();
        expect(find.text(l.routingFakeDnsHint), findsOneWidget);
        expect(selected, isFalse);
        await tester.tap(find.byTooltip(l.prototypeCloseDialog));
        await tester.pumpAndSettle();
        expect(find.text(l.routingFragment), findsOneWidget);
        expect(find.text(l.routingFragmentHint), findsNothing);
        final fakeDnsSwitch = find.descendant(
          of: find.byType(RoutingFakeDnsRow),
          matching: find.byType(ShadSwitch),
        );
        final fragmentSwitch = find.descendant(
          of: find.byType(RoutingFragmentRow),
          matching: find.byType(ShadSwitch),
        );
        expect(tester.widget<ShadSwitch>(fakeDnsSwitch).value, false);
        expect(tester.widget<ShadSwitch>(fragmentSwitch).value, false);
        await tester.tap(fakeDnsSwitch);
        await tester.pumpAndSettle();
        expect(selected, true);
        expect(tester.widget<ShadSwitch>(fakeDnsSwitch).value, true);
        await tester.tap(fragmentSwitch);
        await tester.pumpAndSettle();
        expect(fragmentSelected, true);
        expect(tester.widget<ShadSwitch>(fragmentSwitch).value, true);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final locale in const [Locale('en'), Locale('fa')]) {
    testWidgets('entry count remains draft-only with scaled text ($locale)', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var selected = 1;
      final changes = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: RoutingCard(
                      child: RoutingEntryCountRow(
                        value: selected,
                        onChanged: (value) => setState(() {
                          selected = value;
                          changes.add(value);
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      expect(changes, [3]);
      expect(selected, 3);
      final context = tester.element(find.byType(EntryCountPicker));
      expect(
        tester.widget<Text>(find.text('3')).style?.color,
        ColorManager.palette(context).primaryText,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('routing navigation hides only mobile description', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [390.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: RoutingCard(
              child: RoutingSettingRow(
                icon: LucideIcons.earth,
                title: 'Direct regions',
                description: 'Region explanation',
                value: 'China',
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('China'), findsOneWidget);
      expect(
        find.text('Region explanation'),
        width < 720 ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
