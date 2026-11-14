import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/startup_probe.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/ping/state.dart';

import 'compiler_test.dart' show catalog, node, options;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in TrafficMode.values) {
    test(
      '${mode.name} probes a single round-robin chain without observatory',
      () async {
        final runtime = _compiledRuntime(mode: mode);
        final settings = PingState()
          ..url = PingUrl.custom
          ..customUrl = 'https://example.com/check'
          ..timeout = 8;
        var calls = 0;
        final probe = ConnectionStartupProbe(
          readPingState: () async => settings,
          runBatch: (sources, actualSettings) async {
            calls++;
            expect(actualSettings, same(settings));
            expect(sources.single.outboundTag, 'app-entry-0');
            expect(sources.single.xrayJson, runtime.xrayJson);
            return [const PingBatchResult(true, 13, '')];
          },
        );
        expect(runtime.observationPaths, isEmpty);
        expect(await probe.run(runtime), isTrue);
        expect(calls, 1);
      },
    );
  }

  test(
    'the default advanced profile probes its compiled proxy chain',
    () async {
      final runtime = _compiledRuntime(
        mode: TrafficMode.custom,
        advanced: true,
      );
      final original = runtime.xrayJson;
      var calls = 0;
      final probe = ConnectionStartupProbe(
        readPingState: () async => PingState(),
        runBatch: (sources, settings) async {
          calls++;
          expect(sources.single.outboundTag, 'app-entry-0');
          expect(sources.single.xrayJson, original);
          final graph = jsonDecode(sources.single.xrayJson);
          expect(
            graph['routing']['balancers'].single['strategy']['type'],
            'roundRobin',
          );
          expect(
            (graph['outbounds'] as List).map((outbound) => outbound['tag']),
            containsAll(['app-entry-0', 'dnsOut', 'dns-forward']),
          );
          return [const PingBatchResult(true, 11, '')];
        },
      );
      expect(runtime.observationPaths, isEmpty);
      expect(await probe.run(runtime), isTrue);
      expect(calls, 1);
      expect(runtime.xrayJson, original);
    },
  );

  test(
    'final-exit checks preserve the exact run and all chain dependencies',
    () async {
      final runtime = _compiledRuntime(
        entries: 2,
        finalExit: true,
        fragment: true,
      );
      final originalRequest = jsonEncode(runtime.request.toJson());
      final probe = ConnectionStartupProbe(
        readPingState: () async => PingState(),
        runBatch: (sources, settings) async {
          expect(sources.map((source) => source.outboundTag), [
            'app-exit-0',
            'app-exit-1',
          ]);
          for (final source in sources) {
            expect(source.xrayJson, runtime.xrayJson);
            final json = jsonDecode(source.xrayJson) as Map<String, dynamic>;
            expect(
              (json['outbounds'] as List).map((outbound) => outbound['tag']),
              containsAll(['app-entry-0', 'app-entry-1', 'fragment']),
            );
            final outbounds = (json['outbounds'] as List).cast<Map>();
            for (var index = 0; index < 2; index++) {
              final exit = outbounds.singleWhere(
                (outbound) => outbound['tag'] == 'app-exit-$index',
              );
              final entry = outbounds.singleWhere(
                (outbound) => outbound['tag'] == 'app-entry-$index',
              );
              expect(
                exit['streamSettings']['sockopt']['dialerProxy'],
                'app-entry-$index',
              );
              expect(
                entry['streamSettings']['sockopt']['dialerProxy'],
                'fragment',
              );
            }
            expect(json['dns'], isNotNull);
          }
          return [
            PingBatchResult.failed(),
            const PingBatchResult(true, 20, ''),
          ];
        },
      );
      expect(await probe.run(runtime), isTrue);
      expect(jsonEncode(runtime.request.toJson()), originalRequest);
    },
  );

  test('only all failed paths produce a failed reference check', () async {
    final runtime = _compiledRuntime(entries: 2);
    var reads = 0;
    var calls = 0;
    final probe = ConnectionStartupProbe(
      readPingState: () async {
        reads++;
        return PingState();
      },
      runBatch: (sources, settings) async {
        calls++;
        expect(sources, hasLength(2));
        return [PingBatchResult.failed(), PingBatchResult.failed()];
      },
    );
    expect(await probe.run(runtime), isFalse);
    expect(reads, 1);
    expect(calls, 1);
  });

  test(
    'unsupported execution and ambiguous graphs never invoke native tests',
    () async {
      var reads = 0;
      var calls = 0;
      ConnectionStartupProbe probe({bool supported = true}) =>
          ConnectionStartupProbe(
            supported: () => supported,
            readPingState: () async {
              reads++;
              return PingState();
            },
            runBatch: (sources, settings) async {
              calls++;
              return [];
            },
          );
      expect(await probe(supported: false).run(_runtime()), isNull);
      for (final runtime in [
        _runtime(expert: true),
        _runtime(provider: true),
        _runtime(entries: 0),
        _runtime(entries: 6),
        _runtime(selectors: ['app-entry-']),
        _runtime(selectors: ['direct']),
        _runtime(entries: 2, selectors: ['app-entry-0', 'app-entry-0']),
        _runtime(missingOutbound: true),
        _runtime(extraBalancer: true),
        _runtime(invalidJson: true),
      ]) {
        expect(await probe().run(runtime), isNull);
      }
      expect(reads, 0);
      expect(calls, 0);
    },
  );

  test(
    'an execution error is returned without escaping into connection startup',
    () async {
      final probe = ConnectionStartupProbe(
        readPingState: () async => PingState(),
        runBatch: (_, _) async => throw StateError('probe failed'),
      );
      expect(await probe.run(_runtime()), isFalse);
    },
  );

  test(
    'unavailable preferences skip the check before invoking native code',
    () async {
      final probe = ConnectionStartupProbe(
        readPingState: () async => throw StateError('preferences unavailable'),
        runBatch: (_, _) async => fail('No test settings were loaded'),
      );
      expect(await probe.run(_runtime()), isNull);
    },
  );
}

