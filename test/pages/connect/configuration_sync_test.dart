import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/pigeon/messages.g.dart' show VpnStatus;
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/controller.dart';
import 'package:onexray/pages/connect/view.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Fixture {
  _Fixture(this.db, this.coordinator, this.connect, this.servers, this.started);

  final AppDatabase db;
  final ConnectionCoordinator coordinator;
  final ConnectController connect;
  final ServersController servers;
  final List<ConnectionRuntime> started;

  static Future<_Fixture> create({required bool expert}) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bus = AppEventBus();
    addTearDown(bus.close);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final sourceId = await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'Provider source',
        url: 'https://example.test/provider',
        mode: Value(SubscriptionMode.providerManaged.name),
        timestamp: DateTime(2026, 10, 12),
      ),
    );
    await db.coreConfigDao.insertAssetRow(
      CoreConfigCompanion.insert(
        id: const Value(63),
        name: 'Personal Raw',
        type: CoreConfigType.raw.name,
        tags: '',
        data: Value(
          base64Encode(
            utf8.encode(
              '{"outbounds":[{"tag":"raw-direct","protocol":"freedom"}]}',
            ),
          ),
        ),
        delay: PingDelayConstants.unknown,
        subId: 0,
      ),
    );
    await db.coreConfigDao.insertAssetRow(
      CoreConfigCompanion.insert(
        id: const Value(65),
        name: 'Provider profile',
        type: CoreConfigType.Remnawave.name,
        tags: '',
        data: Value(
          base64Encode(
            utf8.encode(
              '{"outbounds":[{"tag":"provider-direct","protocol":"freedom"}]}',
            ),
          ),
        ),
        delay: PingDelayConstants.unknown,
        subId: sourceId,
      ),
    );
    final initial = ConnectionConfiguration(
      connection: ConnectionSettings(expert: expert, rawId: 63),
    );
    await db.connectionConfigDao.commit(configurationJson: initial.encode());
    ConnectionRuntime? active;
    final started = <ConnectionRuntime>[];
    final coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => active,
      inspect: (_, {observedStatus}) async => active == null
          ? const HostConnection(VpnStatus.disconnected)
          : HostConnection(VpnStatus.connected, runtime: active),
      prepare: (configuration, _) async {
        expect(configuration.connection.expert, isFalse);
        expect(configuration.connection.selection.id, 65);
        final row = (await db.coreConfigDao.searchActiveServerRow(65))!;
        final compiled = CompiledConnection(
          xrayJson: '{}',
          entries: const [],
          finalExit: null,
          nodeTags: const {},
          profile: ResolvedProfile.fromRow(row),
        );
        return ConnectionRuntime.create(
          configuration: configuration,
          compiled: compiled,
          platform: ConnectionPlatform.android,
          request: StartVpnRequest(
            configuration.policy.toTun(ConnectionPlatform.android),
            null,
            '18003',
            jsonEncode(
              LibXrayInvokeRequest(
                method: LibXrayMethod.runXray,
                payload: RunXrayRequest(compiled.xrayJson).toJson(),
              ).toJson(),
            ),
          ),
        );
      },
      start: (runtime) async {
        started.add(runtime);
        active = runtime;
        return HostConnection(VpnStatus.connected, runtime: runtime);
      },
      stop: () async {
        active = null;
        return const HostConnection(VpnStatus.disconnected);
      },
    );
    await coordinator.initialize(observe: false, registerReferences: false);
    final connect = ConnectController(database: db, coordinator: coordinator);
    final servers = ServersController(database: db, coordinator: coordinator)
      ..sources = await db.subscriptionDao.allRows
      ..servers = await db.coreConfigDao.allActiveServerRows()
      ..ready = true;
    await connect.initialize();
    // Let the initial persisted configuration stream arrive before opening a
    // local Raw browsing draft in the widget's zone.
    await db.connectionConfigDao.watch().first;
    if (!connect.servers.any((row) => row.id == 65) || connect.raws.isEmpty) {
      await connect.stream
          .firstWhere(
            (state) =>
                state.servers.any((row) => row.id == 65) &&
                state.raws.isNotEmpty,
          )
          .timeout(const Duration(seconds: 5));
    }
    return _Fixture(db, coordinator, connect, servers, started);
  }

  Future<void> close() async {
    await servers.close();
    await connect.close();
    coordinator.dispose();
    await db.close();
  }
}

