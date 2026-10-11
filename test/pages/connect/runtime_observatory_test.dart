import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/runtime_observatory.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/traffic.dart';
import 'package:onexray/service/settings/language/locale.dart';

void main() {
  Widget app(ConnectionView view, {Locale locale = const Locale('en')}) =>
      MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RuntimeObservatoryReadout(view: view),
          ),
        ),
      );

  testWidgets(
    'unknown probes do not reuse old availability or RTT after metrics failure',
    (tester) async {
      final runtime = _runtime();
      final paths = runtime.observationPaths;
      final sample = ConnectionTraffic(
        uplink: 0,
        downlink: 0,
        sampledAtMs: DateTime.utc(2026, 10, 11, 0, 1).millisecondsSinceEpoch,
        observations: [
          RuntimePathObservation(
            path: paths[0],
            availability: RuntimePathAvailability.available,
            delayMs: 125,
            lastTryTimeMs: DateTime.utc(
              2026,
              10,
              11,
              0,
              1,
            ).millisecondsSinceEpoch,
          ),
          RuntimePathObservation(
            path: paths[1],
            availability: RuntimePathAvailability.failed,
            lastTryTimeMs: DateTime.utc(
              2026,
              10,
              11,
              0,
              1,
            ).millisecondsSinceEpoch,
          ),
        ],
      );
      await tester.pumpWidget(
        app(ConnectionView(phase: ConnectionPhase.connected, runtime: runtime)),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(RuntimeObservatoryReadout)),
      )!;
      expect(find.text(l.runtimeRoutingUnknown), findsNWidgets(2));
      await tester.pumpWidget(
        app(
          ConnectionView(
            phase: ConnectionPhase.connected,
            runtime: runtime,
            traffic: sample,
            metricsAvailable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l.runtimeRoutingAlive), findsOneWidget);
      expect(find.text(l.runtimeRoutingFailed), findsOneWidget);
      expect(find.text('125 ms'), findsOneWidget);
      await tester.pumpWidget(
        app(
          ConnectionView(
            phase: ConnectionPhase.connected,
            runtime: runtime,
            traffic: sample,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l.runtimeRoutingUnknown), findsNWidgets(2));
      expect(find.text('125 ms'), findsNothing);
      expect(find.text(l.runtimeRoutingUpdatedAt('—')), findsNothing);
    },
  );

  testWidgets(
    'final exit paths retain separate entries and fit narrow RTL screens',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final runtime = _runtime(finalExit: true);
      for (final (width, locale) in [
        (320.0, const Locale('en')),
        (390.0, const Locale('zh')),
        (320.0, const Locale('fa')),
        (1160.0, const Locale('en')),
      ]) {
        await tester.binding.setSurfaceSize(Size(width, 700));
        await tester.pumpWidget(
          app(
            ConnectionView(phase: ConnectionPhase.connected, runtime: runtime),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Entry 0 → Final exit'), findsOneWidget);
        expect(find.text('Entry 1 → Final exit'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('runtime-path-app-exit-0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('runtime-path-app-exit-1')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'inactive and single-node configurations show no running probes',
    (tester) async {
      for (final view in [
        ConnectionView(runtime: _runtime()),
        ConnectionView(
          phase: ConnectionPhase.connected,
          runtime: _runtime(entries: 1),
        ),
        ConnectionView(
          phase: ConnectionPhase.connected,
          runtime: _runtime(strategy: 'roundRobin'),
        ),
      ]) {
        await tester.pumpWidget(app(view));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('runtime-observatory')), findsNothing);
      }
    },
  );
}

ConnectionRuntime _runtime({
  int entries = 2,
  bool finalExit = false,
  String strategy = 'leastPing',
}) {
  final tags = [
    for (var i = 0; i < entries; i++)
      '${finalExit ? 'app-exit' : 'app-entry'}-$i',
  ];
  final json = jsonEncode({
    'routing': {
      'balancers': [
        {
          'tag': 'proxy',
          'selector': tags,
          'strategy': {'type': strategy},
        },
      ],
    },
    'observatory': {'subjectSelector': tags},
  });
  ResolvedServer node(int id, String name) => ResolvedServer(
    id: id,
    sourceId: 7,
    outbound: {'protocol': 'freedom', 'tag': name},
  );
  return ConnectionRuntime.create(
    configuration: ConnectionConfiguration(),
    compiled: CompiledConnection(
      xrayJson: json,
      entries: [for (var i = 0; i < entries; i++) node(i + 1, 'Entry $i')],
      finalExit: finalExit ? node(100, 'Final exit') : null,
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
          payload: RunXrayRequest(json).toJson(),
        ).toJson(),
      ),
    ),
    startedAt: DateTime.utc(2026, 10, 11),
  );
}
