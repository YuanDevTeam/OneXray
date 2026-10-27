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
import 'package:onexray/service/advanced/local_api/service.dart';
import 'package:onexray/service/advanced/local_api/settings.dart';
import 'package:onexray/service/connect/preparation.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
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

    Future<void> saveInbound(Map<String, dynamic> inbound) async {
      final config = {
        ..._providerConfig,
        'inbounds': [inbound],
      };
      profile = profile.copyWith(
        data: Value(base64Encode(utf8.encode(jsonEncode(config)))),
      );
      await db.coreConfigDao.updateRow(profile);
    }

    group('HTTP API inbound conflicts', () {
      for (final collision in [
        (name: 'same port', port: 18587, listen: '127.0.0.1'),
        (name: 'port range', port: '18580-18590', listen: '127.0.0.1'),
        (name: 'wildcard address', port: 18587, listen: '0.0.0.0'),
        (name: 'default address', port: 18587, listen: null),
        (name: 'localhost address', port: 18587, listen: 'localhost'),
        (name: 'trimmed localhost address', port: 18587, listen: ' localhost '),
        (name: 'dual-stack wildcard', port: 18587, listen: '::'),
        (name: 'bracketed IPv6 wildcard', port: 18587, listen: '[::]'),
        (name: 'mapped IPv4 loopback', port: 18587, listen: '::ffff:127.0.0.1'),
      ]) {
        test('rejects provider ${collision.name} before allocation', () async {
          final api = _localApi(enabled: true);
          addTearDown(api.stop);
          await saveInbound({
            'tag': 'provider-socks',
            'protocol': 'socks',
            'port': collision.port,
            if (collision.listen != null) 'listen': collision.listen,
          });
          var allocated = false;
          var dependenciesChecked = false;
          await expectLater(
            _providerPreparation(
              db,
              localApi: api,
              getFreePorts: (count, {excludePorts}) async {
                allocated = true;
                return [18002, 18003];
              },
              requireDependencies: (_) async => dependenciesChecked = true,
            ).prepare(_providerInput(profile.id)),
            _throwsApiConflict,
          );
          expect(allocated, isFalse);
          expect(dependenciesChecked, isFalse);
          expect(
            (await db.coreConfigDao.searchRow(profile.id))!.data,
            profile.data,
          );
        });
      }

      test('rejects a provider port occupied by a listening API', () async {
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = socket.port;
        await socket.close();
        final api = _localApi(enabled: true, port: port);
        addTearDown(api.stop);
        await api.start();
        expect(api.listening, isTrue);
        await saveInbound({
          'tag': 'provider-socks',
          'protocol': 'socks',
          'port': port,
          'listen': '127.0.0.1',
        });
        await expectLater(
          _providerPreparation(
            db,
            localApi: api,
          ).prepare(_providerInput(profile.id)),
          _throwsApiConflict,
        );
        expect(api.listening, isTrue);
        expect(
          (await db.coreConfigDao.searchRow(profile.id))!.data,
          profile.data,
        );
      });

      for (final allowed in [
        (
          name: 'another API port',
          enabled: true,
          apiPort: 19587,
          listen: '127.0.0.1',
        ),
        (
          name: 'disabled API',
          enabled: false,
          apiPort: 18587,
          listen: '127.0.0.1',
        ),
        (
          name: 'another IPv4 address',
          enabled: true,
          apiPort: 18587,
          listen: '127.0.0.2',
        ),
        (name: 'IPv6 loopback', enabled: true, apiPort: 18587, listen: '::1'),
        (
          name: 'Unix socket',
          enabled: true,
          apiPort: 18587,
          listen: '/tmp/onexray-provider.sock',
        ),
      ]) {
        test('preserves provider inbound with ${allowed.name}', () async {
          final api = _localApi(
            enabled: allowed.enabled,
            port: allowed.apiPort,
          );
          addTearDown(api.stop);
          final inbound = {
            'tag': 'provider-socks',
            'protocol': 'socks',
            'port': 18587,
            'listen': allowed.listen,
          };
          await saveInbound(inbound);
          final runtime = await _providerPreparation(
            db,
            localApi: api,
            getFreePorts: (count, {excludePorts}) async {
              expect(excludePorts, contains(allowed.apiPort));
              return [18002, 18003];
            },
          ).prepare(_providerInput(profile.id));
          final compiled = jsonDecode(runtime.xrayJson) as Map<String, dynamic>;
          expect(
            (compiled['inbounds'] as List).singleWhere(
              (value) => value['tag'] == inbound['tag'],
            ),
            inbound,
          );
          expect(
            (await db.coreConfigDao.searchRow(profile.id))!.data,
            profile.data,
          );
        });
      }

      test('preserves a UDP-only provider listener at the API port', () async {
        final api = _localApi(enabled: true);
        addTearDown(api.stop);
        final inbound = {
          'tag': 'provider-udp',
          'protocol': 'tunnel',
          'port': 18587,
          'listen': '127.0.0.1',
          'settings': {
            'allowedNetwork': 'udp',
            'rewriteAddress': '8.8.8.8',
            'rewritePort': 53,
          },
        };
        await saveInbound(inbound);
        final runtime = await _providerPreparation(
          db,
          localApi: api,
        ).prepare(_providerInput(profile.id));
        final compiled = jsonDecode(runtime.xrayJson) as Map<String, dynamic>;
        expect(
          (compiled['inbounds'] as List).singleWhere(
            (value) => value['tag'] == inbound['tag'],
          ),
          inbound,
        );
      });

      test('preserves a UDP transport listener at the API port', () async {
        final api = _localApi(enabled: true);
        addTearDown(api.stop);
        final inbound = {
          'tag': 'provider-socks',
          'protocol': 'socks',
          'port': 18587,
          'listen': '127.0.0.1',
          'streamSettings': {'network': 'kcp'},
        };
        await saveInbound(inbound);
        final runtime = await _providerPreparation(
          db,
          localApi: api,
        ).prepare(_providerInput(profile.id));
        final compiled = jsonDecode(runtime.xrayJson) as Map<String, dynamic>;
        expect(
          (compiled['inbounds'] as List).singleWhere(
            (value) => value['tag'] == inbound['tag'],
          ),
          inbound,
        );
      });

      for (final transport in ['xhttp', 'masque']) {
        test(
          'preserves an HTTP/3-only $transport listener at the API port',
          () async {
            final api = _localApi(enabled: true);
            addTearDown(api.stop);
            final inbound = {
              'tag': 'provider-socks',
              'protocol': 'socks',
              'port': 18587,
              'listen': '127.0.0.1',
              'streamSettings': {
                'network': transport,
                'security': 'TLS',
                'tlsSettings': {
                  'alpn': ['h3'],
                },
              },
            };
            await saveInbound(inbound);
            final runtime = await _providerPreparation(
              db,
              localApi: api,
            ).prepare(_providerInput(profile.id));
            final compiled =
                jsonDecode(runtime.xrayJson) as Map<String, dynamic>;
            expect(
              (compiled['inbounds'] as List).singleWhere(
                (value) => value['tag'] == inbound['tag'],
              ),
              inbound,
            );
          },
        );
      }

      test(
        'preserves MASQUE default UDP-only listening at the API port',
        () async {
          final api = _localApi(enabled: true);
          addTearDown(api.stop);
          final inbound = {
            'tag': 'provider-socks',
            'protocol': 'socks',
            'port': 18587,
            'listen': '127.0.0.1',
            'streamSettings': {'network': 'masque', 'security': 'tls'},
          };
          await saveInbound(inbound);
          final runtime = await _providerPreparation(
            db,
            localApi: api,
          ).prepare(_providerInput(profile.id));
          final compiled = jsonDecode(runtime.xrayJson) as Map<String, dynamic>;
          expect(
            (compiled['inbounds'] as List).singleWhere(
              (value) => value['tag'] == inbound['tag'],
            ),
            inbound,
          );
        },
      );

      test('rejects MASQUE TCP listening even with HTTP/3 enabled', () async {
        final api = _localApi(enabled: true);
        addTearDown(api.stop);
        await saveInbound({
          'tag': 'provider-socks',
          'protocol': 'socks',
          'port': 18587,
          'listen': '127.0.0.1',
          'streamSettings': {
            'network': 'masque',
            'security': 'tls',
            'tlsSettings': {
              'alpn': ['h3', 'h2'],
            },
          },
        });
        await expectLater(
          _providerPreparation(
            db,
            localApi: api,
          ).prepare(_providerInput(profile.id)),
          _throwsApiConflict,
        );
      });

      test('an empty Shadowsocks network list still defaults to TCP', () async {
        final api = _localApi(enabled: true);
        addTearDown(api.stop);
        await saveInbound({
          'tag': 'provider-shadowsocks',
          'protocol': 'shadowsocks',
          'port': 18587,
          'listen': '127.0.0.1',
          'settings': {
            'method': 'aes-128-gcm',
            'password': 'test-password',
            'network': <String>[],
          },
        });
        await expectLater(
          _providerPreparation(
            db,
            localApi: api,
          ).prepare(_providerInput(profile.id)),
          _throwsApiConflict,
        );
      });

      for (final override in [
        (method: 'tcp', network: 'kcp', conflicts: true),
        (method: 'kcp', network: 'tcp', conflicts: false),
      ]) {
        test(
          'transport method ${override.method} overrides network ${override.network}',
          () async {
            final api = _localApi(enabled: true);
            addTearDown(api.stop);
            await saveInbound({
              'tag': 'provider-socks',
              'protocol': 'socks',
              'port': 18587,
              'listen': '127.0.0.1',
              'streamSettings': {
                'method': override.method,
                'network': override.network,
              },
            });
            final preparing = _providerPreparation(
              db,
              localApi: api,
            ).prepare(_providerInput(profile.id));
            if (override.conflicts) {
              await expectLater(preparing, _throwsApiConflict);
            } else {
              expect((await preparing).profile?.id, profile.id);
            }
          },
        );
      }

      test(
        'preserves an IPv6-only wildcard listener at the API port',
        () async {
          final api = _localApi(enabled: true);
          addTearDown(api.stop);
          final inbound = {
            'tag': 'provider-socks',
            'protocol': 'socks',
            'port': 18587,
            'listen': '::',
            'streamSettings': {
              'sockopt': {'v6only': true},
            },
          };
          await saveInbound(inbound);
          final runtime = await _providerPreparation(
            db,
            localApi: api,
          ).prepare(_providerInput(profile.id));
          final compiled = jsonDecode(runtime.xrayJson) as Map<String, dynamic>;
          expect(
            (compiled['inbounds'] as List).singleWhere(
              (value) => value['tag'] == inbound['tag'],
            ),
            inbound,
          );
        },
      );

      test(
        'API preference read failures keep the default reservation',
        () async {
          final api = LocalApiService.forTesting(
            readSettings: () async =>
                throw StateError('Preferences unavailable'),
            writeSettings: (_) async {},
            info: () async => {},
            validate: (_) async => {},
            compile: (_) async => {},
          );
          addTearDown(api.stop);
          await saveInbound({
            'tag': 'provider-socks',
            'protocol': 'socks',
            'port': 18587,
            'listen': '127.0.0.1',
          });
          final runtime = await _providerPreparation(
            db,
            localApi: api,
            getFreePorts: (count, {excludePorts}) async {
              expect(excludePorts, contains(LocalApiSettings.defaultPort));
              return [18002, 18003];
            },
          ).prepare(_providerInput(profile.id));
          expect(runtime.profile?.id, profile.id);
        },
      );

      test('rejects a personal Raw inbound at the enabled API port', () async {
        final api = _localApi(enabled: true);
        addTearDown(api.stop);
        await expectLater(
          _providerPreparation(db, localApi: api).prepare(
            ConnectionConfiguration(
              connection: ConnectionSettings(expert: true),
            ),
            rawDraft: jsonEncode({
              'inbounds': [
                {'tag': 'raw-http', 'protocol': 'http', 'port': '18580-18590'},
              ],
              'outbounds': [
                {'tag': 'direct', 'protocol': 'freedom'},
              ],
            }),
          ),
          _throwsApiConflict,
        );
      });

      test(
        'rejects an advanced custom inbound at the enabled API port',
        () async {
          final api = _localApi(enabled: true);
          addTearDown(api.stop);
          final id = await db.coreConfigDao.insertRow(
            CoreConfigCompanion.insert(
              name: 'Custom proxy',
              type: CoreConfigType.outbound.name,
              tags: '',
              delay: 30,
              subId: 0,
              data: Value(
                base64Encode(
                  utf8.encode(
                    jsonEncode({
                      'outbounds': [
                        {'tag': 'proxy', 'protocol': 'freedom'},
                      ],
                    }),
                  ),
                ),
              ),
            ),
          );
          await expectLater(
            ConnectionPreparation(
              db: db,
              localApi: api,
              getFreePorts: (count, {excludePorts}) async => [18002, 18003],
              requireDependencies: (_) async {},
            ).prepare(
              ConnectionConfiguration(
                connection: ConnectionSettings(
                  selection: ServerSelection.server(id),
                  trafficMode: TrafficMode.custom,
                ),
              ),
              customDraft: AdvancedRoutingDocument.fromJson({
                'outbounds': [<String, dynamic>{}],
                'inbounds': [
                  {'tag': 'custom-http', 'protocol': 'http', 'port': 18587},
                ],
              }).state,
            ),
            _throwsApiConflict,
          );
        },
      );
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

    for (final scoped in [false, true]) {
      for (final mode in [TrafficMode.smart, TrafficMode.custom]) {
        test(
          'automatic provider fallback preserves $mode and source scope $scoped',
          () async {
            final original = _providerInput(profile.id, trafficMode: mode);
            final input = ConnectionConfiguration(
              connection: ConnectionSettings.fromJson({
                ...original.connection.toJson(),
                'selection':
                    (scoped
                            ? ServerSelection.source(source.id)
                            : const ServerSelection.automatic())
                        .toJson(),
              }),
              policy: original.policy,
            );
            final protected = <int>{};
            final runtime =
                await ConnectionPreparation(
                  db: db,
                  getFreePorts: (count, {excludePorts}) async {
                    expect(protected, {profile.id});
                    return [18002, 18003];
                  },
                  requireDependencies: (_) async {},
                ).prepare(
                  input,
                  customDraft: mode == TrafficMode.custom
                      ? RoutingProfileState(
                          name: 'Preserved route',
                          entryCount: 3,
                        )
                      : null,
                  onResolved: protected.addAll,
                );
            expect(runtime.configuration.encode(), input.encode());
            expect(runtime.profile?.id, profile.id);
            expect(runtime.profile?.sourceId, source.id);
            expect(runtime.entries, isEmpty);
            expect(runtime.finalExit, isNull);
            expect(runtime.notice, isNull);
            expect(runtime.nodeIds, {profile.id});
            expect(runtime.profile?.type, CoreConfigType.Remnawave.name);
            final restored = ConnectionRuntime.fromRequest(runtime.request);
            expect(restored.configuration.encode(), input.encode());
            expect(restored.profile?.id, profile.id);
            expect(restored.nodeIds, {profile.id});
            final compiled =
                jsonDecode(runtime.xrayJson) as Map<String, dynamic>;
            expect(
              (compiled['outbounds'] as List).any(
                (value) => value['tag'] == 'provider-proxy',
              ),
              isTrue,
            );
            expect(
              (compiled['outbounds'] as List).any(
                (value) => '${value['tag']}'.startsWith('app-entry-'),
              ),
              isFalse,
            );
          },
        );
      }
    }

    test('automatic selection ignores inactive provider and ordinary caches', () async {
      final appSourceId = await db.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: 'App source',
          url: 'https://example.com/app-subscription',
          timestamp: DateTime(2026, 10, 12),
        ),
      );
      final hiddenProfileId = await db.coreConfigDao.insertRow(
        CoreConfigCompanion.insert(
          name: 'Hidden provider profile',
          type: CoreConfigType.Remnawave.name,
          tags: '',
          delay: PingDelayConstants.unknown,
          subId: appSourceId,
          data: Value(profile.data),
        ),
      );
      await db.coreConfigDao.insertRow(
        CoreConfigCompanion.insert(
          name: 'Hidden ordinary node',
          type: CoreConfigType.outbound.name,
          tags: '',
          delay: 1,
          subId: source.id,
          data: Value(profile.data),
        ),
      );
      // Put the inactive profile before the active row to verify filtering,
      // rather than depending on the setup row already having the smallest ID.
      await db.coreConfigDao.deleteRow(profile);
      final activeId = await db.coreConfigDao.insertRow(
        CoreConfigCompanion.insert(
          name: profile.name,
          type: CoreConfigType.Remnawave.name,
          tags: '',
          delay: PingDelayConstants.unknown,
          subId: source.id,
          data: Value(profile.data),
        ),
      );
      expect(hiddenProfileId, lessThan(activeId));
      final runtime =
          await ConnectionPreparation(
            db: db,
            getFreePorts: (count, {excludePorts}) async => [18002, 18003],
            requireDependencies: (_) async {},
          ).prepare(
            ConnectionConfiguration(
              connection: ConnectionSettings(trafficMode: TrafficMode.allVpn),
            ),
          );
      expect(runtime.profile?.id, activeId);
      expect(runtime.entries, isEmpty);
    });

    test('a missing custom route remains a configuration error with provider candidates', () async {
      await expectLater(
        ConnectionPreparation(
          db: db,
          getFreePorts: (count, {excludePorts}) async => [18002, 18003],
          requireDependencies: (_) async {},
        ).prepare(
          ConnectionConfiguration(
            connection: ConnectionSettings(
              trafficMode: TrafficMode.custom,
              customId: 987654,
            ),
          ),
        ),
        throwsFormatException,
      );
    });

    test(
      'automatic profile without inbounds ignores inactive custom listeners',
      () async {
        final config = {..._providerConfig}..remove('inbounds');
        await db.coreConfigDao.updateRow(
          profile.copyWith(
            data: Value(base64Encode(utf8.encode(jsonEncode(config)))),
          ),
        );
        final api = _localApi(enabled: true);
        addTearDown(api.stop);
        final runtime =
            await ConnectionPreparation(
              db: db,
              localApi: api,
              getFreePorts: (count, {excludePorts}) async => [18002, 18003],
              requireDependencies: (_) async {},
            ).prepare(
              ConnectionConfiguration(
                connection: ConnectionSettings(trafficMode: TrafficMode.custom),
              ),
              customDraft: AdvancedRoutingDocument.fromJson({
                'outbounds': [<String, dynamic>{}],
                'inbounds': [
                  {'tag': 'custom-http', 'protocol': 'http', 'port': 18587},
                ],
              }).state,
            );
        expect(runtime.profile?.id, profile.id);
        expect(runtime.entries, isEmpty);
      },
    );

    test(
      'automatic provider changes are rejected without trying a later profile',
      () async {
        final laterId = await db.coreConfigDao.insertRow(
          CoreConfigCompanion.insert(
            name: 'Later provider profile',
            type: CoreConfigType.Remnawave.name,
            tags: '',
            delay: PingDelayConstants.unknown,
            subId: source.id,
            data: Value(profile.data),
          ),
        );
        var allocations = 0;
        await expectLater(
          ConnectionPreparation(
            db: db,
            getFreePorts: (count, {excludePorts}) async {
              allocations++;
              await db.coreConfigDao.deleteRow(profile);
              return [18002, 18003];
            },
            requireDependencies: (_) async {},
          ).prepare(
            ConnectionConfiguration(
              connection: ConnectionSettings(trafficMode: TrafficMode.allVpn),
            ),
          ),
          throwsFormatException,
        );
        expect(allocations, 1);
        expect(await db.coreConfigDao.searchRow(laterId), isNotNull);
      },
    );

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

    for (final healthyAlternative in [false, true]) {
      test(
        'fixed ordinary retry stays ordinary with alternative $healthyAlternative',
        () async {
          Future<int> addOrdinary(String name, int delay) =>
              db.coreConfigDao.insertRow(
                CoreConfigCompanion.insert(
                  name: name,
                  type: CoreConfigType.outbound.name,
                  tags: '',
                  delay: delay,
                  subId: 0,
                  data: Value(
                    base64Encode(
                      utf8.encode(
                        jsonEncode({
                          'outbounds': [
                            {'tag': name, 'protocol': 'freedom'},
                          ],
                        }),
                      ),
                    ),
                  ),
                ),
              );
          final failed = await addOrdinary(
            'Failed ordinary',
            PingDelayConstants.error,
          );
          final healthy = healthyAlternative
              ? await addOrdinary('Healthy ordinary', 20)
              : null;
          final preparing =
              ConnectionPreparation(
                db: db,
                getFreePorts: (count, {excludePorts}) async => [18002, 18003],
                requireDependencies: (_) async {},
              ).prepare(
                ConnectionConfiguration(
                  connection: ConnectionSettings(
                    selection: ServerSelection.server(failed),
                    trafficMode: TrafficMode.allVpn,
                  ),
                ),
              );
          if (healthy == null) {
            await expectLater(
              preparing,
              throwsA(
                isA<ConnectionResolutionException>().having(
                  (error) => error.reason,
                  'reason',
                  ConnectionResolutionFailure.insufficientHealthyServers,
                ),
              ),
            );
          } else {
            final runtime = await preparing;
            expect(runtime.profile, isNull);
            expect(runtime.entries.map((entry) => entry.id), [healthy]);
            expect(
              runtime.configuration.connection.selection.kind,
              SelectionKind.automatic,
            );
            expect(runtime.notice, 'selectionReset');
          }
        },
      );
    }

    test('rejects an inactive fixed provider', () async {
      await db.subscriptionDao.updateRow(
        source.copyWith(mode: SubscriptionMode.appManaged.name),
      );
      await expectLater(
        _providerPreparation(db).prepare(_providerInput(profile.id)),
        throwsFormatException,
      );
    });

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
  LocalApiService? localApi,
  Future<List<int>> Function(int count, {List<int>? excludePorts})?
  getFreePorts,
  Future<void> Function(Map<String, GeoDataType>)? requireDependencies,
}) => ConnectionPreparation(
  db: db,
  localApi: localApi,
  resolver: _unavailableResolver(),
  getFreePorts: getFreePorts ?? (count, {excludePorts}) async => [18002, 18003],
  requireDependencies: requireDependencies ?? (_) async {},
);

LocalApiService _localApi({bool enabled = false, int port = 18587}) =>
    LocalApiService.forTesting(
      readSettings: () async => LocalApiSettings(
        enabled: enabled,
        port: port,
        token: 'a' * 43,
      ).toJson(),
      writeSettings: (_) async {},
      info: () async => {},
      validate: (_) async => {},
      compile: (_) async => {},
    );

final _throwsApiConflict = throwsA(
  isA<FormatException>().having(
    (error) => error.message,
    'message',
    contains('HTTP API'),
  ),
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
