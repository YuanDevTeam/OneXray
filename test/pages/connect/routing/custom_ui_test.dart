import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/connect/routing/custom/controller.dart';
import 'package:onexray/pages/connect/routing/custom/rule_controller.dart';
import 'package:onexray/pages/connect/routing/custom/rule_page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/connect/routing/custom/editor.dart';
import 'package:onexray/service/connect/routing/custom/geodata_suggestions.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  bool mobile = true,
}) => MaterialApp(
  theme: AppTheme.material(Brightness.light, mobile: mobile),
  locale: locale,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => ShadTheme(
    data: AppTheme.shad(Brightness.light, mobile: mobile),
    child: child!,
  ),
  home: child,
);

Finder _input(TextEditingController controller) => find.byWidgetPredicate(
  (widget) => widget is ShadInput && widget.controller == controller,
);

void main() {
  for (final (locale, mobile) in const [
    (Locale('en'), false),
    (Locale('zh'), true),
    (Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), true),
    (Locale('ru'), false),
    (Locale('fa'), true),
  ]) {
    testWidgets(
      'extended conditions are editable without overflow ($locale, mobile=$mobile)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = mobile
            ? const Size(390, 844)
            : const Size(1280, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final controller = CustomRoutingRuleController(
          rule: RoutingRuleState(
            protocol: const ['http'],
            localOS: const ['darwin'],
          ),
        );
        addTearDown(controller.close);
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: mobile ? null : 500,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: CustomRoutingRuleForm(controller: controller),
                  ),
                ),
              ),
            ),
            locale: locale,
            mobile: mobile,
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.state.moreConditions, true);
        for (final condition in [
          RoutingRuleCondition.protocol,
          RoutingRuleCondition.localOS,
        ]) {
          final header = find
              .descendant(
                of: find.byKey(ValueKey(condition)),
                matching: find.byType(InkWell),
              )
              .first;
          await tester.ensureVisible(header);
          await tester.tap(header);
          await tester.pumpAndSettle();
        }
        final tls = find.widgetWithText(FilterChip, 'TLS');
        await tester.ensureVisible(tls);
        await tester.tap(tls);
        await tester.pumpAndSettle();
        expect(controller.draftRule.protocol, ['http', 'tls']);
        final windows = find.widgetWithText(FilterChip, 'Windows');
        await tester.ensureVisible(windows);
        await tester.tap(windows);
        await tester.pumpAndSettle();
        expect(controller.draftRule.localOS, ['darwin', 'windows']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'conditions stay collapsed with summaries and keep real completion',
    (tester) async {
      _phone(tester);
      final original = RoutingRuleState(
        ruleTag: 'Sites',
        domain: const ['geosite:CN'],
      );
      final controller = CustomRoutingRuleController(
        rule: original,
        loadIndex: () async => const RoutingGeodataIndex(
          domainFiles: {
            'geosite.dat': ['CN'],
            'other.dat': ['CN'],
          },
          ipFiles: {},
        ),
      );
      addTearDown(controller.close);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: CustomRoutingRuleForm(controller: controller),
            ),
          ),
        ),
      );
      expect(find.byType(ShadInput), findsOneWidget);
      expect(find.text('geosite:CN'), findsOneWidget);
      await tester.tap(find.text('Websites and domains'));
      await tester.pumpAndSettle();
      await tester.enterText(_input(controller.domains.single.text), 'cn');
      await tester.pumpAndSettle();
      expect(find.text('ext:other.dat:CN'), findsOneWidget);
      await tester.tap(find.text('ext:other.dat:CN'));
      await tester.pumpAndSettle();
      expect(controller.domains.single.text.text, 'ext:other.dat:CN');
      await tester.tap(find.text('Add another'));
      await tester.pumpAndSettle();
      expect(controller.domains, hasLength(2));
      expect(find.byTooltip('Remove this entry'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Remove this entry').first);
      await tester.pumpAndSettle();
      expect(controller.domains.single.text.text, isEmpty);
      expect(find.byTooltip('Remove this entry'), findsNothing);
      await tester.tap(find.text('Websites and domains'));
      await tester.pumpAndSettle();
      expect(find.byType(ShadInput), findsOneWidget);
      expect(original.domain, ['geosite:CN']);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in const [
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ru'),
    Locale('fa'),
  ]) {
    testWidgets(
      'four-condition form fits phone and preserves input direction ($locale)',
      (tester) async {
        _phone(tester);
        final controller = CustomRoutingRuleController(
          loadIndex: () async =>
              const RoutingGeodataIndex(domainFiles: {}, ipFiles: {}),
        );
        addTearDown(controller.close);
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: CustomRoutingRuleForm(controller: controller),
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(CustomRoutingRuleForm)),
        )!;
        for (final title in [
          l.prototypeWebsitesDomains,
          l.prototypeIpAddressesRanges,
          l.prototypeTargetPort,
        ]) {
          await tester.ensureVisible(find.text(title));
          await tester.tap(find.text(title));
          await tester.pumpAndSettle();
        }
        for (final value in [
          controller.domains.single.text,
          controller.ips.single.text,
          controller.port,
        ]) {
          final editable = find.descendant(
            of: _input(value),
            matching: find.byType(EditableText),
          );
          expect(
            Directionality.of(tester.element(editable)),
            TextDirection.ltr,
          );
          expect(tester.widget<EditableText>(editable).style.fontSize, 16);
        }
        controller.setAction(RoutingRuleAction.block);
        await tester.pumpAndSettle();
        expect(find.text(l.prototypeVpnRuleHint), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'rule save returns a draft for profile validation and cancel discards edits',
    (tester) async {
      _phone(tester);
      RoutingRuleState? result;
      var completed = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.push<RoutingRuleState>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CustomRoutingRulePage(),
                    ),
                  );
                  completed++;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ShadInput>(find.byType(ShadInput)).controller!.text,
        'New rule',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(completed, 1);
      expect(result?.toJson(), {'ruleTag': 'New rule', 'balancerTag': 'proxy'});
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Target port'));
      await tester.pumpAndSettle();
      final port = find.byWidgetPredicate(
        (widget) =>
            widget is ShadInput &&
            widget.placeholder is Text &&
            (widget.placeholder as Text).data == '80, 443, 1000-2000',
      );
      await tester.enterText(port, '443');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result?.toJson(), {
        'ruleTag': 'New rule',
        'port': '443',
        'balancerTag': 'proxy',
      });
      expect(completed, 2);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(completed, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'route ordering and inline edits only change the in-memory draft',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final coordinator = ConnectionCoordinator(database: db);
      final controller = CustomRoutingEditorController(
        service: CustomRoutingEditorService(
          database: db,
          coordinator: coordinator,
        ),
      );
      addTearDown(controller.close);
      addTearDown(coordinator.dispose);
      addTearDown(db.close);
      late BuildContext context;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (value) {
              context = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.runAsync(() async {
        await db.routingProfileDao.insertRow(
          RoutingProfileCompanion.insert(
            name: 'Work 1',
            data: base64Encode(
              utf8.encode('{"outbounds":[{}],"routing":{"rules":[]}}'),
            ),
          ),
        );
        await controller.load(context);
      });
      expect(controller.state.loaded, isTrue);
      expect(controller.routeCount, 2);
      expect(controller.name.text, 'Custom Routing 2');
      expect(controller.state.rules, isEmpty);
      expect(controller.state.fakeDns, false);
      expect(controller.state.fragment, false);
      controller.setFragment(true);
      expect(controller.profileState.fragment, true);
      expect(controller.profileState.fragmentOutbound?['tag'], 'fragment');
      controller.replaceTemplate(
        jsonEncode({
          'outbounds': [{}],
          'dns': {
            'servers': [
              {'tag': 'app-dns-direct', 'address': '8.8.8.8'},
              {'tag': 'app-dns-fake', 'address': 'fakedns'},
            ],
          },
          'routing': {
            'rules': [
              for (final name in ['A', 'B', 'C'])
                {
                  'ruleTag': name,
                  'domain': ['$name.example'],
                  'balancerTag': 'proxy',
                },
            ],
          },
        }),
      );
      final selected = controller.state.selectedRuleKey;
      expect(controller.state.fakeDns, true);
      expect(controller.state.fragment, false);
      expect(controller.profileState.fragmentOutbound, isNull);
      controller.setFragment(true);
      expect(controller.profileState.fragment, true);
      controller.setFragment(false);
      expect(controller.profileState.fragmentOutbound, isNull);
      controller.setFakeDns(false);
      expect(controller.profileState.fakeDns, false);
      controller.setFakeDns(true);
      controller.setDirectDnsAddress('1.1.1.1');
      expect(controller.profileState.directDnsAddress, '1.1.1.1');
      final storedDns = jsonDecode(controller.previewState!.encode())['dns'];
      expect(storedDns['servers'], [
        {'tag': 'app-dns-proxy', 'address': '8.8.8.8', 'timeoutMs': 4000},
        {'tag': 'app-dns-direct', 'address': '1.1.1.1', 'timeoutMs': 4000},
        {'tag': 'app-dns-fake', 'address': 'fakedns'},
      ]);
      expect(storedDns['disableCache'], false);
      for (final removed in [
        'enableParallelQuery',
        'serveStale',
        'serveExpiredTTL',
      ]) {
        expect(storedDns, isNot(contains(removed)));
      }
      controller.reorder(1, 0);
      expect(controller.state.rules.map((rule) => rule.ruleTag), [
        'B',
        'A',
        'C',
      ]);
      expect(controller.state.selectedRuleKey, selected);
      controller.deleteRule(0);
      expect(controller.state.rules.map((rule) => rule.ruleTag), ['A', 'C']);
      expect(controller.state.selectedRuleKey, controller.state.ruleKeys.first);
      controller.setInlineEditing(true);
      expect(controller.inlineRule!.name.text, 'A');
      expect(controller.profileState.directDnsAddress, '1.1.1.1');
      expect(controller.profileState.fakeDns, true);
      controller.inlineRule!.name.text = 'A edited';
      controller.inlineRule!.domains.single.text.text = 'edited.example';
      controller.inlineRule!.port.text = '65536';
      // Parent operations must synchronously flush the inline Cubit draft.
      Future<RoutingRuleState?> unexpectedNavigation(
        BuildContext _,
        RoutingRuleState? _,
      ) async =>
          throw StateError('Desktop must keep the editor beside the list');
      await controller.editRule(context, unexpectedNavigation, 1);
      expect(controller.inlineRule!.name.text, 'C');
      expect(controller.state.rules.first.port, '65536');
      expect(controller.previewState!.rules.first.port, '65536');
      await controller.editRule(context, unexpectedNavigation, 0);
      expect(controller.inlineRule!.domains.single.text.text, 'edited.example');
      expect(controller.inlineRule!.port.text, '65536');
      controller.inlineRule!.port.text = '443';
      controller.reorder(0, 1);
      expect(controller.state.rules.last.ruleTag, 'A edited');
      expect(controller.state.rules.last.port, '443');
      controller.inlineRule!.setAction(RoutingRuleAction.direct);
      await controller.editRule(context, unexpectedNavigation);
      expect(
        controller.state.rules
            .singleWhere((rule) => rule.ruleTag == 'A edited')
            .action,
        RoutingRuleAction.direct,
      );
      expect(controller.inlineRule!.name.text, 'New rule');
      expect(controller.previewState!.rules.last.domain, isEmpty);
      controller.inlineRule!.domains.single.text.text = 'new.example';
      controller.deleteRule(0);
      expect(controller.previewState!.rules, hasLength(2));
      expect(controller.state.rules.last.domain, ['new.example']);
      expect(controller.inlineRule!.name.text, 'New rule');
      controller.deleteRule(1);
      expect(controller.inlineRule!.name.text, 'A edited');
      controller.inlineRule!.port.text = '65536';
      await tester.pump();
      expect(controller.profileState.rules.single.port, '65536');
      controller.inlineRule!.port.text = '443';
      controller.setInlineEditing(false);
      expect(controller.inlineRule, isNull);
      var mobileOpened = false;
      await controller.editRule(context, (_, rule) async {
        mobileOpened = true;
        final current = rule!;
        expect(current.ruleTag, 'A edited');
        return current.copyWith(ruleTag: 'Mobile edit');
      }, 0);
      expect(mobileOpened, isTrue);
      expect(controller.state.rules.last.ruleTag, 'Mobile edit');
      await tester.pump();
      expect(
        await tester.runAsync(() => db.routingProfileDao.allRows),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('route draft waits for readable connection settings', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final coordinator = _PendingConfiguration(database: db);
    final controller = CustomRoutingEditorController(
      service: _PendingCustomSave(database: db, coordinator: coordinator),
    );
    addTearDown(() async {
      await controller.close();
      coordinator.dispose();
      await db.close();
    });
    await tester.pumpWidget(_app(const Text('Draft')));
    final context = tester.element(find.text('Draft'));
    final loading = controller.load(context);
    await coordinator.requested.future;
    expect(controller.state.loaded, isFalse);
    expect(controller.state.processing, isTrue);

    coordinator.result.completeError(StateError('Settings unavailable'));
    await loading;

    expect(controller.state.loaded, isFalse);
    expect(controller.state.processing, isFalse);
    expect(
      controller.state.error,
      AppLocalizations.of(context)!.prototypeCannotReadCustomRoute,
    );
  });

  testWidgets('route save retains transfer resources until save finishes', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final coordinator = ConnectionCoordinator(database: db);
    final service = _PendingCustomSave(database: db, coordinator: coordinator);
    final controller = CustomRoutingEditorController(service: service);
    addTearDown(() async {
      coordinator.dispose();
      await db.close();
    });
    late BuildContext context;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await controller.load(context);

    final saving = controller.save(context);
    await service.started.future;
    unawaited(controller.close());
    await tester.pump();
    expect(controller.transfer.isClosed, isFalse);

    service.result.complete(1);
    await saving;
    await tester.pump();
    expect(controller.transfer.isClosed, isTrue);
  });
}

class _PendingConfiguration extends ConnectionCoordinator {
  _PendingConfiguration({required super.database});

  final requested = Completer<void>();
  final result = Completer<ConnectionConfiguration>();

  @override
  Future<ConnectionConfiguration> get configuration {
    requested.complete();
    return result.future;
  }
}

class _PendingCustomSave extends CustomRoutingEditorService {
  _PendingCustomSave({required super.database, required super.coordinator});

  final started = Completer<void>();
  final result = Completer<int?>();

  @override
  Future<CustomRoutingEditorDraft> load(int? id) async =>
      CustomRoutingEditorDraft(state: RoutingProfileState(name: 'Work'));

  @override
  Future<List<RoutingProfileData>> get rows async => const [];

  @override
  Future<int?> save(
    CustomRoutingEditorDraft draft, {
    required Future<bool> Function() confirmReconnect,
    ConfigurationImportDraft? imported,
  }) {
    started.complete();
    return result.future;
  }
}
