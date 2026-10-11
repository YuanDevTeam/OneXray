import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/traffic.dart';
import 'package:onexray/service/shared/xray/metrics/model.dart';

void main() {
  test(
    'one metrics HTTP request supplies traffic and all complete proxy paths',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <String>[];
      final runtime = _runtime(finalExit: true);
      final probeTime = runtime.startedAt.millisecondsSinceEpoch ~/ 1000 + 60;
      server.listen((request) async {
        requests.add(request.uri.path);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stats': {
              'inbound': {
                'tunIn': {'uplink': 10, 'downlink': 20},
              },
            },
            'observatory': {
              'app-exit-0': {
                'alive': true,
                'delay': 55,
                'outbound_tag': 'app-exit-0',
                'last_try_time': probeTime,
                'last_seen_time': probeTime,
              },
              'app-exit-1': {
                'delay': 99999999,
                'outbound_tag': 'app-exit-1',
                'last_try_time': probeTime,
              },
              // Helper/entry samples must not replace final-exit chain samples.
              'app-entry-0': {
                'alive': true,
                'delay': 1,
                'outbound_tag': 'app-entry-0',
                'last_try_time': probeTime,
              },
            },
          }),
        );
        await request.response.close();
      });
      runtime.request.metricsPort = server.port.toString();
      final sample = await ConnectionRuntimeHost().query(runtime);
      expect(requests, ['/debug/vars']);
      expect(sample.uplink, 10);
      expect(sample.downlink, 20);
      expect(sample.observations.map((value) => value.path.tag), [
        'app-exit-0',
        'app-exit-1',
        'app-exit-2',
      ]);
      expect(sample.observations.map((value) => value.path.entryName), [
        'Entry 0',
        'Entry 1',
        'Entry 2',
      ]);
      expect(
        sample.observations.every(
          (value) => value.path.finalExitName == 'Final exit',
        ),
        true,
      );
      expect(
        sample.observations[0].availability,
        RuntimePathAvailability.available,
      );
      expect(sample.observations[0].delayMs, 55);
      expect(sample.observations[0].lastTryTimeMs, probeTime * 1000);
      expect(sample.observations[0].lastSeenTimeMs, probeTime * 1000);
      expect(
        sample.observations[1].availability,
        RuntimePathAvailability.failed,
      );
      expect(sample.observations[1].delayMs, isNull);
      expect(
        sample.observations[2].availability,
        RuntimePathAvailability.unknown,
      );
    },
  );

  test('reports are scoped to current-session exact tags and missing remains unknown', () async {
    final runtime = _runtime();
    final started = runtime.startedAt.millisecondsSinceEpoch ~/ 1000;
    var reports = <String, dynamic>{
      'app-entry-0': {
        'alive': true,
        'outbound_tag': 'app-entry-0',
        'last_try_time': started - 1,
      },
      'app-entry-1': {
        'alive': true,
        'outbound_tag': 'app-entry-0',
        'last_try_time': started,
      },
    };
    final host = ConnectionRuntimeHost(
      readMetrics: (_) async => XrayMetricsVars.fromJson({
        'stats': {'inbound': <String, dynamic>{}},
        'observatory': reports,
      }),
    );
    expect(
      (await host.query(runtime)).observations.every(
        (value) => value.availability == RuntimePathAvailability.unknown,
      ),
      true,
    );
    reports = {
      'app-entry-0': {
        'alive': true,
        'outbound_tag': 'app-entry-0',
        'last_try_time': started,
      },
      'app-entry-1': {'outbound_tag': 'app-entry-1', 'last_try_time': started},
    };
    final sample = await host.query(runtime);
    expect(
      sample.observations[0].availability,
      RuntimePathAvailability.available,
    );
    expect(sample.observations[0].delayMs, 0);
    expect(sample.observations[1].availability, RuntimePathAvailability.failed);
    reports = {};
    expect(
      (await host.query(runtime)).observations.every(
        (value) => value.availability == RuntimePathAvailability.unknown,
      ),
      true,
    );
  });

  test(
    'single-node and round-robin runs expose no automatic probe status',
    () async {
      for (final runtime in [
        _runtime(entries: 1),
        _runtime(strategy: 'roundRobin'),
        _runtime(expert: true),
      ]) {
        expect(runtime.observationPaths, isEmpty);
        final sample = await ConnectionRuntimeHost(
          readMetrics: (_) async =>
              const XrayMetricsVars(XrayMetricsStats(null)),
        ).query(runtime);
        expect(sample.observations, isEmpty);
      }
    },
  );

  test(
    'restored start request retains exact chain mapping without new metadata',
    () {
      final original = _runtime(finalExit: true);
      final restored = ConnectionRuntime.fromRequest(original.request);
      expect(restored.observationPaths.map((value) => value.tag), [
        'app-exit-0',
        'app-exit-1',
        'app-exit-2',
      ]);
      expect(restored.observationPaths[1].entryName, 'Entry 1');
      expect(restored.observationPaths[1].finalExitName, 'Final exit');
      expect(
        identical(restored.observationPaths, restored.observationPaths),
        true,
      );
      final metadata = jsonDecode(restored.request.metadataJson!);
      expect(metadata['version'], 1);
      expect(metadata.containsKey('observatory'), false);
    },
  );
}

ConnectionRuntime _runtime({
  int entries = 3,
  bool finalExit = false,
  String strategy = 'leastPing',
  bool expert = false,
}) {
  final tags = [
    for (var index = 0; index < entries; index++)
      '${finalExit ? 'app-exit' : 'app-entry'}-$index',
  ];
  final xrayJson = jsonEncode({
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
  final invoke = LibXrayInvokeRequest(
    method: LibXrayMethod.runXray,
    payload: RunXrayRequest(xrayJson).toJson(),
  );
  return ConnectionRuntime.create(
    configuration: ConnectionConfiguration(
      connection: ConnectionSettings(expert: expert),
    ),
    compiled: CompiledConnection(
      xrayJson: xrayJson,
      entries: [for (var i = 0; i < entries; i++) node(i + 1, 'Entry $i')],
      finalExit: finalExit ? node(100, 'Final exit') : null,
      nodeTags: const {},
    ),
    platform: ConnectionPlatform.android,
    request: StartVpnRequest(null, null, '18003', jsonEncode(invoke.toJson())),
    startedAt: DateTime.utc(2026, 10, 11),
  );
}
