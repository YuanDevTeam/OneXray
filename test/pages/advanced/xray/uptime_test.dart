import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/pages/advanced/controller.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/adaptive_shell.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/main/page_visibility.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:onexray/service/connect/coordinator.dart';

import 'dart:convert';

import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';

void main() {
  testWidgets('visible inactive windows keep the uptime clock running', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final coordinator = ConnectionCoordinator(database: db);
    var now = DateTime(2026, 9, 3);
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: _runtime(now.subtract(const Duration(minutes: 1))),
    );
    final controller = _AdvancedController(
      coordinator: coordinator,
      now: () => now,
    );
    try {
      controller.setVisible(true);
      await tester.pump();
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.state.uptime, '0:01:01');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.state.uptime, '0:01:02');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(controller.state.uptime, '0:01:02');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(controller.state.uptime, '0:01:07');
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.state.uptime, '0:01:08');
    } finally {
      await controller.close();
      coordinator.dispose();
      await db.close();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });

  testWidgets(
    'uptime uses a visible application clock, without metrics updates',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final coordinator = ConnectionCoordinator(database: db);
      var now = DateTime(2026, 9, 3);
      coordinator.state.value = ConnectionView(
        phase: ConnectionPhase.connected,
        runtime: _runtime(now.subtract(const Duration(minutes: 1))),
      );
      final controller = _AdvancedController(
        coordinator: coordinator,
        now: () => now,
      );
      controller.setVisible(true);
      await tester.pump();
      expect(controller.state.uptime, '0:01:00');
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.state.uptime, '0:01:01');

      controller.setVisible(false);
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(controller.state.uptime, '0:01:01');
      controller.setVisible(true);
      expect(controller.state.uptime, '0:01:04');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(controller.state.uptime, '0:01:04');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(controller.state.uptime, '0:01:09');

      coordinator.state.value = const ConnectionView();
      expect(controller.state.uptime, '—');
      await controller.close();
      coordinator.dispose();
      await db.close();
    },
  );

  testWidgets('xray uptime follows primary navigation and covered routes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1160, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final coordinator = ConnectionCoordinator(database: db);
    var now = DateTime(2026, 9, 3);
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: _runtime(now.subtract(const Duration(minutes: 1))),
    );
    final controller = _AdvancedController(
      coordinator: coordinator,
      now: () => now,
    );
    final bus = AppEventBus();
    final router = GoRouter(
      initialLocation: AppPrimaryDestination.xray.rootPath,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AdaptiveMainShell(
            navigationShell: shell,
            hasActiveModal: (_) => false,
            initializeServices: (_) async {},
          ),
          branches: [
            for (final primary in AppPrimaryDestination.values)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: primary.rootPath,
                    builder: (_, _) => primary == AppPrimaryDestination.xray
                        ? PageVisibility(
                            onChanged: controller.setVisible,
                            child: const Text('xray-content'),
                          )
                        : Text('${primary.name}-content'),
                    routes: [
                      GoRoute(
                        path: AppPageDestination.xrayDiagnostics.segment,
                        builder: (_, _) => const Text('diagnostics-content'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    try {
      await tester.pumpWidget(
        BlocProvider.value(
          value: bus,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.material(Brightness.light, mobile: false),
            builder: (_, child) => ShadTheme(
              data: AppTheme.shad(Brightness.light, mobile: false),
              child: child!,
            ),
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.state.uptime, '0:01:00');

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.state.uptime, '0:01:01');

      await tester.tap(find.byKey(const ValueKey('primary-navigation-tunnel')));
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('tunnel-content'), findsOneWidget);
      expect(controller.state.uptime, '0:01:01');

      await tester.tap(find.byKey(const ValueKey('primary-navigation-xray')));
      await tester.pumpAndSettle();
      expect(controller.state.uptime, '0:01:04');

      final detail = router.push<void>(
        '/xray/${AppPageDestination.xrayDiagnostics.segment}',
      );
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('diagnostics-content'), findsOneWidget);
      expect(controller.state.uptime, '0:01:04');
      router.pop();
      await tester.pumpAndSettle();
      await detail;
      expect(controller.state.uptime, '0:01:07');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await bus.close();
      await controller.close();
      coordinator.dispose();
      await db.close();
    }
  });
}

class _AdvancedController extends AdvancedController {
  _AdvancedController({required super.coordinator, required super.now});

  @override
  Future<void> reload() async {}
}

ConnectionRuntime _runtime(DateTime startedAt) => ConnectionRuntime.create(
  configuration: ConnectionConfiguration(),
  compiled: CompiledConnection(
    xrayJson: '{}',
    entries: const [],
    finalExit: null,
    nodeTags: const {},
  ),
  platform: ConnectionPlatform.android,
  request: StartVpnRequest(
    null,
    null,
    '18003',
    jsonEncode(
      LibXrayInvokeRequest(
        method: LibXrayMethod.runXray,
        payload: RunXrayRequest('{}').toJson(),
      ).toJson(),
    ),
  ),
  startedAt: startedAt,
);
