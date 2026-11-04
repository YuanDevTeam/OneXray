import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/details.dart';
import 'package:onexray/pages/servers/sources.dart';
import 'package:onexray/pages/servers/subscription/user_info.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;

import 'fixtures/server_test_router.dart';

final _source = SubscriptionData(
  panel: 'generic',
  mode: 'appManaged',
  id: 7,
  name: 'Example subscription',
  hwidEnabled: false,
  url: 'https://example.test/subscription',
  timestamp: DateTime(2026, 9, 1, 9, 42),
);

CoreConfigData _server(int id, {int source = 0}) => CoreConfigData(
  id: id,
  name: 'Server $id',
  type: 'outbound',
  tags: '',
  delay: 20,
  subId: source,
  manualSortOrder: 0,
  favorite: false,
);

class _Controller extends ServersController {
  _Controller({required super.database, required super.coordinator});
  final actions = <SourceAction>[];

  @override
  Future<void> sourceAction(
    BuildContext context,
    SubscriptionData source,
    SourceAction action,
  ) async {
    expect(context.mounted, isTrue);
    expect(source.id, _source.id);
    actions.add(action);
  }
}

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late _Controller controller;
  late ScrollController scroll;
  GoRouter? router;

  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(database: db);
    controller = _Controller(database: db, coordinator: coordinator);
    scroll = ScrollController();
  });

  tearDown(() async {
    router?.dispose();
    router = null;
    scroll.dispose();
    await controller.close();
    coordinator.dispose();
    await db.close();
  });

  Future<AppLocalizations> pumpSources(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(427, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    router = serverTestRouter(
      home: (_) => Scaffold(
        body: BlocBuilder<ServersController, ServersPageState>(
          bloc: controller,
          builder: (_, _) =>
              ServerBrowser(controller: controller, scroll: scroll),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light,
        locale: const Locale('en'),
        routerConfig: router,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) => ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: ShadToaster(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(ServerBrowser)))!;
    await tester.ensureVisible(find.text(l.prototypeSubscriptions).first);
    await tester.tap(find.text(l.prototypeSubscriptions).first);
    await tester.pumpAndSettle();
    expect(find.byType(ServerSourcesView), findsOneWidget);
    return l;
  }

  testWidgets(
    'subscription destination does not represent personal nodes as a source',
    (tester) async {
      controller.servers = List.generate(4, (index) => _server(index + 1));
      final l = await pumpSources(tester);
      expect(find.text(l.prototypeManualAdditions), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, l.prototypeAddSubscription),
        findsOneWidget,
      );
      expect(controller.actions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'subscription cards update package information from their source stream',
    (tester) async {
      controller.sources = [_source];
      controller.servers = [_server(1, source: 7)];
      final l = await pumpSources(tester);
      expect(find.byType(SubscriptionPackageSummary), findsNothing);
      controller.sources = [
        _source.copyWith(
          totalBytes: const Value(0),
          expireTimestamp: const Value(0),
          userInfoUpdatedAt: Value(DateTime(2026, 9, 2)),
        ),
      ];
      await tester.pumpAndSettle();
      expect(find.byType(SubscriptionPackageSummary), findsOneWidget);
      expect(
        find.text(
          '${l.subscriptionPackageUnlimited} · ${l.subscriptionPackageNoExpiry}',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(_source.name));
      await tester.pumpAndSettle();
      expect(find.byType(ServerSourcePage), findsOneWidget);
      expect(find.byType(SubscriptionPackageDetails), findsOneWidget);
      expect(find.text(_source.url), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source search matches URL and can be cleared without changing the connection',
    (tester) async {
      controller.sources = [_source];
      final l = await pumpSources(tester);
      final before = controller.configuration.encode();
      await tester.enterText(find.byType(TextField).first, 'example.test');
      await tester.pumpAndSettle();
      expect(find.text(_source.name), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'not-present');
      await tester.pumpAndSettle();
      expect(find.text(l.prototypeNoMatchingSubscriptions), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('server-search-clear')));
      await tester.pumpAndSettle();
      expect(find.text(_source.name), findsOneWidget);
      expect(controller.configuration.encode(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'production source detail retains failures and dispatches its actions once',
    (tester) async {
      controller.sources = [_source];
      controller.servers = [_server(1, source: 7)];
      controller.setSourceError(7, 'Stored update failure');
      final l = await pumpSources(tester);
      expect(find.text('Stored update failure'), findsOneWidget);
      await tester.tap(find.text(_source.name));
      await tester.pumpAndSettle();
      expect(find.byType(ServerSourcePage), findsOneWidget);
      expect(find.text('Stored update failure'), findsOneWidget);
      for (final (action, label) in [
        (SourceAction.update, l.prototypeCheckForUpdates),
        (SourceAction.edit, l.prototypeEditSubscription),
        (SourceAction.share, l.prototypeShareSubscription),
        (SourceAction.delete, l.prototypeDeleteSource),
      ]) {
        final target = find.text(label);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(controller.actions.last, action);
      }
      expect(controller.actions, SourceAction.values);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zero-node update result explains that existing nodes were kept',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SourceUpdateErrorDialog(sourceName: 'Example subscription'),
          ),
        ),
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(SourceUpdateErrorDialog)),
      )!;
      expect(find.text(l.prototypeSubscriptionUpdateFailed), findsOneWidget);
      expect(find.text('Example subscription'), findsOneWidget);
      expect(
        find.text(l.prototypeSubscriptionExistingNodesKept),
        findsOneWidget,
      );
      expect(find.text(l.prototypeDone), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
