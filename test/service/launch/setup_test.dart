import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/launch/setup.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late PreferencesKey preferences;
  late SetupService setup;
  var failLocal = false;
  var failSave = false;
  var writes = 0;

  setUpAll(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  setUp(() async {
    await SharedPreferencesAsync().clear();
    preferences = PreferencesKey();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    failLocal = false;
    failSave = false;
    writes = 0;
    setup = SetupService(
      database: db,
      platform: ConnectionPlatform.ios,
      prepareLocal: () async {
        if (failLocal) throw const SetupFailure('local');
      },
      readRegionCodes: () async => ['CN', 'RU', 'US'],
      saveConfiguration: (value) async {
        if (failSave) throw StateError('Cannot save');
        writes++;
        await db.connectionConfigDao.commit(configurationJson: value.encode());
      },
    );
  });

  test('privacy and one configuration step finish without servers or VPN API', () async {
    expect(await setup.currentStep(), SetupStep.welcome);
    await setup.acceptPrivacy();
    await setup.prepareLocal();
    expect(await setup.currentStep(), SetupStep.configuration);
    expect(await preferences.readFirstRun(), isTrue);
    expect(writes, 0);

    // No native API is mocked: any permission/start call would fail this test.
    expect(await db.coreConfigDao.watchHasOutbounds().first, isFalse);
    await setup.finish(interfaceName: '', regions: ['RU']);
    expect(await setup.currentStep(), SetupStep.complete);
    expect(await preferences.readFirstRun(), isFalse);
    expect(writes, 1);
    expect((await setup.configuration()).connection.smart.directRegions, [
      'RU',
    ]);
    expect(
      (await setup.configuration()).connection.selection.kind,
      SelectionKind.automatic,
    );
  });

  test('local preparation or save failure keeps setup incomplete', () async {
    await setup.acceptPrivacy();
    failLocal = true;
    await expectLater(
      setup.finish(interfaceName: ''),
      throwsA(isA<SetupFailure>()),
    );
    expect(writes, 0);
    failLocal = false;
    failSave = true;
    await expectLater(setup.finish(interfaceName: ''), throwsStateError);
    expect(await preferences.readFirstRun(), isTrue);
    expect(await setup.currentStep(), SetupStep.configuration);
    failSave = false;
    await setup.finish(interfaceName: '');
    expect(await setup.currentStep(), SetupStep.complete);
  });

  for (final regions in <List<String>?>[
    null,
    [],
    ['RU'],
  ]) {
    test('region choice $regions preserves unrelated settings', () async {
      final previous = ConnectionConfiguration(
        connection: ConnectionSettings(expert: true, rawId: 7),
        policy: PlatformPolicy.fromJson({'xrayOutboundInterfaceName': 'saved'}),
      );
      await db.connectionConfigDao.commit(configurationJson: previous.encode());
      await setup.acceptPrivacy();
      await setup.finish(interfaceName: '', regions: regions);
      final saved = await setup.configuration();
      expect(
        saved.connection.smart.directRegions,
        regions ?? previous.connection.smart.directRegions,
      );
      expect(saved.connection.expert, isTrue);
      expect(saved.connection.rawId, 7);
      expect(saved.policy.toJson(), previous.policy.toJson());
    });
  }

  for (final platform in [
    ConnectionPlatform.macos,
    ConnectionPlatform.windows,
    ConnectionPlatform.linux,
  ]) {
    test(
      '$platform proxy Setup preserves interface draft without querying it',
      () async {
        final service = _ProxySetup(database: db, platform: platform);
        final previous = ConnectionConfiguration(
          connection: ConnectionSettings(),
          policy: PlatformPolicy.fromJson({
            'xrayOutboundInterfaceName': 'saved-interface',
          }),
        );
        await db.connectionConfigDao.commit(
          configurationJson: previous.encode(),
        );
        await service.acceptPrivacy();
        await service.finish(interfaceName: '', captureMode: CaptureMode.proxy);
        final saved = await service.configuration();
        expect(saved.policy.captureMode, CaptureMode.proxy);
        expect(saved.policy.proxyPort, 10808);
        expect(saved.policy.xrayOutboundInterfaceName, 'saved-interface');
        expect(await service.currentStep(), SetupStep.complete);
      },
    );
  }

  for (final platform in ConnectionPlatform.values) {
    test(
      '$platform saves interface and region together without permissions',
      () async {
        final service = _InterfaceSetup(database: db, platform: platform);
        await service.acceptPrivacy();
        if (service.requiresInterface) {
          for (final name in ['', 'missing']) {
            await expectLater(
              service.finish(interfaceName: name, regions: ['RU']),
              throwsA(isA<SetupFailure>()),
            );
            expect(await preferences.readFirstRun(), isTrue);
            expect(
              (await service.configuration()).policy.xrayOutboundInterfaceName,
              '',
            );
          }
        }
        await service.finish(
          interfaceName: service.requiresInterface ? 'Ethernet' : '',
          regions: ['RU'],
        );
        final saved = await service.configuration();
        expect(
          saved.policy.xrayOutboundInterfaceName,
          service.requiresInterface ? 'Ethernet' : '',
        );
        expect(saved.connection.smart.directRegions, ['RU']);
        expect(await service.currentStep(), SetupStep.complete);
      },
    );
  }

  for (final failure in <Object>[
    const SocketException('Failed host lookup'),
    TimeoutException('Region suggestion timed out'),
    const FormatException('Invalid region response'),
  ]) {
    test(
      'region lookup failure does not prevent finishing: $failure',
      () async {
        await setup.acceptPrivacy();
        final suggested = await HttpOverrides.runZoned(
          setup.suggestRegion,
          createHttpClient: (_) => _FailingHttpClient(failure),
        );
        expect(suggested, isNull);
        await setup.finish(interfaceName: '');
        expect(await setup.currentStep(), SetupStep.complete);
      },
    );
  }
}

class _InterfaceSetup extends SetupService {
  _InterfaceSetup({required super.database, required super.platform})
    : super(
        prepareLocal: () async {},
        readRegionCodes: () async => ['CN', 'RU'],
      );

  @override
  Future<List<OutboundInterfaceOption>> interfaces() async => [
    const OutboundInterfaceOption('Ethernet', ['192.0.2.2'], true),
  ];
}

class _ProxySetup extends SetupService {
  _ProxySetup({required super.database, required super.platform})
    : super(
        prepareLocal: () async {},
        readRegionCodes: () async => ['CN', 'RU'],
      );

  @override
  Future<List<OutboundInterfaceOption>> interfaces() =>
      throw StateError('Proxy must not query interfaces');
}

class _FailingHttpClient implements HttpClient {
  final Object failure;
  _FailingHttpClient(this.failure);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getUrl) {
      return Future<HttpClientRequest>.error(failure);
    }
    if (invocation.memberName == const Symbol('connectionTimeout=') ||
        invocation.memberName == const Symbol('findProxy=') ||
        invocation.memberName == #close) {
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}
