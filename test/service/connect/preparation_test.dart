import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/advanced/local_api/settings.dart';
import 'package:onexray/service/connect/preparation.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retries allocations that overlap Raw inbound ranges', () async {
    final candidates = [
      [11000, 12001],
      [14000, 13000],
      [11000, 13000],
    ];
    var attempts = 0;
    final ports = await allocateRuntimePorts(
      [
        {'port': '12000-12010,14000'},
      ],
      getFreePorts: (count, {excludePorts}) async {
        expect(count, 2);
        expect(excludePorts, isNull);
        return candidates[attempts++];
      },
    );

    expect(attempts, 3);
    expect(ports, [11000, 13000]);
  });

  for (final apiPort in [LocalApiSettings.defaultPort, 19587]) {
    test('excludes HTTP API port $apiPort from both runtime ports', () async {
      final candidates = [
        [11000, 12001],
        [11000, 13000],
      ];
      var attempts = 0;
      final ports = await allocateRuntimePorts(
        [
          {'port': '12000-12010'},
        ],
        excludePorts: [apiPort],
        getFreePorts: (count, {excludePorts}) async {
          expect(count, 2);
          expect(excludePorts, [apiPort]);
          return candidates[attempts++];
        },
      );

      expect(attempts, 2);
      expect(ports, [11000, 13000]);
    });
  }

  test(
    'keeps API and enabled LAN sharing ports out of runtime allocation',
    () async {
      final ports = await allocateRuntimePorts(
        const [],
        excludePorts: [LocalApiSettings.defaultPort, 11024],
        getFreePorts: (count, {excludePorts}) async {
          expect(count, 2);
          expect(excludePorts, [LocalApiSettings.defaultPort, 11024]);
          return [12001, 13000];
        },
      );
      expect(ports, [12001, 13000]);
    },
  );

  test(
    'preserves allocator failures without retrying invalid responses',
    () async {
      await expectLater(
        allocateRuntimePorts(
          const [],
          excludePorts: [LocalApiSettings.defaultPort],
          getFreePorts: (count, {excludePorts}) async {
            expect(count, 2);
            expect(excludePorts, [LocalApiSettings.defaultPort]);
            throw const FormatException('Invalid free ports response');
          },
        ),
        throwsFormatException,
      );
    },
  );

  test('stops after five unavailable runtime port groups', () async {
    var attempts = 0;
    await expectLater(
      allocateRuntimePorts(
        const [
          {'port': '11000-11010'},
        ],
        getFreePorts: (count, {excludePorts}) async {
          expect(count, 2);
          attempts++;
          return [11000, 13000];
        },
      ),
      throwsFormatException,
    );
    expect(attempts, 5);
  });

  group('provider configuration preparation', () {
    late AppDatabase db;
    late SubscriptionData source;
    late CoreConfigData profile;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final directory = await Directory.systemTemp.createTemp(
        'onexray-provider-preparation-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.onexray.BridgeHostApi.getTunFilesDir',
        BridgeHostApi.pigeonChannelCodec,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockDecodedMessageHandler(
        channel,
        (_) async => [directory.path],
      );
      addTearDown(() => messenger.setMockDecodedMessageHandler(channel, null));
      await AppHostApi().initTunFilesDir();
      final sourceId = await db.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: 'Provider',
          url: 'https://example.com/subscription',
          timestamp: DateTime(2026, 10, 12),
          mode: Value(SubscriptionMode.providerManaged.name),
        ),
      );
      source = (await db.subscriptionDao.searchRow(sourceId))!;
      final id = await db.coreConfigDao.insertRow(
        CoreConfigCompanion.insert(
          name: 'Provider profile',
          type: CoreConfigType.Remnawave.name,
          tags: '',
          delay: PingDelayConstants.unknown,
          subId: sourceId,
          data: Value(base64Encode(utf8.encode(jsonEncode(_providerConfig)))),
        ),
      );
      profile = (await db.coreConfigDao.searchRow(id))!;
    });

    for (final mode in [TrafficMode.smart, TrafficMode.custom]) {
      test(
        'fixed provider bypasses $mode routing, probes and final exit',
        () async {
          final resolved = <Set<int>>[];
          final input = _providerInput(profile.id, trafficMode: mode);
          final runtime = await _providerPreparation(db)
              .prepare(input, onResolved: (ids) => resolved.add(ids));

          expect(runtime.configuration.encode(), input.encode());
          expect(runtime.configuration.connection.expert, isFalse);
          expect(runtime.entries, isEmpty);
          expect(runtime.finalExit, isNull);
          expect(runtime.notice, isNull);
          expect(runtime.profile?.id, profile.id);
          expect(runtime.profile?.sourceId, source.id);
          expect(runtime.profile?.type, CoreConfigType.Remnawave.name);
          expect(runtime.nodeIds, {profile.id});
          expect(resolved, isNotEmpty);
          expect(
            resolved.every(
              (ids) => ids.length == 1 && ids.contains(profile.id),
            ),
            isTrue,
          );
          expect(
            (await db.coreConfigDao.searchRow(profile.id))!.data,
            profile.data,
          );
        },
      );
    }

    test('reports the provider before allocation so refresh keeps its original row', () async {
      final protectedIds = <int>{};
      var refreshed = false;
      final preparation = ConnectionPreparation(
        db: db,
        resolver: _unavailableResolver(),
        getFreePorts: (count, {excludePorts}) async {
          expect(protectedIds, {profile.id});
          await db.subscriptionDao.deleteConfigs(
            source.id,
            protectedIds: protectedIds,
          );
          await db.coreConfigDao.insertRow(
            CoreConfigCompanion.insert(
              name: 'New provider profile',
              type: CoreConfigType.Remnawave.name,
              tags: '',
              delay: PingDelayConstants.unknown,
              subId: source.id,
              data: Value(profile.data),
            ),
          );
          refreshed = true;
          return [18002, 18003];
        },
        requireDependencies: (_) async {},
      );
      final runtime = await preparation.prepare(
        _providerInput(profile.id),
        onResolved: protectedIds.addAll,
      );

      expect(refreshed, isTrue);
      expect(runtime.profile?.id, profile.id);
      expect(await db.coreConfigDao.searchRow(profile.id), profile);
      expect(await db.coreConfigDao.allActiveServerRows(), hasLength(2));
    });

    test(
      'rejects an inactive provider and a provider source selection',
      () async {
        await db.subscriptionDao.updateRow(
          source.copyWith(mode: SubscriptionMode.appManaged.name),
        );
        await expectLater(
          _providerPreparation(db).prepare(_providerInput(profile.id)),
          throwsFormatException,
        );
        await db.subscriptionDao.updateRow(source);
        await expectLater(
          _providerPreparation(db).prepare(
            ConnectionConfiguration(
              connection: ConnectionSettings(
                selection: ServerSelection.source(source.id),
              ),
            ),
          ),
          throwsFormatException,
        );
      },
    );

    test('a missing fixed configuration remains a selection error', () async {
      await expectLater(
        _providerPreparation(db).prepare(_providerInput(profile.id + 100)),
        throwsA(
          isA<ConnectionResolutionException>().having(
            (error) => error.reason,
            'reason',
            ConnectionResolutionFailure.selectionUnavailable,
          ),
        ),
      );
    });

    test(
      'manual source selection does not require a subscription row',
      () async {
        final id = await db.coreConfigDao.insertRow(
          CoreConfigCompanion.insert(
            name: 'Manual proxy',
            type: CoreConfigType.outbound.name,
            tags: '',
            subId: 0,
            delay: 30,
            data: Value(
              base64Encode(
                utf8.encode(
                  jsonEncode({
                    'outbounds': [
                      {
                        'tag': 'Manual proxy',
                        'protocol': 'socks',
                        'settings': {
                          'servers': [
                            {'address': '127.0.0.1', 'port': 1080},
                          ],
                        },
                      },
                    ],
                  }),
                ),
              ),
            ),
          ),
        );
        expect(await db.subscriptionDao.searchRow(0), isNull);
        final runtime =
            await ConnectionPreparation(
              db: db,
              getFreePorts: (count, {excludePorts}) async => [18002, 18003],
              requireDependencies: (_) async {},
            ).prepare(
              ConnectionConfiguration(
                connection: ConnectionSettings(
                  selection: const ServerSelection.source(0),
                  trafficMode: TrafficMode.allVpn,
                ),
              ),
            );
        expect(runtime.entries.single.id, id);
        expect(runtime.profile, isNull);
        expect(
          runtime.configuration.connection.selection,
          const ServerSelection.source(0),
        );
      },
    );

    for (final change in ['mode', 'row']) {
      test(
        'rejects a provider $change change while dependencies are checked',
        () async {
          final checking = Completer<void>();
          final finish = Completer<void>();
          final preparing = _providerPreparation(
            db,
            requireDependencies: (_) async {
              checking.complete();
              await finish.future;
            },
          ).prepare(_providerInput(profile.id));
          await checking.future;
          final rejected = expectLater(preparing, throwsFormatException);
          try {
            if (change == 'mode') {
              await db.subscriptionDao.updateRow(
                source.copyWith(mode: SubscriptionMode.appManaged.name),
              );
            } else {
              await db.subscriptionDao.deleteRow(source.id);
            }
          } finally {
            finish.complete();
          }
          await rejected;
        },
      );
    }
  }, skip: !(Platform.isMacOS || Platform.isIOS || Platform.isAndroid));
}