ConnectionRuntime _compiledRuntime({
  TrafficMode mode = TrafficMode.smart,
  int entries = 1,
  bool finalExit = false,
  bool fragment = false,
  bool advanced = false,
}) {
  final settings = ConnectionSettings(
    trafficMode: mode,
    smart: SmartRoutingSettings(
      entryCount: entries,
      finalExitId: finalExit ? 100 : null,
      fragment: fragment,
      selection: const RoutingSelectionSettings(type: 'roundRobin'),
    ),
  );
  final compiled = ConnectionCompiler.compile(
    settings: settings,
    entries: [for (var index = 0; index < entries; index++) node(index + 1)],
    finalExit: finalExit ? node(100) : null,
    custom: mode != TrafficMode.custom
        ? null
        : advanced
        ? AdvancedRoutingDocument.parse(
            AdvancedRoutingProfile.defaultText,
            name: 'Default advanced',
          ).state
        : RoutingProfileState(
            name: 'Custom',
            entryCount: entries,
            selection: const RoutingSelectionSettings(type: 'roundRobin'),
          ),
    regions: catalog,
    options: options(),
  );
  return ConnectionRuntime.create(
    configuration: ConnectionConfiguration(connection: settings),
    compiled: compiled,
    platform: ConnectionPlatform.android,
    request: StartVpnRequest(null, null, '18186', null),
  );
}

ConnectionRuntime _runtime({
  int entries = 1,
  bool expert = false,
  bool provider = false,
  bool missingOutbound = false,
  bool extraBalancer = false,
  bool invalidJson = false,
  List<String>? selectors,
}) {
  ResolvedServer node(int id) => ResolvedServer(
    id: id,
    sourceId: 1,
    outbound: {'tag': 'Node $id', 'protocol': 'freedom'},
  );
  final tags = [
    for (var index = 0; index < entries; index++) 'app-entry-$index',
  ];
  final xrayJson = invalidJson
      ? '{'
      : jsonEncode({
          'outbounds': [
            for (var index = 0; index < entries; index++)
              if (!missingOutbound) {'tag': tags[index], 'protocol': 'freedom'},
            {'tag': 'direct', 'protocol': 'freedom'},
          ],
          'routing': {
            'balancers': [
              {'tag': 'proxy', 'selector': selectors ?? tags},
              if (extraBalancer) {'tag': 'proxy', 'selector': tags},
            ],
          },
          'dns': {
            'servers': ['tcp://8.8.8.8'],
          },
        });
  final compiled = CompiledConnection(
    xrayJson: xrayJson,
    entries: [for (var index = 0; index < entries; index++) node(index + 1)],
    finalExit: null,
    profile: provider
        ? ResolvedProfile(id: 10, sourceId: 1, name: 'Provider', config: {})
        : null,
    nodeTags: const {},
  );
  return ConnectionRuntime.create(
    configuration: ConnectionConfiguration(
      connection: ConnectionSettings(expert: expert),
    ),
    compiled: compiled,
    platform: ConnectionPlatform.android,
    request: StartVpnRequest(null, null, '18003', null),
  );
}
