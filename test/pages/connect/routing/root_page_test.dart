import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/controller.dart';
import 'package:onexray/pages/connect/routing/page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/state_db.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadButton, ShadTheme, ShadToaster;

const _waitTimeout = Duration(seconds: 5);

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  RoutingPageController? controller;
  late int goodId, brokenId;
  late RoutingProfileData originalGood;

  setUp(() async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    goodId = await db.routingProfileDao.insertRow(
      RoutingProfileState(name: 'Good route').insertCompanion,
    );
    brokenId = await db.routingProfileDao.insertRow(
      RoutingProfileCompanion.insert(
        name: 'Broken route',
        data: 'invalid-base64!',
        advanced: const Value(true),
      ),
    );
    originalGood = (await db.routingProfileDao.searchRow(goodId))!;
    await db.connectionConfigDao.commit(
      configurationJson: ConnectionConfiguration(
        connection: ConnectionSettings(trafficMode: TrafficMode.allVpn),
      ).encode(),
    );
    coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => null,
      inspect: (_, {observedStatus}) async =>
          const HostConnection(VpnStatus.disconnected),
      prepare: (_, _) async =>
          throw StateError('Changing a stored preference must not prepare VPN'),
      start: (_) async =>
          throw StateError('Changing a stored preference must not start VPN'),
      stop: () async =>
          throw StateError('Changing a stored preference must not stop VPN'),
    );
    await coordinator
        .initialize(observe: false, registerReferences: false)
        .timeout(_waitTimeout);
  });

  tearDown(() async {
    await controller?.close().timeout(_waitTimeout);
    controller = null;
    coordinator.dispose();
    await db.close().timeout(_waitTimeout);
  });

  Future<void> waitFor(bool Function(RoutingPageState state) predicate) async {
    if (!predicate(controller!.state)) {
      await controller!.stream.firstWhere(predicate).timeout(_waitTimeout);
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
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
        home: RoutingPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle().timeout(_waitTimeout);
  }

  bool useEnabled(WidgetTester tester, String key) {
    final widget = tester.widget(find.byKey(ValueKey(key)));
    // Selected routes have a status badge instead of a disabled action.
    return widget is ShadButton && widget.enabled;
  }

  testWidgets(
    'broken and readable routes coexist while Smart and All remain usable',
    (tester) async {
      await tester.runAsync(() async {
        controller = RoutingPageController(
          database: db,
          coordinator: coordinator,
        );
        await controller!.load().timeout(_waitTimeout);
      });
      await pumpPage(tester);
      final state = controller!.state;
      expect(state.failed, isFalse);
      expect(state.profiles.map((row) => row.id), [goodId, brokenId]);
      expect(state.profileErrors.keys, [brokenId]);
      expect(controller!.configurationFor(originalGood), isNotNull);
      expect(find.text('Good route'), findsOneWidget);
      expect(find.text('Broken route'), findsOneWidget);
      expect(useEnabled(tester, 'routing-use-profile-$brokenId'), isFalse);
      expect(useEnabled(tester, 'routing-use-profile-$goodId'), isTrue);
      expect(useEnabled(tester, 'routing-use-smart'), isTrue);
      final l = AppLocalizations.of(tester.element(find.byType(RoutingPage)))!;
      final broken = find.byKey(ValueKey('routing-profile-$brokenId'));
      expect(
        find.descendant(
          of: broken,
          matching: find.text(l.prototypeTemporarilyUnavailable),
        ),
        findsOneWidget,
      );
      for (final label in [l.prototypeEdit, l.prototypeDelete]) {
        final action = find.descendant(
          of: broken,
          matching: find.widgetWithText(ShadButton, label),
        );
        expect(action, findsOneWidget);
        expect(tester.widget<ShadButton>(action).enabled, isTrue);
      }
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('routing-use-smart')));
        await waitFor(
          (s) =>
              !s.busy &&
              s.configuration?.connection.trafficMode == TrafficMode.smart,
        );
      });
      await tester.pumpAndSettle().timeout(_waitTimeout);
      expect(
        (await tester.runAsync(
          () => coordinator.configuration.timeout(_waitTimeout),
        ))!.connection.trafficMode,
        TrafficMode.smart,
      );
      expect(useEnabled(tester, 'routing-use-all'), isTrue);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('routing-use-all')));
        await waitFor(
          (s) =>
              !s.busy &&
              s.configuration?.connection.trafficMode == TrafficMode.allVpn,
        );
      });
      await tester.pumpAndSettle().timeout(_waitTimeout);
      expect(
        (await tester.runAsync(
          () => coordinator.configuration.timeout(_waitTimeout),
        ))!.connection.trafficMode,
        TrafficMode.allVpn,
      );
      expect(controller!.state.profileErrors.keys, [brokenId]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stream parse failures stay on their row and repair restores Use',
    (tester) async {
      await tester.runAsync(() async {
        controller = RoutingPageController(
          database: db,
          coordinator: coordinator,
        );
        await controller!.load().timeout(_waitTimeout);
      });
      await pumpPage(tester);
      await tester.runAsync(() async {
        await db.routingProfileDao.updateRow(
          originalGood.copyWith(data: 'also-broken'),
        );
        await waitFor((s) => s.profileErrors.containsKey(goodId));
      });
      await tester.pumpAndSettle().timeout(_waitTimeout);
      expect(controller!.state.failed, isFalse);
      expect(controller!.state.profiles, hasLength(2));
      expect(useEnabled(tester, 'routing-use-profile-$goodId'), isFalse);
      expect(useEnabled(tester, 'routing-use-smart'), isTrue);
      await tester.runAsync(() async {
        await db.routingProfileDao.updateRow(originalGood);
        await waitFor((s) => !s.profileErrors.containsKey(goodId));
      });
      await tester.pumpAndSettle().timeout(_waitTimeout);
      expect(useEnabled(tester, 'routing-use-profile-$goodId'), isTrue);
      expect(controller!.state.profileErrors.keys, [brokenId]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('database load failure retains an explicit retry and recovers', (
    tester,
  ) async {
    var fail = true;
    await tester.runAsync(() async {
      controller = RoutingPageController(
        database: db,
        coordinator: coordinator,
        readProfiles: () => fail
            ? Future.error(StateError('Profile storage unavailable'))
            : db.routingProfileDao.allRows,
      );
      await controller!.load().timeout(_waitTimeout);
    });
    await pumpPage(tester);
    final l = AppLocalizations.of(tester.element(find.byType(RoutingPage)))!;
    expect(controller!.state.failed, isTrue);
    expect(find.text(l.prototypeRetry), findsOneWidget);
    fail = false;
    await tester.runAsync(() async {
      await tester.tap(find.text(l.prototypeRetry));
      await waitFor((s) => !s.failed && s.profiles.length == 2);
    });
    await tester.pumpAndSettle().timeout(_waitTimeout);
    expect(find.text('Good route'), findsOneWidget);
    expect(useEnabled(tester, 'routing-use-smart'), isTrue);
    expect(tester.takeException(), isNull);
  });

  test(
    'an older load cannot replace newer streamed rows or diagnostics',
    () async {
      final first = Completer<List<RoutingProfileData>>(),
          entered = Completer<void>();
      var reads = 0;
      controller = RoutingPageController(
        database: db,
        coordinator: coordinator,
        readProfiles: () {
          if (reads++ == 0) {
            entered.complete();
            return first.future.timeout(_waitTimeout);
          }
          return db.routingProfileDao.allRows;
        },
      );
      await entered.future.timeout(_waitTimeout);
      await controller!.load().timeout(_waitTimeout);
      expect(controller!.state.profiles, hasLength(2));
      first.complete([]);
      await Future<void>.delayed(Duration.zero);
      expect(controller!.state.profiles.map((row) => row.id), [
        goodId,
        brokenId,
      ]);
      expect(controller!.state.profileErrors.keys, [brokenId]);
      expect(controller!.state.failed, isFalse);
    },
  );

  testWidgets('a delayed reload cannot replace a newer Smart selection', (
    tester,
  ) async {
    late Completer<List<RoutingProfileData>> delayedRows;
    var delay = false;
    var reloadFinished = false;
    late Future<void> reload;
    await tester.runAsync(() async {
      // Both barriers belong to the real async zone. A Completer created in
      // the widget test's FakeAsync zone can be completed here while its
      // listeners remain queued until the next pump, deadlocking this await.
      delayedRows = Completer<List<RoutingProfileData>>();
      final entered = Completer<void>();
      controller = RoutingPageController(
        database: db,
        coordinator: coordinator,
        readProfiles: () {
          if (delay) {
            entered.complete();
            return delayedRows.future.timeout(_waitTimeout);
          }
          return db.routingProfileDao.allRows;
        },
      );
      await controller!.load().timeout(_waitTimeout);
      expect(
        (await coordinator.configuration).connection.trafficMode,
        TrafficMode.allVpn,
      );
      // The older load captures the SQLite All preference before Smart saves.
      delay = true;
      reload = controller!.load().whenComplete(() => reloadFinished = true);
      await entered.future.timeout(_waitTimeout);
      expect(reloadFinished, isFalse);
    });
    await pumpPage(tester);
    final context = tester.element(find.byType(RoutingPage));
    expect(useEnabled(tester, 'routing-use-smart'), isTrue);
    await tester.runAsync(() async {
      try {
        await controller!
            .select(context, TrafficMode.smart)
            .timeout(_waitTimeout);
        expect(
          controller!.state.configuration!.connection.trafficMode,
          TrafficMode.smart,
        );
        expect(
          (await coordinator.configuration).connection.trafficMode,
          TrafficMode.smart,
        );
        expect(reloadFinished, isFalse);
      } finally {
        if (!delayedRows.isCompleted) delayedRows.complete([]);
        await reload.timeout(_waitTimeout);
      }
    });
    expect(reloadFinished, isTrue);
    await tester.pumpAndSettle().timeout(_waitTimeout);
    expect(
      controller!.state.configuration!.connection.trafficMode,
      TrafficMode.smart,
    );
    expect(controller!.state.profiles.map((row) => row.id), [goodId, brokenId]);
    expect(controller!.state.profileErrors.keys, [brokenId]);
    expect(controller!.state.failed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