ConnectionPreparation _providerPreparation(
  AppDatabase db, {
  Future<void> Function(Map<String, GeoDataType>)? requireDependencies,
}) => ConnectionPreparation(
  db: db,
  resolver: _unavailableResolver(),
  getFreePorts: (count, {excludePorts}) async => [18002, 18003],
  requireDependencies: requireDependencies ?? (_) async {},
);

ConnectionResolver _unavailableResolver() => ConnectionResolver(
  rows: () =>
      Stream.error(StateError('Provider selection must bypass ordinary nodes')),
  probe: (_) async =>
      throw StateError('Provider configuration must not be probed'),
);

ConnectionConfiguration _providerInput(
  int id, {
  TrafficMode trafficMode = TrafficMode.smart,
}) => ConnectionConfiguration(
  connection: ConnectionSettings(
    selection: ServerSelection.server(id),
    trafficMode: trafficMode,
    customId: 987654,
    smart: SmartRoutingSettings(
      entryCount: 3,
      finalExitId: 987655,
      directRegions: const ['CN'],
      fragment: true,
    ),
  ),
);

const _providerConfig = <String, dynamic>{
  'inbounds': [
    {
      'tag': 'provider-socks',
      'protocol': 'socks',
      'port': 1080,
      'listen': '127.0.0.1',
      'sniffing': {
        'enabled': true,
        'destOverride': ['http', 'tls'],
        'routeOnly': true,
      },
    },
  ],
  'outbounds': [
    {'tag': 'provider-proxy', 'protocol': 'freedom'},
  ],
  'dns': {
    'servers': ['8.8.8.8'],
  },
  'routing': {
    'rules': [
      {
        'type': 'field',
        'inboundTag': ['provider-socks'],
        'domain': ['domain:example.net'],
        'outboundTag': 'provider-proxy',
      },
    ],
  },
};
