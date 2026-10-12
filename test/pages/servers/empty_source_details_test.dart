import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/page.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;

class _Controller extends ServersController {
  _Controller({required super.database, required super.coordinator});

  final actions = <({int id, String mode, SourceAction action})>[];

  @override
  Future<void> sourceAction(
    BuildContext context,
    SubscriptionData source,
    SourceAction action,
  ) async {
    expect(context.mounted, isTrue);
    actions.add((id: source.id, mode: source.mode, action: action));
  }
}

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late _Controller controller;
  late int sourceId;
  late int profileId;

  setUp(() async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sourceId = await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'Provider source',
        url: 'https://example.test/provider',
        mode: Value(SubscriptionMode.providerManaged.name),
        timestamp: DateTime(2026, 10, 12),
      ),
    );
    profileId = await db.coreConfigDao.insertAssetRow(
      CoreConfigCompanion.insert(
        name: 'Complete profile',
        type: CoreConfigType.Remnawave.name,
        tags: '',
        subId: sourceId,
        delay: PingDelayConstants.unknown,
        data: Value(
          base64Encode(
            utf8.encode(
              '{"outbounds":[{"tag":"provider-direct","protocol":"freedom"}]}',
            ),
          ),
        ),
      ),
    );
    coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => null,
      inspect: (_, {observedStatus}) async =>
          const HostConnection(VpnStatus.disconnected),
    );
    controller = _Controller(database: db, coordinator: coordinator);
    await controller.initialize();
    if (controller.servers.isEmpty) {
      await controller.stream
          .firstWhere((state) => state.servers.isNotEmpty)
          .timeout(const Duration(seconds: 5));
    }
  });

  tearDown(() async {
    await controller.close();
    coordinator.dispose();
    await db.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) => ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: ShadToaster(child: child!),
        ),
        home: ServerGroupPage(
          params: ServerGroupParams(controller, 'subscription:$sourceId'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PageAppBar),
        matching: find.text('Provider source'),
      ),
      findsOneWidget,
    );
    expect(find.text('Complete profile'), findsOneWidget);
  }

  Future<void> clearActiveCache(WidgetTester tester) async {
    await tester.runAsync(() async {
      final source = (await db.subscriptionDao.searchRow(sourceId))!;
      await db.subscriptionDao.updateRow(
        source.copyWith(mode: SubscriptionMode.appManaged.name),
      );
      if (controller.sources.single.mode != SubscriptionMode.appManaged.name ||
          controller.servers.isNotEmpty) {
        await controller.stream
            .firstWhere(
              (state) =>
                  state.sources.single.mode ==
                      SubscriptionMode.appManaged.name &&
                  state.servers.isEmpty,
            )
            .timeout(const Duration(seconds: 5));
      }
    });
  }

  testWidgets(
    'switching to a mode without cache retains source title and update/edit actions',
    (tester) async {
      await open(tester);
      await clearActiveCache(tester);
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerGroupPage)),
      )!;
      expect(controller.groups(l), isEmpty);
      expect(
        find.descendant(
          of: find.byType(PageAppBar),
          matching: find.text('Provider source'),
        ),
        findsOneWidget,
      );
      expect(find.text('Complete profile'), findsNothing);
      expect(find.text(l.subscriptionModeAppManaged), findsOneWidget);
      expect(find.text(l.subscriptionModeNoCacheTitle), findsOneWidget);
      expect(find.text(l.subscriptionModeNeedsRefresh), findsOneWidget);
      expect(find.byType(SourceMenu), findsOneWidget);
      for (final (action, label) in [
        (SourceAction.update, l.prototypeCheckForUpdates),
        (SourceAction.edit, l.prototypeEditSubscription),
      ]) {
        await tester.runAsync(() => tester.tap(find.byType(SourceMenu)));
        await tester.pumpAndSettle();
        expect(find.text(l.prototypeCheckForUpdates), findsOneWidget);
        expect(find.text(l.prototypeEditSubscription), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text(label));
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(controller.actions.last, (
          id: sourceId,
          mode: SubscriptionMode.appManaged.name,
          action: action,
        ));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deleting a source removes its retained empty detail and source actions',
    (tester) async {
      await open(tester);
      await clearActiveCache(tester);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(PageAppBar),
          matching: find.text('Provider source'),
        ),
        findsOneWidget,
      );
      expect(find.byType(SourceMenu), findsOneWidget);
      await tester.runAsync(() async {
        await db.subscriptionDao.deleteRow(sourceId);
        if (controller.sources.isNotEmpty || controller.servers.isNotEmpty) {
          await controller.stream
              .firstWhere(
                (state) => state.sources.isEmpty && state.servers.isEmpty,
              )
              .timeout(const Duration(seconds: 5));
        }
        expect(await db.coreConfigDao.searchRow(profileId), isNull);
      });
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerGroupPage)),
      )!;
      expect(find.text('Provider source'), findsNothing);
      expect(find.text(l.prototypeServers), findsOneWidget);
      expect(find.text(l.prototypeNoServersYet), findsOneWidget);
      expect(find.text(l.subscriptionModeNoCacheTitle), findsNothing);
      expect(find.byType(SourceMenu), findsNothing);
      expect(controller.actions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