Widget _screen(ConnectController controller) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  builder: (_, child) => ShadTheme(
    data: AppTheme.shad(Brightness.light),
    child: ShadToaster(child: child!),
  ),
  home: Scaffold(
    body: BlocBuilder<ConnectController, ConnectPageState>(
      bloc: controller,
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        return ConnectView(
          view: state.connectionView,
          hasServers: state.servers.isNotEmpty,
          expert: state.expertView,
          raws: state.raws,
          activeRawId: state.configuration.connection.expert
              ? state.configuration.connection.rawId
              : null,
          pendingChange: state.pendingChange,
          location: controller.selectionTitle(l),
          locationDetail: controller.selectionDetail(l),
          method: controller.homeMethodTitle(l),
          methodDetail: controller.methodDescription(l),
          methodEnabled: !controller.providerConfiguration,
          onConnection: () => controller.connectionAction(context),
          onExpert: (value) => controller.toggleExpert(context, value),
          onAddServers: () {},
          onServer: () {},
          onMethod: () {},
          onWhy: () {},
          onRawAdd: () {},
          onRawSelect: (_) {},
          onRawActions: (_) {},
        );
      },
    ),
  ),
);

void main() {
  for (final initiallyExpert in [true, false]) {
    testWidgets(
      'external provider selection leaves the Raw view and starts the chosen profile (persisted expert: $initiallyExpert)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        late _Fixture fixture;
        await tester.runAsync(() async {
          fixture = await _Fixture.create(expert: initiallyExpert);
        });
        addTearDown(() => tester.runAsync(fixture.close));
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        await tester.pumpWidget(_screen(fixture.connect));
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(ConnectView));
        final l = AppLocalizations.of(context)!;
        if (!initiallyExpert) {
          await tester.runAsync(() async {
            final opened = fixture.connect.stream.firstWhere(
              (state) => state.expertView,
            );
            await fixture.connect.toggleExpert(context, true);
            await opened.timeout(const Duration(seconds: 5));
          });
        }
        await tester.pumpAndSettle();
        expect(fixture.connect.expertView, isTrue);
        expect(
          tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value,
          isTrue,
        );
        await tester.runAsync(() async {
          await fixture.servers.choose(
            context,
            const ServerSelection.server(65),
          );
          if (fixture.connect.configuration.connection.selection.id != 65 ||
              fixture.connect.configuration.connection.expert) {
            await fixture.connect.stream
                .firstWhere(
                  (state) =>
                      state.configuration.connection.selection.id == 65 &&
                      !state.configuration.connection.expert,
                )
                .timeout(const Duration(seconds: 5));
          }
          final saved = await fixture.coordinator.configuration;
          expect(
            (
              saved.connection.expert,
              saved.connection.rawId,
              saved.connection.selection.id,
            ),
            (false, 63, 65),
          );
        });
        await tester.pumpAndSettle();
        expect(fixture.connect.expertView, isFalse);
        expect(
          tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value,
          isFalse,
        );
        expect(find.text('Provider profile'), findsOneWidget);
        await tester.runAsync(() async {
          final connected = fixture.connect.stream.firstWhere(
            (state) => state.connectionView.phase == ConnectionPhase.connected,
          );
          await tester.tap(
            find.widgetWithText(FilledButton, l.prototypeConnect),
          );
          await connected.timeout(const Duration(seconds: 5));
        });
        // The connected status has a persistent animation; render its transition
        // without waiting for an idle frame that a live connection never has.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(fixture.started.single.profile?.id, 65);
        expect(fixture.started.single.configuration.connection.expert, isFalse);
        expect(fixture.started.single.configuration.connection.rawId, 63);
        expect(find.text(l.prototypeChooseRawConfiguration), findsNothing);
        expect(
          fixture.coordinator.state.value.phase,
          ConnectionPhase.connected,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'unrelated persisted settings keep the uncommitted Raw browsing draft',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late _Fixture fixture;
      await tester.runAsync(() async {
        fixture = await _Fixture.create(expert: false);
      });
      addTearDown(() => tester.runAsync(fixture.close));
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(_screen(fixture.connect));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(ConnectView));
      await tester.runAsync(() async {
        final opened = fixture.connect.stream.firstWhere(
          (state) => state.expertView,
        );
        await fixture.connect.toggleExpert(context, true);
        await opened.timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final before = await fixture.coordinator.configuration;
        expect(before.connection.expert, isFalse);
        final next = ConnectionConfiguration.fromJson({
          ...before.toJson(),
          'policy': {...before.policy.toJson(), 'ipv6Enabled': false},
          'connection': {
            ...before.connection.toJson(),
            'smart': {...before.connection.smart.toJson(), 'blockAds': true},
          },
        });
        await fixture.coordinator.apply(next);
        if (fixture.connect.configuration.policy.ipv6Enabled ||
            !fixture.connect.configuration.connection.smart.blockAds) {
          await fixture.connect.stream
              .firstWhere(
                (state) =>
                    !state.configuration.policy.ipv6Enabled &&
                    state.configuration.connection.smart.blockAds,
              )
              .timeout(const Duration(seconds: 5));
        }
        final saved = await fixture.coordinator.configuration;
        expect(saved.connection.expert, isFalse);
        expect(saved.connection.rawId, 63);
        expect(saved.connection.selection.kind, SelectionKind.automatic);
      });
      await tester.pumpAndSettle();
      expect(fixture.connect.expertView, isTrue);
      expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isTrue);
      expect(fixture.started, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
