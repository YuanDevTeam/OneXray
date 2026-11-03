import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/l10n/localizations/app_localizations_en.dart';
import 'package:onexray/pages/connect/target_picker.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton, ShadTheme;

void main() {
  final l = AppLocalizationsEn();
  final sources = [
    _source(7, 'Duplicate'),
    _source(11, 'Provider source', provider: true),
  ];
  final rows = [
    _node(1, 'Measured', 30, sourceId: 7),
    _node(2, 'Unmeasured', PingDelayConstants.unknown),
    _node(3, 'Failed probe', PingDelayConstants.error),
    _node(4, 'Timed out', PingDelayConstants.timeout),
    _node(6, 'Final exit', 1),
    _node(
      7,
      'Duplicate',
      PingDelayConstants.unknown,
      sourceId: 11,
      type: 'Remnawave',
    ),
    _node(8, 'Inactive provider cache', 1, sourceId: 7, type: 'Remnawave'),
    _node(9, 'Inactive ordinary cache', 1, sourceId: 11),
    CoreConfigData(
      id: 10,
      name: 'Unreadable',
      type: 'outbound',
      tags: '',
      delay: 1,
      subId: 0,
      manualSortOrder: 0,
      favorite: false,
    ),
  ];
  final catalog = ServerCatalog(servers: rows, sources: sources);
  final raws = List.generate(
    4,
    (i) => _node(
      40 + i,
      i == 0 ? 'Duplicate' : 'Legacy Raw ${i + 1}',
      PingDelayConstants.unknown,
      type: 'raw',
    ),
  );
  ConnectionTargetChoice? choice;
  var completions = 0;

  String scopeName(ServerSelection scope) => switch (scope.kind) {
    SelectionKind.automatic => l.prototypeAutomaticSelection,
    SelectionKind.source =>
      scope.id == 0 ? l.prototypeManualAdditions : 'Duplicate',
    SelectionKind.server => 'Server ${scope.id}',
  };

  Future<void> open(
    WidgetTester tester,
    ConnectionSettings settings, {
    Size size = const Size(960, 1100),
    EdgeInsets viewInsets = EdgeInsets.zero,
    double textScale = 1,
    ServerCatalog? catalogOverride,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    choice = null;
    completions = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            viewInsets: viewInsets,
            textScaler: TextScaler.linear(textScale),
          ),
          child: ShadTheme(
            data: AppTheme.shad(Brightness.light),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                choice = await showAppDialog<ConnectionTargetChoice>(
                  context,
                  (_) => ConnectionTargetPicker(
                    settings: settings,
                    catalog: catalogOverride ?? catalog,
                    raws: raws,
                    candidateCount: (scope) => (catalogOverride ?? catalog)
                        .servers
                        .where(
                          (row) =>
                              row.id != settings.finalExitId &&
                              (catalogOverride ?? catalog).outboundEligible(
                                row,
                              ) &&
                              (scope.kind == SelectionKind.automatic ||
                                  row.subId == scope.id),
                        )
                        .length,
                    selectionName: scopeName,
                  ),
                );
                completions++;
              },
              child: const Text('Choose target'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose target'));
    await tester.pumpAndSettle();
  }

  Finder tile(String title, {String? subtitle}) => find.byWidgetPredicate(
    (widget) =>
        widget is ListTile &&
        widget.title is Text &&
        (widget.title! as Text).data == title &&
        (subtitle == null ||
            widget.subtitle is Text &&
                (widget.subtitle! as Text).data == subtitle),
  );

  bool isSelected(WidgetTester tester, Finder row) =>
      tester
          .widget<Semantics>(
            find.ancestor(of: row, matching: find.byType(Semantics)).first,
          )
          .properties
          .selected ==
      true;

  Future<void> reveal(WidgetTester tester, Finder row) async {
    final lists = find.byKey(const ValueKey('connection-target-options'));
    if (lists.evaluate().isEmpty) {
      await tester.ensureVisible(row);
    } else {
      final scrollable = find
          .descendant(of: lists.first, matching: find.byType(Scrollable))
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        row,
        tester
            .state<ScrollableState>(scrollable)
            .position
            .viewportDimension
            .clamp(120.0, 320.0),
        scrollable: scrollable,
        maxScrolls: 180,
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String title) async {
    final chip = find.widgetWithText(ChoiceChip, title);
    await reveal(tester, chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String text) async {
    final input = find.byKey(const ValueKey('connection-target-search'));
    await reveal(tester, input);
    await tester.enterText(input, text);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'source ID collisions keep automatic scope selected by kind and ID',
    (tester) async {
      final settings = ConnectionSettings(
        selection: const ServerSelection.source(7),
        smart: SmartRoutingSettings(finalExitId: 6),
      );
      final before = settings.toJson();
      await open(tester, settings);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, l.serverSelectionAutomaticScope),
            )
            .selected,
        isTrue,
      );
      expect(isSelected(tester, tile('Duplicate')), isTrue);
      expect(find.text(l.connectionCandidates(4)), findsOneWidget);
      expect(find.text(l.connectionCandidates(3)), findsOneWidget);
      expect(find.text(l.connectionCandidates(1)), findsOneWidget);
      await tab(tester, l.serverCompleteConfigurationsTab);
      await reveal(
        tester,
        tile('Duplicate', subtitle: l.providerConfigurationTitle),
      );
      expect(
        isSelected(
          tester,
          tile('Duplicate', subtitle: l.providerConfigurationTitle),
        ),
        isFalse,
      );
      await reveal(tester, tile('Duplicate', subtitle: l.xrayRawPageTitle));
      expect(
        isSelected(tester, tile('Duplicate', subtitle: l.xrayRawPageTitle)),
        isFalse,
      );
      expect(completions, 0);
      expect(settings.toJson(), before);
      await tester.tap(find.widgetWithText(ShadButton, l.prototypeCancel));
      await tester.pumpAndSettle();
      expect(choice, isNull);
      expect(completions, 1);
      expect(settings.toJson(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fixed choices include failed or unmeasured nodes, excluding final exit and inactive caches',
    (tester) async {
      final settings = ConnectionSettings(
        selection: const ServerSelection.server(3),
        smart: SmartRoutingSettings(finalExitId: 6),
      );
      await open(tester, settings);
      for (final title in [
        'Measured',
        'Unmeasured',
        'Failed probe',
        'Timed out',
      ]) {
        await reveal(tester, tile(title));
        expect(tile(title), findsOneWidget);
      }
      for (final title in [
        'Final exit',
        'Inactive provider cache',
        'Inactive ordinary cache',
        'Unreadable',
      ]) {
        await search(tester, title);
        expect(tile(title), findsNothing);
        expect(find.text(l.serverNoMatchingResources), findsOneWidget);
      }
      await search(tester, '');
      await reveal(tester, tile('Failed probe'));
      expect(isSelected(tester, tile('Failed probe')), isTrue);
      expect(isSelected(tester, tile('Unmeasured')), isFalse);
      await reveal(tester, tile('Unmeasured'));
      await tester.tap(tile('Unmeasured'));
      await tester.pumpAndSettle();
      expect(choice?.selection?.kind, SelectionKind.server);
      expect(choice?.selection?.id, 2);
      expect(choice?.rawId, isNull);
      expect(settings.selection.id, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Raw and provider choices with equal names retain separate resource identities',
    (tester) async {
      final settings = ConnectionSettings(
        expert: true,
        rawId: 40,
        selection: const ServerSelection.server(7),
      );
      await open(tester, settings);
      final raw = tile('Duplicate', subtitle: l.xrayRawPageTitle);
      final provider = tile(
        'Duplicate',
        subtitle: l.providerConfigurationTitle,
      );
      await reveal(tester, raw);
      expect(isSelected(tester, raw), isTrue);
      await reveal(tester, provider);
      expect(isSelected(tester, provider), isFalse);
      for (final row in raws) {
        await reveal(tester, tile(row.name, subtitle: l.xrayRawPageTitle));
        expect(tile(row.name, subtitle: l.xrayRawPageTitle), findsOneWidget);
      }
      await reveal(tester, provider);
      await tester.tap(provider);
      await tester.pumpAndSettle();
      expect(choice?.selection?.kind, SelectionKind.server);
      expect(choice?.selection?.id, 7);
      expect(choice?.rawId, isNull);
      expect(settings.expert, isTrue);
      expect(settings.rawId, 40);

      await open(
        tester,
        ConnectionSettings(selection: const ServerSelection.server(7)),
      );
      await reveal(
        tester,
        tile('Duplicate', subtitle: l.providerConfigurationTitle),
      );
      expect(
        isSelected(
          tester,
          tile('Duplicate', subtitle: l.providerConfigurationTitle),
        ),
        isTrue,
      );
      await reveal(tester, tile('Duplicate', subtitle: l.xrayRawPageTitle));
      expect(
        isSelected(tester, tile('Duplicate', subtitle: l.xrayRawPageTitle)),
        isFalse,
      );
      await tester.tap(tile('Duplicate', subtitle: l.xrayRawPageTitle));
      await tester.pumpAndSettle();
      expect(choice?.rawId, 40);
      expect(choice?.selection, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search and tab changes stay local; restore and management are explicit intents',
    (tester) async {
      final settings = ConnectionSettings(expert: true, rawId: 40);
      final before = settings.toJson();
      await open(tester, settings);
      await search(tester, 'legacy raw 3');
      expect(tile('Legacy Raw 3'), findsOneWidget);
      expect(tile('Duplicate', subtitle: l.xrayRawPageTitle), findsNothing);
      expect(completions, 0);
      await search(tester, '');
      await tab(tester, l.serverSelectionAutomaticScope);
      await tester.tap(find.text(l.connectionRestoreOrdinary));
      await tester.pumpAndSettle();
      expect(choice?.restore, isTrue);
      expect(choice?.selection, isNull);
      expect(settings.toJson(), before);
      await open(tester, settings);
      await tester.tap(find.widgetWithText(OutlinedButton, l.prototypeServers));
      await tester.pumpAndSettle();
      expect(choice?.manage, isTrue);
      expect(choice?.rawId, isNull);
      expect(choice?.selection, isNull);
      expect(settings.toJson(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'normal-height target picker keeps actions fixed while its one content surface scrolls',
    (tester) async {
      final many = ServerCatalog(
        servers: List.generate(
          60,
          (index) => _node(
            100 + index,
            'Long-list server ${index + 1}',
            PingDelayConstants.unknown,
          ),
        ),
      );
      await open(
        tester,
        ConnectionSettings(selection: const ServerSelection.server(100)),
        catalogOverride: many,
      );
      final cancel = find.widgetWithText(ShadButton, l.prototypeCancel);
      final manage = find.widgetWithText(OutlinedButton, l.prototypeServers);
      final cancelBounds = tester.getRect(cancel);
      final manageBounds = tester.getRect(manage);
      await reveal(tester, tile('Long-list server 60'));
      expect(tester.getRect(cancel), cancelBounds);
      expect(tester.getRect(manage), manageBounds);
      expect(cancel.hitTestable(), findsOneWidget);
      expect(manage.hitTestable(), findsOneWidget);
      expect(completions, 0);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(choice, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (name, size, insets, scale) in const [
    ('phone keyboard', Size(390, 844), EdgeInsets.only(bottom: 320), 1.3),
    ('short phone with large text', Size(390, 360), EdgeInsets.zero, 2.0),
    (
      'wide short window with keyboard',
      Size(850, 340),
      EdgeInsets.only(bottom: 120),
      1.3,
    ),
  ]) {
    testWidgets(
      'target browsing and both footer actions remain reachable: $name',
      (tester) async {
        final many = ServerCatalog(
          servers: List.generate(
            60,
            (index) => _node(
              100 + index,
              'Long-list server ${index + 1}',
              PingDelayConstants.unknown,
            ),
          ),
        );
        final settings = ConnectionSettings(
          selection: const ServerSelection.server(100),
        );
        final before = settings.toJson();
        for (final manage in [false, true]) {
          await open(
            tester,
            settings,
            size: size,
            viewInsets: insets,
            textScale: scale,
            catalogOverride: many,
          );
          expect(tester.takeException(), isNull);
          final picker = find.byType(ConnectionTargetPicker);
          final pickerBounds = tester.getRect(picker);
          final keyboardTop = size.height - insets.bottom;
          expect(pickerBounds.bottom, lessThanOrEqualTo(keyboardTop + .01));
          expect(pickerBounds.top, greaterThanOrEqualTo(0));
          expect(pickerBounds.height, greaterThan(100));
          final surface = find.byKey(
            const ValueKey('connection-target-options'),
          );
          expect(
            find.descendant(
              of: surface,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            ),
            findsOneWidget,
          );
          final searchInput = find.byKey(
            const ValueKey('connection-target-search'),
          );
          await reveal(tester, searchInput);
          expect(searchInput.hitTestable(), findsOneWidget);
          await search(tester, 'Long-list server 60');
          expect(tile('Long-list server 60'), findsOneWidget);
          expect(completions, 0);
          await search(tester, '');
          await reveal(tester, tile('Long-list server 60'));
          expect(tile('Long-list server 60').hitTestable(), findsOneWidget);
          expect(settings.toJson(), before);
          expect(completions, 0);
          final action = manage
              ? find.widgetWithText(OutlinedButton, l.prototypeServers)
              : find.widgetWithText(ShadButton, l.prototypeCancel);
          await reveal(tester, action);
          expect(action.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(action).bottom,
            lessThanOrEqualTo(keyboardTop + .01),
          );
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(picker, findsNothing);
          expect(completions, 1);
          expect(choice?.manage, manage ? isTrue : isNull);
          expect(choice?.selection, isNull);
          expect(choice?.rawId, isNull);
          expect(settings.toJson(), before);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}

CoreConfigData _node(
  int id,
  String name,
  int delay, {
  int sourceId = 0,
  String type = 'outbound',
}) => CoreConfigData(
  id: id,
  name: name,
  type: type,
  tags: '',
  delay: delay,
  subId: sourceId,
  manualSortOrder: 0,
  favorite: false,
  data: base64Encode(
    utf8.encode(
      jsonEncode({
        'outbounds': [
          {'tag': name, 'protocol': type == 'outbound' ? 'socks' : 'freedom'},
        ],
      }),
    ),
  ),
);

SubscriptionData _source(int id, String name, {bool provider = false}) =>
    SubscriptionData(
      id: id,
      name: name,
      url: 'https://source.example/$id',
      panel: 'generic',
      mode: provider ? 'providerManaged' : 'appManaged',
      hwidEnabled: false,
      timestamp: DateTime(2026, 11, 3),
    );
