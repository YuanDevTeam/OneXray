import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';

RuntimeOptions _options(
  ConnectionPlatform platform, {
  WindowsMode? mode,
  bool proxy = true,
}) => RuntimeOptions(
  platform: platform,
  windowsMode: mode,
  proxyMode: proxy,
  sessionDirectory: '/unused',
  metricsPort: 18081,
  socksPort: 10808,
  lanProxyEnabled: true,
  lanProxyPort: 11024,
);

final _node = ResolvedServer(
  id: 1,
  sourceId: 0,
  outbound: {'protocol': 'freedom'},
);

NativeVpnCommandResult _success(VpnStatus status) => NativeVpnCommandResult(
  state: NativeVpnCommandState.success,
  status: status,
);

ConnectionRuntime _runtime({bool proxy = true}) {
  final configuration = ConnectionConfiguration(
    policy: PlatformPolicy.fromJson({
      'captureMode': proxy ? 'proxy' : 'tun',
      'autoSetSystemProxy': proxy,
    }),
    connection: ConnectionSettings(trafficMode: TrafficMode.allVpn),
  );
  final compiled = ConnectionCompiler.compile(
    settings: configuration.connection,
    entries: [_node],
    regions: const RegionCatalog.empty(),
    options: _options(ConnectionPlatform.macos, proxy: proxy),
  );
  return ConnectionRuntime.create(
    configuration: configuration,
    compiled: compiled,
    platform: ConnectionPlatform.macos,
    request: StartVpnRequest(
      null,
      '10808',
      '18081',
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(compiled.xrayJson).toJson(),
        ).toJson(),
      ),
      captureMode: proxy ? 'proxy' : 'tun',
      autoSetSystemProxy: proxy,
    ),
  );
}

