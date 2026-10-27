import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/config/controller.dart';
import 'package:onexray/pages/advanced/xray/config/page.dart';
import 'package:onexray/pages/advanced/xray/config/params.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/editor/page.dart';
import 'package:onexray/pages/servers/page.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/shared/share/params.dart';
import 'package:onexray/pages/shared/widgets/json_editor.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Assets extends ServerAssetService {
  _Assets({required super.database, required super.coordinator});
  final loaded = <int>[];
  final completeRead = Completer<void>();
  final copies = <({int id, String? name})>[];
  int validations = 0;
  Future<void> Function(int)? afterValidation;

  @override
  Future<void> validateSelection(ServerSelection selection) async {
    validations++;
    await super.validateSelection(selection);
    await afterValidation?.call(validations);
  }

  @override
  Future<ServerEditDraft> loadComplete(int id) async {
    loaded.add(id);
    final draft = await super.loadComplete(id);
    completeRead.complete();
    return draft;
  }

  @override
  Future<int> copyAsRaw(int id, {String? name}) async {
    copies.add((id: id, name: name));
    return 501;
  }
}

class _Controller extends ServersController {
  _Controller({
    required super.database,
    required super.coordinator,
    required super.assets,
    required super.ping,
  });

  final selectionComplete = Completer<void>();

