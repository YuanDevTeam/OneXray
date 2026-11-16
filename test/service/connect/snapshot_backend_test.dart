import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:path/path.dart' as p;

import '../../support/test_directory.dart';

NativeVpnCommandResult _success(VpnStatus status) => NativeVpnCommandResult(
  state: NativeVpnCommandState.success,
  status: status,
);

ConnectionRuntime _runtime({required bool proxy}) => ConnectionRuntime.create(
  configuration: ConnectionConfiguration(
    policy: PlatformPolicy.fromJson({'captureMode': proxy ? 'proxy' : 'tun'}),
  ),
  compiled: CompiledConnection(
    xrayJson: '{}',
    entries: [
      ResolvedServer(
        id: proxy ? 2 : 1,
        sourceId: 0,
        outbound: {
          'protocol': 'freedom',
          'tag': proxy ? 'proxy-node' : 'tun-node',
        },
      ),
    ],
    finalExit: null,
    nodeTags: const {},
  ),
  platform: ConnectionPlatform.macos,
  request: StartVpnRequest(
    null,
    '10808',
    '18081',
    jsonEncode(
      LibXrayInvokeRequest(
        method: LibXrayMethod.runXray,
        payload: RunXrayRequest('{}').toJson(),
      ).toJson(),
    ),
    captureMode: proxy ? 'proxy' : 'tun',
  ),
  startedAt: DateTime(2026, 11, 16, 0, 0, proxy ? 2 : 1),
);

final class _Backends {
  _Backends(this.directory);
  final Directory directory;
  final tun = _runtime(proxy: false);
  final proxy = _runtime(proxy: true);
  bool preferredProxy = true;
  VpnStatus tunStatus = VpnStatus.disconnected;
  VpnStatus proxyStatus = VpnStatus.disconnected;
  NativeVpnCommandResult? proxyFailure;
  bool failTunStop = false;
  bool failProxyStop = false;
  bool onDemandEnabled = false;
  final calls = <String>[];

  ConnectionRuntimeHost host() => ConnectionRuntimeHost(
    runDirectory: directory.path,
    prefersProxy: () async => preferredProxy,
    readStatus: () async {
      calls.add('read-tun');
      return tunStatus;
    },
    readProxyStatus: () async {
      calls.add('read-proxy');
      return proxyFailure ?? _success(proxyStatus);
    },
    stopVpn: () async {
      calls.add('stop-tun');
      if (failTunStop) {
        return NativeVpnCommandResult(
          state: NativeVpnCommandState.failed,
          status: tunStatus,
          message: 'TUN stop failed',
        );
      }
      onDemandEnabled = false;
      tunStatus = VpnStatus.disconnected;
      return _success(tunStatus);
    },
    stopProxy: () async {
      calls.add('stop-proxy');
      if (failProxyStop) {
        return NativeVpnCommandResult(
          state: NativeVpnCommandState.failed,
          status: proxyStatus,
          message: 'Proxy stop failed',
        );
      }
      proxyFailure = null;
      proxyStatus = VpnStatus.disconnected;
      return _success(proxyStatus);
    },
  );

  Future<void> write(bool proxyFile, ConnectionRuntime runtime) async {
    await File(
      p.join(directory.path, proxyFile ? 'proxy-start.json' : 'start.json'),
    ).writeAsString(jsonEncode(runtime.request.toJson()));
  }

  Future<void> writeBoth() async {
    await write(false, tun);
    await write(true, proxy);
  }
}