void main() {
  for (final platform in [
    ConnectionPlatform.macos,
    ConnectionPlatform.windows,
    ConnectionPlatform.linux,
  ]) {
    test(
      'proxy $platform compiles a private mixed listener without a network interface',
      () {
        final compiled = ConnectionCompiler.compile(
          settings: ConnectionSettings(trafficMode: TrafficMode.allVpn),
          entries: [_node],
          regions: const RegionCatalog.empty(),
          options: _options(platform),
        ).config;
        final inbounds = (compiled['inbounds'] as List).cast<Map>();
        final managed = inbounds.singleWhere(
          (value) => value['tag'] == 'tunIn',
        );
        expect(managed['protocol'], 'socks');
        expect(managed['listen'], '127.0.0.1');
        expect(managed['port'].toString(), '10808');
        expect(inbounds.any((value) => value['protocol'] == 'tun'), isFalse);
        final lan = inbounds.singleWhere(
          (value) => value['tag'] == 'app-lan-proxy',
        );
        expect(lan['listen'], '0.0.0.0');
        expect(lan['port'].toString(), '11024');
        for (final outbound in compiled['outbounds'] as List) {
          expect(outbound['streamSettings']?['sockopt']?['interface'], isNull);
        }
        expect(jsonEncode(compiled), isNot(contains('autoSystemWfpBlockLeak')));
        expect(jsonEncode(compiled), isNot(contains('autoSystemRoutingTable')));
      },
    );

    test('proxy $platform adapts Raw only in the runtime copy', () {
      final raw = <String, dynamic>{
        'dns': {
          'servers': ['1.1.1.1'],
        },
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
        'inbounds': [
          {
            'tag': 'tunIn',
            'protocol': 'tun',
            'settings': {'mtu': 1500},
          },
        ],
        'routing': {
          'rules': [
            {
              'inboundTag': ['tunIn'],
              'outboundTag': 'proxy',
            },
          ],
        },
      };
      final before = jsonEncode(raw);
      final compiled = ConnectionCompiler.compile(
        settings: ConnectionSettings(expert: true),
        entries: [],
        raw: raw,
        regions: const RegionCatalog.empty(),
        options: _options(platform),
      ).config;
      expect(jsonEncode(raw), before);
      final managed = (compiled['inbounds'] as List).singleWhere(
        (value) => value['tag'] == 'tunIn',
      );
      expect(managed['protocol'], 'socks');
      expect(managed['settings'], isNot(contains('mtu')));
      final rules = compiled['routing']['rules'] as List;
      expect(rules.last, (raw['routing'] as Map)['rules'].single);
      expect(rules.first['port'], '53');
      expect(rules.first['inboundTag'], ['tunIn']);
    });
  }

  test('provider graphs keep routes and stored input in proxy mode', () {
    final source = <String, dynamic>{
      'inbounds': [
        {'tag': 'provider', 'port': 8080, 'protocol': 'http'},
      ],
      'outbounds': [
        {'tag': 'exit', 'protocol': 'freedom'},
      ],
      'routing': {
        'rules': [
          {
            'inboundTag': ['provider'],
            'outboundTag': 'exit',
          },
        ],
      },
    };
    final before = jsonEncode(source);
    final compiled = ConnectionCompiler.compile(
      settings: ConnectionSettings(selection: const ServerSelection.server(99)),
      entries: [],
      profile: ResolvedProfile(
        id: 99,
        sourceId: 7,
        name: 'Provider',
        config: source,
      ),
      regions: const RegionCatalog.empty(),
      options: _options(ConnectionPlatform.macos),
    ).config;
    expect(jsonEncode(source), before);
    final managed = (compiled['inbounds'] as List).singleWhere(
      (value) => value['tag'] == 'tunIn',
    );
    expect(managed['protocol'], 'socks');
    expect(managed['listen'], '127.0.0.1');
    expect(managed['port'].toString(), '10808');
    final rules = compiled['routing']['rules'] as List;
    expect(rules.last['outboundTag'], 'exit');
    expect(rules.last['inboundTag'], ['provider', 'tunIn']);
    expect(jsonEncode(compiled), isNot(contains('autoSystemRoutingTable')));
  });

  test('advanced templates preserve their selection routes in proxy mode', () {
    final custom = AdvancedRoutingDocument.parse(
      AdvancedRoutingProfile.defaultText,
      name: 'Custom',
    ).state;
    final before = custom.encode();
    final compiled = ConnectionCompiler.compile(
      settings: ConnectionSettings(trafficMode: TrafficMode.custom),
      entries: [_node],
      custom: custom,
      regions: const RegionCatalog.empty(),
      options: _options(ConnectionPlatform.linux),
    ).config;
    expect(custom.encode(), before);
    final managed = (compiled['inbounds'] as List).singleWhere(
      (value) => value['tag'] == 'tunIn',
    );
    expect(managed['protocol'], 'socks');
    expect(managed['listen'], '127.0.0.1');
    expect(managed['port'].toString(), '10808');
    expect(managed['sniffing']['enabled'], true);
    expect(compiled['routing']['balancers'], isNotEmpty);
    expect(
      (compiled['routing']['rules'] as List).any(
        (value) => value['ruleTag'] == 'Forward DNS',
      ),
      isTrue,
    );
    expect(jsonEncode(compiled), isNot(contains('autoSystemRoutingTable')));
  });

  test(
    'MSIX proxy mode skips its VPN provider and still uses the same listener',
    () {
      final options = _options(
        ConnectionPlatform.windows,
        mode: WindowsMode.msix,
      );
      expect(options.usesWindowsSystemVpn, isFalse);
      expect(options.usesSocksInbound, isTrue);
    },
  );

  test(
    'old saved requests remain TUN and mode survives new runtime metadata',
    () {
      final old = StartVpnRequest.fromJson({'socksPort': '10808'});
      expect(old.captureMode, 'tun');
      expect(old.autoSetSystemProxy, isFalse);
      final runtime = _runtime();
      final restored = ConnectionRuntime.fromRequest(
        StartVpnRequest.fromJson(runtime.request.toJson()),
      );
      expect(restored.isProxy, isTrue);
      expect(restored.request.autoSetSystemProxy, isTrue);
      expect(restored.request.socksPort, '10808');
    },
  );

  test('mobile compilation cannot acquire desktop proxy capture', () {
    expect(() => _options(ConnectionPlatform.ios), throwsFormatException);
    expect(() => _options(ConnectionPlatform.android), throwsFormatException);
  });

  test(
    'proxy WireGuard uses its userspace stack without changing stored nodes',
    () {
      final node = ResolvedServer(
        id: 2,
        sourceId: 0,
        outbound: {
          'protocol': 'wireguard',
          'settings': {'secretKey': 'fixture', 'noKernelTun': false},
        },
      );
      final compiled = ConnectionCompiler.compile(
        settings: ConnectionSettings(trafficMode: TrafficMode.allVpn),
        entries: [node],
        regions: const RegionCatalog.empty(),
        options: _options(ConnectionPlatform.linux),
      ).config;
      expect(
        (compiled['outbounds'] as List).first['settings']['noKernelTun'],
        isTrue,
      );
      expect(node.outbound['settings']['noKernelTun'], isFalse);
    },
  );

  test(
    'Raw cannot explicitly request a kernel WireGuard TUN in proxy mode',
    () {
      final raw = <String, dynamic>{
        'outbounds': [
          {
            'protocol': 'wireguard',
            'settings': {'noKernelTun': false},
          },
        ],
      };
      expect(
        () => ConnectionCompiler.compile(
          settings: ConnectionSettings(expert: true),
          entries: [],
          raw: raw,
          regions: const RegionCatalog.empty(),
          options: _options(ConnectionPlatform.linux),
        ),
        throwsFormatException,
      );
      expect(
        (raw['outbounds'] as List).first['settings']['noKernelTun'],
        isFalse,
      );
    },
  );

  test(
    'proxy start, stop and status use their own host and ignore NE status',
    () async {
      final runtime = _runtime();
      final calls = <String>[];
      var status = VpnStatus.disconnected;
      final host = ConnectionRuntimeHost(
        writeStartFile: (_) async => calls.add('write'),
        prefersProxy: () async => true,
        startProxy: (value) async {
          calls.add('proxy-start');
          expect(value.request.autoSetSystemProxy, isTrue);
          status = VpnStatus.connected;
          return _success(status);
        },
        stopProxy: () async {
          calls.add('proxy-stop');
          status = VpnStatus.disconnected;
          return _success(status);
        },
        readProxyStatus: () async => _success(status),
      );
      expect((await host.start(runtime)).connected, isTrue);
      expect(
        (await host.inspect(
          runtime,
          observedStatus: VpnStatus.disconnected,
        )).connected,
        isTrue,
      );
      expect((await host.stop()).status, VpnStatus.disconnected);
      expect(calls, ['write', 'proxy-start', 'proxy-stop']);
    },
  );

  test('proxy restore failure keeps the session retryable', () async {
    final runtime = _runtime();
    final host = ConnectionRuntimeHost(
      writeStartFile: (_) async {},
      prefersProxy: () async => true,
      startProxy: (_) async => _success(VpnStatus.connected),
      stopProxy: () async => NativeVpnCommandResult(
        state: NativeVpnCommandState.failed,
        status: VpnStatus.connected,
        message: 'restore failed',
      ),
      readProxyStatus: () async => _success(VpnStatus.connected),
    );
    await host.start(runtime);
    await expectLater(host.stop(), throwsA(isA<ConnectionHostException>()));
    expect((await host.inspect(runtime)).connected, isTrue);
  });

  test(
    'an active cached TUN session takes precedence over a proxy preference',
    () async {
      final tun = _runtime(proxy: false);
      var nativeReads = 0;
      final host = ConnectionRuntimeHost(
        prefersProxy: () async => true,
        readStatus: () async {
          nativeReads++;
          return VpnStatus.connected;
        },
        readProxyStatus: () async => fail('Do not hide an active TUN session'),
      );
      final observed = await host.inspect(tun);
      expect(observed.connected, isTrue);
      expect(observed.runtime?.isProxy, isFalse);
      expect(nativeReads, 1);
    },
  );

  test('a disconnected cached TUN request switches inspection to the proxy preference', () async {
    var proxyReads = 0;
    final host = ConnectionRuntimeHost(
      prefersProxy: () async => true,
      readStatus: () async => VpnStatus.disconnected,
      readProxyStatus: () async {
        proxyReads++;
        return _success(VpnStatus.disconnected);
      },
    );
    final observed = await host.inspect(_runtime(proxy: false));
    expect(observed.runtime, isNull);
    expect(proxyReads, 1);
  });
}
