import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/options_form.dart';
import 'package:onexray/pages/connect/routing/smart/controller.dart';
import 'package:onexray/pages/connect/routing/smart/exit_picker_controller.dart';
import 'package:onexray/pages/connect/routing/smart/page.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/routing/smart/editor.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;

const _restore = ValueKey('smart-routing-restore-defaults');
const _timeout = Duration(seconds: 5);

RegionCatalog _regions() => RegionCatalog.fromJson(
  {
    'geosite': {
      'CN': ['CN'],
      'RU': ['CATEGORY-RU'],
    },
    'geoip': {
      'CN': ['CN'],
      'RU': ['RU'],
    },
  },
  geositeCodes: ['CN', 'CATEGORY-RU'],
  geoipCodes: ['CN', 'RU'],
);

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late ConnectionConfiguration original;
  late _LookupService service;
  SmartRoutingEditorController? controller;

  setUp(() async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final exitId = await db.coreConfigDao.insertAssetRow(
      CoreConfigCompanion.insert(
        name: 'Old final exit',
        type: 'outbound',
        tags: '',
        delay: 20,
        subId: 0,
        data: Value(
          base64Encode(
            utf8.encode(
              encodeSingleOutbound({
                'tag': 'Old final exit',
                'protocol': 'freedom',
              }),
            ),
          ),
        ),
      ),
    );
    original = ConnectionConfiguration(
      connection: ConnectionSettings(
        trafficMode: TrafficMode.allVpn,
        smart: SmartRoutingSettings(
          entryCount: 3,
          finalExitId: exitId,
          directRegions: ['RU'],
          directPrivate: false,
          directApple: false,
          directWindows: false,
          directDns: false,
          blockAds: true,
          fakeDns: true,
          fragment: true,
          dns: const RoutingDnsSettings(
            proxyResolvers: [
              RoutingDnsResolver(address: 'https://proxy.example/dns-query'),
              RoutingDnsResolver(address: '9.9.9.9'),
            ],
            directResolvers: [RoutingDnsResolver(address: '1.1.1.1')],
            disableCache: true,
            sameExitOnly: true,
            nonAddressPolicy: NonAddressDnsPolicy.empty,
          ),
          sniffing: const RoutingSniffingSettings(
            routeOnly: true,
            metadataOnly: true,
          ),
          selection: const RoutingSelectionSettings(
            type: 'leastPing',
            probeURL: 'https://probe.example/check',
            probeInterval: '30s',
            enableConcurrency: false,
          ),
        ),
      ),
    );
    await db.connectionConfigDao.commit(configurationJson: original.encode());
    coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => null,
      inspect: (_, {observedStatus}) async =>
          const HostConnection(VpnStatus.disconnected),
      prepare: (_, _) async => throw StateError('Unexpected VPN preparation'),
      start: (_) async => throw StateError('Unexpected VPN start'),
      stop: () async => throw StateError('Unexpected VPN stop'),
    );
    await coordinator.initialize(observe: false, registerReferences: false);
    service = _LookupService(
      db,
      coordinator,
      testXray: (_) async {
        if (!service.validationStarted.isCompleted) {
          service.validationStarted.complete();
        }
        return service.validation == null
            ? ''
            : await service.validation!.future;
      },
    );
  });

  tearDown(() async {
    await controller?.close();
    controller = null;
    coordinator.dispose();
    await db.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.material(Brightness.light),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        builder: (_, child) => ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: ShadToaster(child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                controller = SmartRoutingEditorController(service: service);
                Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => SmartRoutingEditorPage(
                      createController: () => controller!,
                      openRegions: (_, _) async => ['RU'],
                      openFinalExit: (_, _) async => const ServerExitChoice(42),
                    ),
                  ),
                );
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Open editor'));
      await tester.pump();
      if (controller!.state.busy) {
        await controller!.stream
            .firstWhere((state) => !state.busy)
            .timeout(_timeout);
      }
    });
    await tester.pumpAndSettle();
    expect(controller!.state.error, isNull);
  }

  AppLocalizations localizations(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(SmartRoutingEditorPage)))!;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder dns(String kind, int index) => find.descendant(
    of: find.byKey(ValueKey('dns-$kind-$index')),
    matching: find.byType(TextField),
  );

  testWidgets(
    'restore refreshes forms and preview; Cancel preserves saved settings',
    (tester) async {
      await pumpApp(tester);
      await open(tester);
      final l = localizations(tester);
      final loaded = controller!.state.original;
      expect(find.text('Old final exit'), findsOneWidget);
      await tap(tester, find.text(l.routingSelectionProbeSettings));
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byType(RoutingSelectionSettingsForm),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        'https://probe.example/check',
      );
      await tap(tester, find.text(l.routingSniffingMore));
      expect(find.text(l.routingSniffingMetadataOnly), findsOneWidget);

      await tester.ensureVisible(dns('proxy', 0));
      await tester.enterText(dns('proxy', 0), '');
      await tap(tester, find.widgetWithText(FilledButton, l.prototypeSave));
      final error = controller!.state.error;
      expect(error, isNotNull);
      expect(find.text(error!), findsOneWidget);
      await tap(tester, find.byKey(_restore));

      expect(controller!.state.draft.toJson(), SmartRoutingSettings().toJson());
      expect(controller!.state.original, same(loaded));
      expect(controller!.state.finalExitName, isNull);
      expect(controller!.state.error, isNull);
      expect(find.text(error), findsNothing);
      expect(find.text('Old final exit'), findsNothing);
      expect(find.text(l.settingsDefaultsRestored), findsOneWidget);
      expect(find.text(l.routingSelectionProbeSettings), findsNothing);
      expect(find.text(l.routingSniffingMetadataOnly), findsNothing);
      expect(find.text(l.routingSelectionRoundRobin), findsOneWidget);
      expect(find.text(l.prototypeAutomaticEntries(1)), findsOneWidget);
      expect(find.text(controller!.directPreview(l)), findsOneWidget);
      expect(find.byKey(const ValueKey('dns-proxy-1')), findsNothing);
      for (final kind in ['proxy', 'direct']) {
        expect(
          tester.widget<TextField>(dns(kind, 0)).controller!.text,
          RoutingDnsSettings.defaultAddress,
        );
      }
      expect(
        (await tester.runAsync(() => coordinator.configuration))!.encode(),
        original.encode(),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(OutlinedButton, l.prototypeCancel));
      expect(find.byType(SmartRoutingEditorPage), findsNothing);
      await open(tester);
      expect(
        controller!.state.draft.toJson(),
        original.connection.smart.toJson(),
      );
      expect(find.text('Old final exit'), findsOneWidget);
      expect(
        tester.widget<TextField>(dns('proxy', 0)).controller!.text,
        'https://proxy.example/dns-query',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restored settings persist only after Save', (tester) async {
    await pumpApp(tester);
    await open(tester);
    final l = localizations(tester);
    await tap(tester, find.byKey(_restore));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, l.prototypeSave));
      if (controller!.state.busy) {
        await controller!.stream
            .firstWhere((state) => !state.busy)
            .timeout(_timeout);
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(SmartRoutingEditorPage), findsNothing);
    final saved = (await tester.runAsync(() => coordinator.configuration))!;
    expect(saved.connection.smart.toJson(), SmartRoutingSettings().toJson());
    expect(saved.connection.trafficMode, original.connection.trafficMode);
    expect(
      saved.connection.selection.toJson(),
      original.connection.selection.toJson(),
    );
    expect(saved.policy.toJson(), original.policy.toJson());
    await open(tester);
    expect(controller!.state.draft.toJson(), SmartRoutingSettings().toJson());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restore is unavailable while loading and disabled while saving',
    (tester) async {
      final loading = Completer<RegionCatalog>();
      service.regionLookup = loading;
      await pumpApp(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Open editor'));
        await tester.pump();
      });
      expect(find.byKey(_restore), findsNothing);
      controller!.restoreDefaults();
      await tester.runAsync(() async {
        loading.complete(_regions());
        if (controller!.state.busy) {
          await controller!.stream
              .firstWhere((state) => !state.busy)
              .timeout(_timeout);
        }
      });
      service.regionLookup = null;
      await tester.pumpAndSettle();
      final l = localizations(tester);
      await tap(tester, find.byKey(_restore));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final saving = Completer<String>();
      service.validation = saving;
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, l.prototypeSave));
        await service.validationStarted.future.timeout(_timeout);
      });
      await tester.pump();
      expect(tester.widget<TextButton>(find.byKey(_restore)).onPressed, isNull);
      final draft = controller!.state.draft;
      controller!.restoreDefaults();
      expect(controller!.state.draft, same(draft));
      await tester.runAsync(() async {
        saving.complete('Controlled validation failure');
        if (controller!.state.busy) {
          await controller!.stream
              .firstWhere((state) => !state.busy)
              .timeout(_timeout);
        }
      });
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextButton>(find.byKey(_restore)).onPressed,
        isNotNull,
      );
      expect(
        (await tester.runAsync(() => coordinator.configuration))!.encode(),
        original.encode(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late region and final-exit lookups cannot replace restored defaults',
    (tester) async {
      await pumpApp(tester);
      await open(tester);
      final l = localizations(tester);
      final loaded = controller!.state.original;
      final regions = Completer<RegionCatalog>();
      final exit = Completer<String?>();
      service.regionLookup = regions;
      service.exitLookup = exit;
      Finder row(String title) => find.byWidgetPredicate(
        (widget) => widget is RoutingSettingRow && widget.title == title,
      );
      await tap(tester, row(l.prototypeDirectRegions));
      await tap(tester, row(l.prototypeVpnFinalExit));
      await tap(tester, find.byKey(_restore));
      regions.complete(_regions());
      exit.complete('Late final exit');
      await tester.pumpAndSettle();
      expect(controller!.state.draft.toJson(), SmartRoutingSettings().toJson());
      expect(controller!.state.original, same(loaded));
      expect(controller!.state.finalExitName, isNull);
      expect(find.text('Late final exit'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _LookupService extends SmartRoutingEditorService {
  Completer<RegionCatalog>? regionLookup;
  Completer<String?>? exitLookup;
  Completer<String>? validation;
  final validationStarted = Completer<void>();

  _LookupService(
    AppDatabase db,
    ConnectionCoordinator coordinator, {
    required super.testXray,
  }) : super(
         database: db,
         coordinator: coordinator,
         loadRegions: () async => _regions(),
       );

  @override
  Future<RegionCatalog> regions() => regionLookup?.future ?? super.regions();

  @override
  Future<String?> serverName(int? id) =>
      exitLookup?.future ?? super.serverName(id);
}