void main() {
  late _Backends backends;
  setUp(() async {
    final directory = await createTestDirectory('onexray-snapshot-backend-');
    addTearDown(() => directory.delete(recursive: true));
    backends = _Backends(directory);
  });

  for (final activeProxy in [false, true]) {
    test(
      'cold inspection and Stop use the active ${activeProxy ? 'proxy' : 'TUN'} backend instead of saved preference',
      () async {
        await backends.writeBoth();
        backends.preferredProxy = !activeProxy;
        backends.tunStatus = activeProxy
            ? VpnStatus.disconnected
            : VpnStatus.connected;
        backends.proxyStatus = activeProxy
            ? VpnStatus.connected
            : VpnStatus.disconnected;
        final host = backends.host();
        final candidate = await host.readRuntime();
        expect(candidate!.isProxy, !activeProxy);

        final current = await host.inspect(
          candidate,
          observedStatus: VpnStatus.disconnected,
        );

        expect(current.status, VpnStatus.connected);
        expect(
          current.runtime!.identity,
          (activeProxy ? backends.proxy : backends.tun).identity,
        );
        expect(current.runtime!.isProxy, activeProxy);
        backends.calls.clear();
        // A new host has no in-memory result from inspect and must make the same
        // decision from real backend status, not the stale candidate snapshot.
        expect((await backends.host().stop()).status, VpnStatus.disconnected);
        expect(backends.calls.where((call) => call.startsWith('stop-')), [
          activeProxy ? 'stop-proxy' : 'stop-tun',
          if (activeProxy && AppPlatform.isMacOS) 'stop-tun',
        ]);
      },
    );
  }

  for (final firstProxy in [false, true]) {
    test(
      'global Stop closes both active backends starting with ${firstProxy ? 'proxy' : 'TUN'}',
      () async {
        await backends.writeBoth();
        backends.preferredProxy = firstProxy;
        backends.tunStatus = VpnStatus.connected;
        backends.proxyStatus = VpnStatus.connected;

        final stopped = await backends.host().stop();

        expect(stopped.status, VpnStatus.disconnected);
        expect(backends.tunStatus, VpnStatus.disconnected);
        expect(backends.proxyStatus, VpnStatus.disconnected);
        expect(
          backends.calls,
          firstProxy
              ? ['read-proxy', 'stop-proxy', 'read-tun', 'stop-tun']
              : ['read-tun', 'stop-tun', 'read-proxy', 'stop-proxy'],
        );
      },
    );

    test(
      'a failed second ${firstProxy ? 'TUN' : 'proxy'} Stop stays retryable after the first backend closes',
      () async {
        await backends.writeBoth();
        backends.preferredProxy = firstProxy;
        backends.tunStatus = VpnStatus.connected;
        backends.proxyStatus = VpnStatus.connected;
        backends.failTunStop = firstProxy;
        backends.failProxyStop = !firstProxy;
        final host = backends.host();

        await expectLater(
          host.stop(),
          throwsA(
            isA<ConnectionHostException>().having(
              (error) => error.reason,
              'reason',
              'stopFailed',
            ),
          ),
        );

        expect(
          backends.tunStatus,
          firstProxy ? VpnStatus.connected : VpnStatus.disconnected,
        );
        expect(
          backends.proxyStatus,
          firstProxy ? VpnStatus.disconnected : VpnStatus.connected,
        );
        final remaining = await host.inspect(await host.readRuntime());
        expect(remaining.status, VpnStatus.connected);
        expect(remaining.runtime!.isProxy, !firstProxy);
        backends.failTunStop = false;
        backends.failProxyStop = false;
        backends.calls.clear();

        expect((await host.stop()).status, VpnStatus.disconnected);

        expect(
          backends.calls,
          firstProxy
              ? ['read-tun', 'stop-tun', 'read-proxy']
              : [
                  'read-proxy',
                  'stop-proxy',
                  'read-tun',
                  if (AppPlatform.isMacOS) 'stop-tun',
                ],
        );
        expect(backends.tunStatus, VpnStatus.disconnected);
        expect(backends.proxyStatus, VpnStatus.disconnected);
      },
    );
  }

  test('global Stop skips an idle proxy and clears idle macOS TUN on-demand every time', () async {
    await backends.writeBoth();
    backends.onDemandEnabled = AppPlatform.isMacOS;
    final host = backends.host();

    expect((await host.stop()).status, VpnStatus.disconnected);

    expect(backends.calls.where((call) => call.startsWith('stop-')), [
      if (AppPlatform.isMacOS) 'stop-tun',
    ]);
    expect(backends.calls, containsAll(['read-tun', 'read-proxy']));
    expect(backends.onDemandEnabled, false);
    if (AppPlatform.isMacOS) {
      // System Settings can re-enable on-demand between explicit Stops.
      backends.onDemandEnabled = true;
      expect((await host.stop()).status, VpnStatus.disconnected);
      expect(backends.onDemandEnabled, false);
      expect(backends.calls.where((call) => call == 'stop-tun').length, 2);
      expect(backends.calls, isNot(contains('stop-proxy')));
    }
  });

  test(
    'a failed idle macOS on-demand cleanup cannot report global disconnected',
    () async {
      await backends.writeBoth();
      backends.onDemandEnabled = true;
      backends.failTunStop = true;
      final host = backends.host();

      await expectLater(
        host.stop(),
        throwsA(
          isA<ConnectionHostException>().having(
            (error) => error.reason,
            'reason',
            'stopFailed',
          ),
        ),
      );
      expect(backends.onDemandEnabled, true);
      expect(backends.calls, isNot(contains('stop-proxy')));
      backends.failTunStop = false;

      expect((await host.stop()).status, VpnStatus.disconnected);
      expect(backends.onDemandEnabled, false);
    },
    skip: !AppPlatform.isMacOS,
  );

  test('Stop rechecks the other backend after the last observed backend becomes idle', () async {
    await backends.writeBoth();
    backends.preferredProxy = false;
    backends.tunStatus = VpnStatus.connected;
    final host = backends.host();
    expect(
      (await host.inspect(await host.readRuntime())).runtime!.isProxy,
      false,
    );
    backends.tunStatus = VpnStatus.disconnected;
    backends.proxyStatus = VpnStatus.connected;
    backends.calls.clear();

    await host.stop();

    expect(backends.calls, [
      'read-tun',
      'read-proxy',
      'stop-proxy',
      'read-tun',
      if (AppPlatform.isMacOS) 'stop-tun',
    ]);
  });

  test('coordinator protects the active TUN nodes while saved preference is proxy', () async {
    await backends.writeBoth();
    backends.preferredProxy = true;
    backends.tunStatus = VpnStatus.connected;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.connectionConfigDao.commit(
      configurationJson: backends.proxy.configuration.encode(),
    );
    final host = backends.host();
    final coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: host.readRuntime,
      inspect: host.inspect,
      stop: host.stop,
      probe: (_) async => null,
    );
    addTearDown(coordinator.dispose);

    await coordinator.initialize(observe: false, registerReferences: false);

    expect(coordinator.state.value.runtime!.identity, backends.tun.identity);
    expect((await coordinator.readReferences()).runningIds, {1});
    // Keep known active references in memory when its file disappears. The file
    // reader must not return an inactive proxy snapshot instead.
    await File(p.join(backends.directory.path, 'start.json')).delete();
    expect(await coordinator.readCurrentRuntime(), isNull);
    expect((await coordinator.readReferences()).runningIds, {1});
  });

  test(
    'both idle backends return disconnected without an obsolete runtime',
    () async {
      await backends.writeBoth();
      final host = backends.host();

      final current = await host.inspect(
        await host.readRuntime(),
        observedStatus: VpnStatus.connected,
      );

      expect(current.status, VpnStatus.disconnected);
      expect(current.runtime, isNull);
      expect(backends.calls, ['read-proxy', 'read-tun']);
    },
  );

  test(
    'a missing active TUN snapshot never borrows the inactive proxy identity',
    () async {
      await backends.write(true, backends.proxy);
      backends.tunStatus = VpnStatus.connected;
      final host = backends.host();
      final candidate = await host.readRuntime();
      expect(candidate!.isProxy, true);

      final current = await host.inspect(candidate);

      expect(current.status, VpnStatus.connected);
      expect(current.runtime, isNull);
      await backends.host().stop();
      expect(backends.calls, contains('stop-tun'));
      expect(backends.calls, isNot(contains('stop-proxy')));
    },
  );

  test('a removed active proxy snapshot never makes its reader return the old TUN request', () async {
    await backends.writeBoth();
    backends.proxyStatus = VpnStatus.connected;
    final host = backends.host();
    expect((await host.inspect(null)).runtime!.isProxy, true);
    await File(p.join(backends.directory.path, 'proxy-start.json')).delete();

    expect(await host.readRuntime(), isNull);
    final current = await host.inspect(null);

    expect(current.status, VpnStatus.connected);
    expect(current.runtime, isNull);
  });

  test('snapshot capture modes must match their file roles', () async {
    await backends.write(false, backends.proxy);
    await backends.write(true, backends.tun);
    backends.tunStatus = VpnStatus.connected;
    final host = backends.host();

    expect(await host.readRuntime(), isNull);
    final current = await host.inspect(null);

    expect(current.status, VpnStatus.connected);
    expect(current.runtime, isNull);
    await host.stop();
    expect(backends.calls.where((call) => call.startsWith('stop-')), [
      'stop-tun',
    ]);
  });

  test(
    'an old proxy request in start.json is ignored rather than migrated',
    () async {
      await backends.write(false, backends.proxy);
      final oldFile = File(p.join(backends.directory.path, 'start.json'));
      final oldBytes = await oldFile.readAsBytes();
      backends.proxyStatus = VpnStatus.connected;
      final host = backends.host();

      expect(await host.readRuntime(), isNull);
      final current = await host.inspect(
        null,
        observedStatus: VpnStatus.disconnected,
      );

      expect(current.status, VpnStatus.connected);
      expect(current.runtime, isNull);
      expect(await oldFile.readAsBytes(), oldBytes);
      expect(
        await File(p.join(backends.directory.path, 'proxy-start.json'))
            .exists(),
        false,
      );
    },
  );

  test(
    'a failed proxy status preserves its error but cannot block owned Stop',
    () async {
      await backends.writeBoth();
      backends.preferredProxy = false;
      backends.proxyFailure = NativeVpnCommandResult(
        state: NativeVpnCommandState.failed,
        message: 'Restore the changed bypass before stopping',
      );
      final host = backends.host();

      await expectLater(
        host.inspect(await host.readRuntime()),
        throwsA(
          isA<ConnectionHostException>().having(
            (error) => '${error.cause}',
            'cause',
            contains('changed bypass'),
          ),
        ),
      );
      backends.calls.clear();

      expect((await host.stop()).status, VpnStatus.disconnected);

      expect(backends.calls, [
        'read-tun',
        'read-proxy',
        'stop-proxy',
        'read-tun',
        if (AppPlatform.isMacOS) 'stop-tun',
      ]);
    },
  );

  test(
    'legacy TUN hosts accept missing captureMode and never query proxy',
    () async {
      final request = backends.tun.request.toJson()..remove('captureMode');
      await File(p.join(backends.directory.path, 'start.json'))
          .writeAsString(jsonEncode(request));
      await backends.write(true, backends.proxy);
      final host = ConnectionRuntimeHost(
        runDirectory: backends.directory.path,
        readStatus: () async => VpnStatus.connected,
        readProxyStatus: () async => fail('Legacy TUN must not query proxy'),
      );

      final runtime = await host.readRuntime();
      expect(runtime!.isProxy, false);
      expect(
        (await host.inspect(runtime)).runtime!.identity,
        backends.tun.identity,
      );
    },
  );
}
