import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/xray/metrics/model.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;

  setUp(() async {
    final fixtures = Directory(
      p.join('..', 'references', 'onexray-refactor-validation', 'fixtures'),
    ).absolute;
    await fixtures.create(recursive: true);
    directory = await fixtures.createTemp('runtime-host-');
    addTearDown(() => directory.delete(recursive: true));
  });

  test('start.json is the only persisted runtime descriptor', () async {
    final runtime = _runtime();
    final originalPath = runtime.request.coreInvokeText;
    await File(p.join(directory.path, 'start.json'))
        .writeAsString(jsonEncode(runtime.request.toJson()));
    final restored = await ConnectionRuntimeHost(runDirectory: directory.path)
        .readRuntime();

    expect(restored?.identity, runtime.identity);
    expect(restored?.nodeIds, {1});
    expect(restored?.entries.single.name, 'Server');
    expect(restored?.request.coreInvokeText, originalPath);
    expect(await Directory(p.join(directory.path, 'plans')).exists(), false);
  });

  test(
    'complete profile identity survives start metadata and protects its row',
    () async {
      const xrayJson = '{"outbounds":[{"protocol":"freedom"}]}';
      final runtime = _runtime(
        profile: _profile(xrayJson),
        entries: const [],
        xrayJson: xrayJson,
      );
      final metadata = jsonDecode(runtime.request.metadataJson!);
      expect(metadata['version'], 1);
      expect(metadata['profile'], {
        'id': 99,
        'sourceId': 7,
        'name': 'Provider profile',
        'type': 'Remnawave',
      });
      expect(runtime.entries, isEmpty);
      expect(runtime.nodeIds, {99});
      final parsed = ConnectionRuntime.fromRequest(runtime.request);
      expect(parsed.profile!.id, 99);
      expect(parsed.profile!.sourceId, 7);
      expect(parsed.profile!.name, 'Provider profile');
      expect(parsed.profile!.type, 'Remnawave');
      expect(parsed.nodeIds, {99});
      expect(parsed.xrayJson, xrayJson);
      expect(parsed.identity, runtime.identity);

      await File(p.join(directory.path, 'start.json'))
          .writeAsString(jsonEncode(runtime.request.toJson()));
      final restored = await ConnectionRuntimeHost(runDirectory: directory.path)
          .readRuntime();
      expect(restored!.profile!.id, 99);
      expect(restored.profile!.sourceId, 7);
      expect(restored.profile!.name, 'Provider profile');
      expect(restored.profile!.type, 'Remnawave');
      expect(restored.nodeIds, {99});
    },
  );

  test('legacy metadata without a profile remains an ordinary runtime', () {
    final request = _runtime().request;
    final metadata = jsonDecode(request.metadataJson!) as Map<String, dynamic>;
    metadata.remove('profile');
    request.metadataJson = jsonEncode(metadata);
    final restored = ConnectionRuntime.fromRequest(request);
    expect(restored.profile, isNull);
    expect(restored.entries.single.name, 'Server');
    expect(restored.nodeIds, {1});
  });

  test('invalid optional profiles reject the runtime descriptor', () async {
    const valid = <String, dynamic>{
      'id': 99,
      'sourceId': 7,
      'name': 'Provider profile',
      'type': 'Remnawave',
    };
    for (final invalid in <Object>[
      'profile',
      [],
      {},
      {...valid, 'id': 0},
      {...valid, 'id': '99'},
      {...valid, 'sourceId': 0},
      {...valid, 'sourceId': '7'},
      {...valid, 'name': ''},
      {...valid, 'name': 99},
      {...valid, 'type': 'raw'},
      {...valid, 'type': 'remnawave'},
      {...valid}..remove('type'),
    ]) {
      final request = _runtime().request;
      final metadata =
          jsonDecode(request.metadataJson!) as Map<String, dynamic>;
      metadata['profile'] = invalid;
      request.metadataJson = jsonEncode(metadata);
      expect(
        () => ConnectionRuntime.fromRequest(request),
        throwsFormatException,
        reason: 'Invalid profile: $invalid',
      );
      await File(p.join(directory.path, 'start.json'))
          .writeAsString(jsonEncode(request.toJson()));
      expect(
        await ConnectionRuntimeHost(runDirectory: directory.path).readRuntime(),
        isNull,
        reason: 'Invalid profile: $invalid',
      );
    }
  });

  test(
    'provider observation tags never become App automatic path observations',
    () async {
      final xrayJson = jsonEncode({
        'outbounds': [
          {'protocol': 'freedom', 'tag': 'app-entry-0'},
          {'protocol': 'freedom', 'tag': 'app-entry-1'},
        ],
        'routing': {
          'balancers': [
            {
              'tag': 'proxy',
              'selector': ['app-entry-0', 'app-entry-1'],
              'strategy': {'type': 'leastPing'},
            },
          ],
        },
        'observatory': {
          'subjectSelector': ['app-entry-0', 'app-entry-1'],
        },
      });
      final entries = [
        for (var id = 1; id <= 2; id++)
          ResolvedServer(
            id: id,
            sourceId: 7,
            outbound: {'protocol': 'freedom', 'tag': 'Entry $id'},
          ),
      ];
      final ordinary = _runtime(entries: entries, xrayJson: xrayJson);
      expect(ordinary.observationPaths, hasLength(2));
      // Retained ordinary entry metadata must not turn a provider's otherwise
      // identical tag/strategy choices into App-managed observation paths.
      final provider = _runtime(
        profile: _profile(xrayJson),
        entries: entries,
        xrayJson: xrayJson,
      );
      expect(provider.nodeIds, {1, 2, 99});
      expect(provider.observationPaths, isEmpty);
      final restored = ConnectionRuntime.fromRequest(provider.request);
      expect(restored.nodeIds, {1, 2, 99});
      expect(restored.observationPaths, isEmpty);
      final host = ConnectionRuntimeHost(
        readMetrics: (_) async => _metrics(3, 5),
      );
      expect((await host.query(ordinary)).observations, hasLength(2));
      final traffic = await host.query(restored);
      expect(traffic.observations, isEmpty);
      expect(traffic.uplink, 3);
      expect(traffic.downlink, 5);
    },
  );

  test(
    'native start and stop failures retain their original messages',
    () async {
      final host = ConnectionRuntimeHost(
        startVpn: (_) async => NativeVpnCommandResult(
          state: NativeVpnCommandState.failed,
          message: 'TUN device could not be opened',
        ),
        stopVpn: () async => NativeVpnCommandResult(
          state: NativeVpnCommandState.failed,
          message: 'Access denied while stopping Core',
        ),
      );
      await expectLater(
        host.start(_runtime()),
        throwsA(
          isA<ConnectionHostException>()
              .having((e) => e.reason, 'reason', 'startFailed')
              .having(
                (e) => e.cause,
                'cause',
                'TUN device could not be opened',
              ),
        ),
      );
      await expectLater(
        host.stop(),
        throwsA(
          isA<ConnectionHostException>()
              .having((e) => e.reason, 'reason', 'stopFailed')
              .having(
                (e) => e.cause,
                'cause',
                'Access denied while stopping Core',
              ),
        ),
      );
    },
  );

  test('invalid start metadata is ignored', () async {
    await File(p.join(directory.path, 'start.json')).writeAsString(
      jsonEncode(StartVpnRequest(null, null, null, '{}').toJson()),
    );

    expect(
      await ConnectionRuntimeHost(runDirectory: directory.path).readRuntime(),
      isNull,
    );
  });

  test(
    'runtime metadata shares the default for unknown selection kinds',
    () async {
      for (final kind in ['region', 'futureSelection']) {
        final request = _runtime().request;
        final metadata =
            jsonDecode(request.metadataJson!) as Map<String, dynamic>;
        metadata['configuration']['connection']['selection'] = {
          'kind': kind,
          'region': 'SG',
        };
        final stored = request.toJson()
          ..['metadataJson'] = jsonEncode(metadata);
        await File(p.join(directory.path, 'start.json'))
            .writeAsString(jsonEncode(stored));
        final restored = await ConnectionRuntimeHost(
          runDirectory: directory.path,
        ).readRuntime();
        expect(
          restored?.configuration.connection.selection.kind,
          SelectionKind.automatic,
        );
        expect(restored?.nodeIds, {1});
      }
    },
  );

  test(
    'inspect associates native status with the active start request',
    () async {
      final runtime = _runtime();
      final host = ConnectionRuntimeHost(
        runDirectory: directory.path,
        readMetrics: (_) async => throw const FormatException(),
        readStatus: () async => VpnStatus.connected,
      );

      final connected = await host.inspect(runtime);
      expect(connected.status, VpnStatus.connected);
      expect(connected.runtime?.identity, runtime.identity);
      expect(connected.traffic, isNull);
    },
  );

  for (final status in VpnStatus.values) {
    test('native $status remains visible without runtime metadata', () async {
      final host = ConnectionRuntimeHost(readStatus: () async => status);
      final current = await host.inspect(null);
      expect(current.status, status);
      expect(current.runtime, isNull);
      expect(current.traffic, isNull);
    });
  }

  test(
    'metrics HTTP is the only source and writes no accounting files',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <String>[];
      server.listen((request) async {
        requests.add(request.uri.path);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_metrics(15, 30).toJson()));
        await request.response.close();
      });
      final runtime = _runtime();
      runtime.request.metricsPort = server.port.toString();
      final host = ConnectionRuntimeHost(runDirectory: directory.path);

      final traffic = await host.query(runtime);
      expect(traffic.uplink, 15);
      expect(traffic.downlink, 30);
      expect(requests, ['/debug/vars']);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'idle metrics have zero counters; malformed metrics are unavailable',
    () async {
      final runtime = _runtime();
      var metrics = const XrayMetricsVars(XrayMetricsStats(null));
      final host = ConnectionRuntimeHost(readMetrics: (_) async => metrics);
      final idle = await host.query(runtime);
      expect(idle.uplink, 0);
      expect(idle.downlink, 0);
      metrics = const XrayMetricsVars(null);
      await expectLater(host.query(runtime), throwsFormatException);
      metrics = _metrics(-1, 0);
      await expectLater(host.query(runtime), throwsFormatException);
    },
  );

  test(
    'session traffic counts only tunIn regardless of other inbounds',
    () async {
      final host = ConnectionRuntimeHost(
        readMetrics: (_) async => XrayMetricsVars.fromJson({
          'stats': {
            'inbound': {
              'tunIn': {'uplink': 10, 'downlink': 20},
              'app-lan-proxy': {'uplink': 30, 'downlink': 40},
              'other': {'uplink': 1000, 'downlink': 2000},
            },
            'outbound': {
              'proxy': {'uplink': 4000, 'downlink': 5000},
            },
          },
        }),
      );
      final traffic = await host.query(_runtime());
      expect(traffic.uplink, 10);
      expect(traffic.downlink, 20);
    },
  );

  test(
    'start and stop depend on native state, not metrics availability',
    () async {
      final runtime = _runtime();
      var statusReads = 0;
      var metricReads = 0;
      final host = ConnectionRuntimeHost(
        runDirectory: directory.path,
        readMetrics: (_) async {
          metricReads++;
          throw const FormatException();
        },
        readStatus: () async {
          statusReads++;
          return VpnStatus.disconnected;
        },
        startVpn: (_) async {
          return NativeVpnCommandResult(
            state: NativeVpnCommandState.success,
            status: VpnStatus.connected,
          );
        },
        stopVpn: () async {
          return NativeVpnCommandResult(
            state: NativeVpnCommandState.success,
            status: VpnStatus.disconnected,
          );
        },
      );

      expect((await host.start(runtime)).runtime?.identity, runtime.identity);
      expect((await host.stop()).status, VpnStatus.disconnected);
      expect(metricReads, 0);
      expect(
        statusReads,
        0,
        reason: 'Platforms confirm commands; the host must not poll again.',
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'accepting a command without a confirmed status is not success',
    () async {
      final host = ConnectionRuntimeHost(
        startVpn: (_) async =>
            NativeVpnCommandResult(state: NativeVpnCommandState.success),
        stopVpn: () async =>
            NativeVpnCommandResult(state: NativeVpnCommandState.success),
        readStatus: () async => throw StateError('must not poll'),
      );
      await expectLater(
        host.start(_runtime()),
        throwsA(
          isA<ConnectionHostException>().having(
            (e) => e.reason,
            'reason',
            'startNotConfirmed',
          ),
        ),
      );
      await expectLater(
        host.stop(),
        throwsA(
          isA<ConnectionHostException>().having(
            (e) => e.reason,
            'reason',
            'stopNotConfirmed',
          ),
        ),
      );
    },
  );
}

ConnectionRuntime _runtime({
  ResolvedProfile? profile,
  List<ResolvedServer>? entries,
  String xrayJson = '{"outbounds":[]}',
}) {
  final configuration = ConnectionConfiguration();
  final server = ResolvedServer(
    id: 1,
    sourceId: 7,
    outbound: {'protocol': 'freedom', 'tag': 'Server'},
  );
  final compiled = CompiledConnection(
    xrayJson: xrayJson,
    entries: entries ?? [server],
    finalExit: null,
    nodeTags: const {},
    profile: profile,
  );
  final invoke = LibXrayInvokeRequest(
    method: LibXrayMethod.runXray,
    payload: RunXrayRequest(xrayJson).toJson(),
  );
  return ConnectionRuntime.create(
    configuration: configuration,
    compiled: compiled,
    platform: ConnectionPlatform.android,
    request: StartVpnRequest(null, null, '18003', jsonEncode(invoke.toJson())),
  );
}

ResolvedProfile _profile(String xrayJson) => ResolvedProfile(
  id: 99,
  sourceId: 7,
  name: 'Provider profile',
  config: jsonDecode(xrayJson) as Map<String, dynamic>,
);

XrayMetricsVars _metrics(int up, int down) => XrayMetricsVars(
  XrayMetricsStats(XrayMetricsInboundStats(XrayTrafficCounter(up, down))),
);
