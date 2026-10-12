import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/l10n/localizations/app_localizations_en.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/connect/routing/smart/exit_picker_controller.dart';
import 'package:onexray/pages/connect/routing/smart/exit_picker.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/servers/outbound/map.dart';

CoreConfigData _server(int id, {int delay = 20}) => CoreConfigData(
  id: id,
  name: 'Server $id',
  type: 'outbound',
  tags: '',
  data: base64Encode(
    utf8.encode(
      encodeSingleOutbound({
        'tag': 'Server $id',
        'protocol': 'vless',
        'streamSettings': {'network': 'xhttp', 'security': 'tls'},
      }),
    ),
  ),
  delay: delay,
  subId: 0,
  favorite: false,
);

void main() {
  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
  });
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late ServerExitPickerController controller;
  final l = AppLocalizationsEn();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(database: db);
    controller = ServerExitPickerController(
      const ServerExitPickerParams(selectedId: 2, excludedIds: {1}),
      database: db,
      coordinator: coordinator,
    );
    await db.coreConfigDao.insertRows([
      for (final row in [
        _server(1),
        _server(2),
        _server(3),
        _server(4, delay: PingDelayConstants.error),
      ])
        row.toCompanion(false),
    ]);
    await controller.initialize();
    await controller.stream.firstWhere(
      (state) => state.catalog.servers.length == 4,
    );
  });

  tearDown(() async {
    await controller.close();
    coordinator.dispose();
    await db.close();
  });

  test(
    'draft keeps exclusions, real health and search within subscriptions',
    () async {
      final before = (await coordinator.configuration).encode();
      controller.selectDraft(
        controller.servers.singleWhere((row) => row.id == 1),
      );
      expect(controller.selectedId, 2);
      expect(
        controller.exitRowDetail(
          l,
          controller.servers.singleWhere((row) => row.id == 1),
        ),
        l.prototypeEntryServer,
      );
      controller.selectDraft(
        controller.servers.singleWhere((row) => row.id == 4),
      );
      expect(controller.selectedId, 2);
      expect(
        controller.exitRowDetail(
          l,
          controller.servers.singleWhere((row) => row.id == 4),
        ),
        l.prototypeTemporarilyUnavailable,
      );
      controller.selectDraft(
        controller.servers.singleWhere((row) => row.id == 3),
      );
      expect(controller.selectedId, 3);
      controller.search.text = 'Server 3';
      expect(controller.search.text, 'Server 3');
      expect(controller.selectionGroups(l).single.visibleRows.single.id, 3);
      expect(
        controller.exitRowDetail(
          l,
          controller.servers.singleWhere((row) => row.id == 3),
        ),
        l.prototypeFastLatency(20),
      );
      expect((await coordinator.configuration).encode(), before);
    },
  );

  Future<void> open(
    WidgetTester tester,
    List<ServerExitChoice?> results, {
    double width = 427,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.material(
          Brightness.light,
          mobile: width <= AppLayout.mobileBreakpoint,
        ),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                results.add(
                  await Navigator.of(context).push<ServerExitChoice>(
                    MaterialPageRoute(
                      builder: (_) =>
                          ServerExitPickerView(controller: controller),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('flat selection changes only the draft until Done', (
    tester,
  ) async {
    final before = (await coordinator.configuration).encode();
    final results = <ServerExitChoice?>[];
    await open(tester, results);
    expect(find.text(l.prototypeVpnFinalExit), findsOneWidget);
    expect(find.text(l.prototypeAddServers), findsNothing);
    expect(find.text(l.prototypeManageSources), findsNothing);
    expect(find.text(l.prototypeFavorites), findsNothing);
    expect(find.text('VLESS | XHTTP | TLS'), findsNWidgets(4));
    expect(find.text('outbound'), findsNWidgets(4));
    expect(find.text(l.countryRegionName('SG')), findsNothing);
    await tester.tap(find.text('Server 3'));
    await tester.pumpAndSettle();
    expect(controller.selectedId, 3);
    expect(results, isEmpty);
    expect(find.byType(ServerExitPickerView), findsOneWidget);
    expect((await coordinator.configuration).encode(), before);
    await tester.tap(find.text(l.prototypeDone));
    await tester.pumpAndSettle();
    expect(results.single?.id, 3);
    expect(find.byType(ServerExitPickerView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop selector keeps a 760 card and a matching footer scope', (
    tester,
  ) async {
    await open(tester, <ServerExitChoice?>[], width: 1160);
    final card = find.byType(RoutingCard);
    expect(tester.getSize(card).width, AppLayout.routingEditorMaxWidth);
    expect(tester.getCenter(card).dx, 580);
    expect(
      tester.getTopLeft(card).dy,
      kToolbarHeight + AppSpacing.desktopPageTop,
    );
    expect(
      tester.widget<PageActionBar>(find.byType(PageActionBar)).maxWidth,
      AppLayout.routingEditorMaxWidth,
    );
    expect(find.byType(TabBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back cancels; Done can explicitly return no additional exit', (
    tester,
  ) async {
    final results = <ServerExitChoice?>[];
    await open(tester, results);
    await tester.tap(find.text(l.prototypeNoAdditionalExit));
    await tester.pumpAndSettle();
    expect(controller.selectedId, isNull);
    expect(results, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(results, [null]);

    controller.selectDraft(
      controller.servers.singleWhere((row) => row.id == 2),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.prototypeNoAdditionalExit));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.prototypeDone));
    await tester.pumpAndSettle();
    expect(results.last, isA<ServerExitChoice>());
    expect(results.last!.id, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'provider profiles stay outside the picker and explicit IDs cannot be selected',
    (tester) async {
      late CoreConfigData profile;
      await tester.runAsync(() async {
        final sourceId = await db.subscriptionDao.insertRow(
          SubscriptionCompanion.insert(
            name: 'Provider',
            url: 'https://example.test/provider',
            mode: const Value('providerManaged'),
            timestamp: DateTime(2026),
          ),
        );
        final profileId = await db.coreConfigDao.insertAssetRow(
          CoreConfigCompanion.insert(
            name: 'Complete profile',
            type: 'Remnawave',
            tags: '',
            subId: sourceId,
            delay: PingDelayConstants.unknown,
            data: Value(
              base64Encode(
                utf8.encode('{"outbounds":[{"protocol":"freedom"}]}'),
              ),
            ),
          ),
        );
        if (!controller.state.catalog.servers.any(
          (row) => row.id == profileId,
        )) {
          await controller.stream
              .firstWhere(
                (state) =>
                    state.catalog.servers.any((row) => row.id == profileId),
              )
              .timeout(const Duration(seconds: 5));
        }
        profile = (await db.coreConfigDao.searchRow(profileId))!;
      });
      final profileId = profile.id;
      expect(controller.catalog.selectable(profile), isTrue);
      expect(controller.canSelect(profile), isFalse);
      controller.selectDraft(profile);
      expect(controller.selectedId, 2);
      expect(
        controller
            .selectionGroups(l)
            .expand((group) => group.rows)
            .map((row) => row.id),
        isNot(contains(profileId)),
      );
      await open(tester, <ServerExitChoice?>[]);
      expect(find.text('Complete profile'), findsNothing);
      expect(find.text('Provider'), findsNothing);
      final explicit = ServerExitPickerController(
        ServerExitPickerParams(selectedId: profileId),
        database: db,
        coordinator: coordinator,
      );
      addTearDown(explicit.close);
      await tester.runAsync(() async {
        await explicit.initialize();
        if (!explicit.state.catalog.servers.any((row) => row.id == profileId)) {
          await explicit.stream
              .firstWhere(
                (state) =>
                    state.catalog.servers.any((row) => row.id == profileId),
              )
              .timeout(const Duration(seconds: 5));
        }
      });
      expect(explicit.canFinish, isFalse);
      explicit.selectDraft(null);
      expect(explicit.canFinish, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