  @override
  Future<void> choose(BuildContext context, ServerSelection selection) async {
    try {
      await super.choose(context, selection);
    } finally {
      selectionComplete.complete();
    }
  }
}

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late _Controller controller;
  late _Assets assets;
  late ScrollController scroll;
  late List<CoreConfigData> profiles;
  late String originalText;
  GoRouter? router;
  SharePageParams? shared;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => null,
      inspect: (_, {observedStatus}) async =>
          const HostConnection(VpnStatus.disconnected),
      prepare: (_, _) async =>
          throw StateError('Browsing must not prepare VPN'),
      start: (_) async => throw StateError('Browsing must not start VPN'),
      stop: () async => throw StateError('Browsing must not stop VPN'),
    );
    await coordinator.initialize(observe: false, registerReferences: false);
    final sourceId = await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'Provider',
        url: 'https://example.test/provider',
        mode: Value(SubscriptionMode.providerManaged.name),
        timestamp: DateTime(2026, 10, 12),
      ),
    );
    originalText = '{"remarks":"Payload name stays intact","outbounds":[{"protocol":"freedom","tag":"provider-direct"}],"routing":{"domainStrategy":"IPIfNonMatch","rules":[]}}';
    profiles = [];
    for (final (index, name) in ['Profile A', 'Profile B'].indexed) {
      final id = await db.coreConfigDao.insertAssetRow(
        CoreConfigCompanion.insert(
          name: name,
          type: CoreConfigType.Remnawave.name,
          tags: '',
          data: Value(base64Encode(utf8.encode(originalText))),
          delay: index == 0
              ? PingDelayConstants.error
              : PingDelayConstants.timeout,
          subId: sourceId,
        ),
      );
      profiles.add((await db.coreConfigDao.searchRow(id))!);
    }
    assets = _Assets(database: db, coordinator: coordinator);
    controller =
        _Controller(
            database: db,
            coordinator: coordinator,
            assets: assets,
            ping: PingService.forTesting(
              database: db,
              runBatch: (_, _) async => throw StateError(
                'Complete configurations must not be pinged',
              ),
            ),
          )
          ..sources = [(await db.subscriptionDao.searchRow(sourceId))!]
          ..servers = profiles
          ..ready = true;
    scroll = ScrollController();
    shared = null;
  });

  tearDown(() async {
    router?.dispose();
    router = null;
    scroll.dispose();
    await controller.close();
    coordinator.dispose();
    await db.close();
  });

  Future<void> open(WidgetTester tester, {bool browse = true}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    router = GoRouter(
      initialLocation: '/servers',
      routes: [
        GoRoute(
          path: '/servers',
          builder: (_, _) => Scaffold(
            body: BlocBuilder<ServersController, ServersPageState>(
              bloc: controller,
              builder: (_, _) =>
                  ServerBrowser(controller: controller, scroll: scroll),
            ),
          ),
          routes: [
            GoRoute(
              path: 'server-group',
              builder: (_, state) =>
                  ServerGroupPage(params: state.extra! as ServerGroupParams),
            ),
            GoRoute(
              path: 'config-file-viewer',
              builder: (_, state) => ConfigFileViewerPage(
                params: state.extra! as ConfigFileViewerParams,
              ),
            ),
            GoRoute(
              path: 'share',
              builder: (_, state) {
                shared = state.extra! as SharePageParams;
                return const Scaffold(body: Text('Share route'));
              },
            ),
          ],
        ),
      ],
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
    if (browse) {
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerBrowser)),
      )!;
      await tester.tap(find.byTooltip(l.providerChooseConfiguration));
      await tester.pumpAndSettle();
    }
  }

  Future<ConnectionConfiguration> configuration(WidgetTester tester) async =>
      (await tester.runAsync(() => coordinator.configuration))!;

  Future<CoreConfigData> savedRow(WidgetTester tester, int id) async =>
      (await tester.runAsync(() => db.coreConfigDao.searchRow(id)))!;

  testWidgets(
    'provider group browses and a user explicitly selects an unmeasured row',
    (tester) async {
      final before = (await configuration(tester)).encode();
      await open(tester);
      final context = tester.element(find.byType(ServerGroupView));
      final l = AppLocalizations.of(context)!;
      expect((await configuration(tester)).encode(), before);
      expect(find.text('Remnawave'), findsNWidgets(2));
      expect(find.text(l.prototypeTestServers), findsNothing);
      expect(find.text(l.prototypeNotTested), findsNothing);
      expect(find.text(l.prototypeTemporarilyUnavailable), findsNothing);
      expect(find.byType(ServerUseButton), findsNothing);
      await controller.test(context, profiles);
      expect(AppEventBus.instance.state.pinging, isFalse);
      expect(controller.state.serverTests, isEmpty);
      await tester.runAsync(() async {
        await tester.tap(find.text('Profile B'));
        await controller.selectionComplete.future.timeout(
          const Duration(seconds: 5),
        );
      });
      await tester.pumpAndSettle();
      final selected = (await configuration(tester)).connection.selection;
      expect(selected.kind, SelectionKind.server);
      expect(selected.id, profiles[1].id);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'complete edit action views the original JSON without an outbound editor',
    (tester) async {
      await open(tester);
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerGroupView)),
      )!;
      await tester.runAsync(() => tester.tap(find.byType(ServerMenu).first));
      await tester.pumpAndSettle();
      expect(find.text(l.prototypeEditServer), findsNothing);
      expect(find.text(l.prototypeTestAgain), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.text(l.providerViewConfiguration));
        await assets.completeRead.future.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.byType(ConfigFileViewerPage), findsOneWidget);
      expect(find.byType(ServerEditorPage), findsNothing);
      expect(find.byType(AppJsonEditor), findsNothing);
      final state = tester
          .element(find.byType(ConfigFileViewerView))
          .read<ConfigFileViewerController>()
          .state;
      expect(state.title, 'Profile A');
      expect(state.text, originalText);
      expect(assets.loaded, [profiles.first.id]);
      expect(
        (await savedRow(tester, profiles.first.id)).data,
        profiles.first.data,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'personal Raw copy asks for a valid name and does not select or alter its source',
    (tester) async {
      final long = profiles.first.copyWith(
        name: 'A provider metadata name longer than thirty two characters',
      );
      await tester.runAsync(() => db.coreConfigDao.updateRow(long));
      profiles[0] = long;
      controller.servers = profiles;
      final before = (await configuration(tester)).encode();
      await open(tester);
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerGroupView)),
      )!;
      await tester.tap(find.byType(ServerMenu).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.providerCopyAsRaw));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, l.providerCopyAsRaw);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('provider-raw-copy-name')),
        'Personal QA',
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(assets.copies, [(id: long.id, name: 'Personal QA')]);
      expect((await configuration(tester)).encode(), before);
      expect((await savedRow(tester, long.id)).name, long.name);
      expect((await savedRow(tester, long.id)).data, long.data);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source existence is checked again before a stale group selection commits',
    (tester) async {
      final provider = controller.sources.single;
      final ordinarySource = provider.copyWith(
        mode: SubscriptionMode.appManaged.name,
      );
      await tester.runAsync(() async {
        await db.subscriptionDao.updateRow(ordinarySource);
        final id = await db.coreConfigDao.insertAssetRow(
          outboundCompanion({'tag': 'Cached node', 'protocol': 'freedom'})
              .copyWith(subId: Value(provider.id)),
        );
        controller.sources = [ordinarySource];
        controller.servers = [(await db.coreConfigDao.searchRow(id))!];
      });
      assets.afterValidation = (attempt) async {
        if (attempt == 1) {
          await db.subscriptionDao.deleteRow(provider.id);
        }
      };
      final before = (await configuration(tester)).encode();
      await open(tester, browse: false);
      final context = tester.element(find.byType(ServerBrowser));
      await tester.runAsync(
        () => controller.choose(context, ServerSelection.source(provider.id)),
      );
      await tester.pumpAndSettle();
      expect(assets.validations, 2);
      expect(
        (await tester.runAsync(
          () => db.subscriptionDao.searchRow(provider.id),
        )),
        isNull,
      );
      expect((await configuration(tester)).encode(), before);
      expect(controller.selecting, isNull);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('provider share uses the complete configuration identity', (
    tester,
  ) async {
    await open(tester);
    final l = AppLocalizations.of(
      tester.element(find.byType(ServerGroupView)),
    )!;
    await tester.tap(find.byType(ServerMenu).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.prototypeShare));
    await tester.pumpAndSettle();
    expect(shared!.type, ShareType.config);
    expect(shared!.id, profiles.first.id);
    expect(find.text('Share route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
