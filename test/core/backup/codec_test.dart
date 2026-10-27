import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/backup/codec.dart';
import 'package:onexray/core/backup/model.dart';

void main() {
  const smart = BackupSmartRouting(
    entryCount: 3,
    directRegions: ['CN'],
    directPrivate: true,
    directApple: true,
    directWindows: true,
    directDns: true,
    directDnsAddress: '8.8.8.8',
    fakeDns: false,
    fragment: true,
    blockAds: false,
  );
  BackupDocument sample() => BackupDocument(
    createdAt: 1000,
    coreConfigs: [
      for (var i = 0; i < 4; i++)
        BackupCoreConfig(
          '配置 $i',
          'raw',
          '',
          base64Encode(utf8.encode('{\n  "custom": 1\n}')),
        ),
    ],
    subscriptions: const [
      BackupSubscription(
        'Source',
        'https://example.com/sub',
        'private-fixture',
        'public-fixture',
        false,
        'stable-fixture',
      ),
    ],
    routingProfiles: const [],
    smartRouting: smart,
    geoData: const [
      BackupGeoData('custom', 'domain', 'https://example.com/custom.dat'),
    ],
  );

  test(
    'single JSON preserves original text, all Raw rows and sensitive fields',
    () {
      final document = sample();
      final result = decodeBackup(encodeBackup(document));
      expect(result.toJson(), document.toJson());
      expect(result.coreConfigs, hasLength(4));
      expect(result.subscriptions.single.hwid, 'stable-fixture');
      expect(result.subscriptions.single.hwidEnabled, false);
      expect(result.smartRouting.toJson(), isNot(contains('finalExitId')));
      expect(result.smartRouting.fragment, true);
    },
  );

  test(
    'platform sections remain opaque until the receiving platform reads them',
    () {
      final json = sample().toJson()
        ..['platformSettings'] = {
          'android': {
            'android': {
              'appScope': 'included',
              'includedAppPackageNames': ['com.example.app'],
              'excludedAppPackageNames': ['com.example.other'],
            },
          },
          'ios': 'unreadable on other platforms',
          'macos': 42,
          'windows': null,
          'linux': {'ipv6Enabled': false},
          'futurePlatform': [1, 2],
        };
      final document = decodeBackup(
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
      );
      expect(
        decodeBackup(encodeBackup(document)).platformSettings,
        json['platformSettings'],
      );
      expect(document.version, 1);
    },
  );

  test('old v1 has no platform settings and omits the optional section', () {
    final document = decodeBackup(encodeBackup(sample()));
    expect(document.platformSettings, isNull);
    expect(document.toJson(), isNot(contains('platformSettings')));
  });

  test('the platform settings container must be an object', () {
    for (final value in ['android', <Object>[], 1]) {
      final json = sample().toJson()..['platformSettings'] = value;
      expect(
        () => decodeBackup(Uint8List.fromList(utf8.encode(jsonEncode(json)))),
        throwsFormatException,
      );
    }
  });

  test('previous v1 backups default fragment to disabled', () {
    final json = sample().toJson();
    (json['smartRouting'] as Map<String, dynamic>).remove('fragment');
    final document = decodeBackup(
      Uint8List.fromList(utf8.encode(jsonEncode(json))),
    );
    expect(document.smartRouting.fragment, false);
    expect(document.smartRouting.toJson()['fragment'], false);
  });

  test('previous v1 backups have ungrouped nodes in their original order', () {
    final json = sample().toJson()..remove('manualGroups');
    for (final row in json['coreConfigs'] as List) {
      (row as Map).remove('manualSortOrder');
      row.remove('manualGroupKey');
    }
    final document = decodeBackup(
      Uint8List.fromList(utf8.encode(jsonEncode(json))),
    );
    expect(document.manualGroups, isEmpty);
    expect(document.coreConfigs.map((row) => row.name), [
      '配置 0',
      '配置 1',
      '配置 2',
      '配置 3',
    ]);
    expect(
      document.coreConfigs.every(
        (row) => row.manualGroupKey == null && row.manualSortOrder == 0,
      ),
      true,
    );
  });

  test('v1 manual groups preserve empty groups and saved node order', () {
    final json = sample().toJson();
    json['manualGroups'] = [
      {'key': 'g1', 'name': 'Empty', 'sortOrder': 1, 'futureField': true},
      {'key': 'g2', 'name': 'Home', 'sortOrder': 2},
    ];
    final row = (json['coreConfigs'] as List).first as Map;
    row['type'] = 'outbound';
    row['manualGroupKey'] = 'g2';
    row['manualSortOrder'] = 3;
    final document = decodeBackup(
      Uint8List.fromList(utf8.encode(jsonEncode(json))),
    );
    final restored = decodeBackup(encodeBackup(document));
    expect(restored.version, 1);
    expect(restored.manualGroups.map((row) => row.name), ['Empty', 'Home']);
    expect(restored.manualGroups.map((row) => row.sortOrder), [1, 2]);
    expect(
      restored.manualGroups.first.toJson(),
      isNot(contains('futureField')),
    );
    expect(restored.coreConfigs.first.manualGroupKey, 'g2');
    expect(restored.coreConfigs.first.manualSortOrder, 3);
  });

  test(
    'rejects invalid grouping fields, duplicate keys and missing references',
    () {
      final group = {'key': 'g1', 'name': 'Home', 'sortOrder': 0};
      for (final patch in <Map<String, dynamic>>[
        {'manualGroups': null},
        {
          'manualGroups': [group, group],
        },
        {
          'manualGroups': [
            {...group, 'sortOrder': 1.5},
          ],
        },
        {
          'manualGroups': [
            {...group, 'sortOrder': -1},
          ],
        },
        {
          'manualGroups': [
            {...group, 'name': ' '},
          ],
        },
        {
          'manualGroups': [group],
          'coreConfigs': [
            const BackupCoreConfig(
              'Node',
              'outbound',
              '',
              'e30=',
              manualGroupKey: 'missing',
            ).toJson(),
          ],
        },
        {
          'manualGroups': [group],
          'coreConfigs': [
            const BackupCoreConfig(
              'Raw',
              'raw',
              '',
              'e30=',
              manualGroupKey: 'g1',
            ).toJson(),
          ],
        },
        {
          'coreConfigs': [
            {
              ...const BackupCoreConfig(
                'Node',
                'outbound',
                '',
                'e30=',
              ).toJson(),
              'manualSortOrder': '1',
            },
          ],
        },
      ]) {
        final json = sample().toJson()..addAll(patch);
        expect(
          () => decodeBackup(Uint8List.fromList(utf8.encode(jsonEncode(json)))),
          throwsFormatException,
        );
      }
    },
  );

  test('previous subscriptions default to generic App management', () {
    final json = sample().toJson();
    final source =
        (json['subscriptions'] as List).single as Map<String, dynamic>;
    source.remove('panel');
    source.remove('mode');
    source['futureSourceField'] = {'preservedByFutureClient': true};
    final document = decodeBackup(
      Uint8List.fromList(utf8.encode(jsonEncode(json))),
    );
    expect(document.subscriptions.single.panel, 'generic');
    expect(document.subscriptions.single.mode, 'appManaged');
    expect(
      document.subscriptions.single.toJson(),
      isNot(contains('futureSourceField')),
    );
  });

  test('source panel and mode round trip without changing backup version', () {
    final json = sample().toJson();
    final source =
        (json['subscriptions'] as List).single as Map<String, dynamic>;
    source['panel'] = 'remnawave';
    source['mode'] = 'providerManaged';
    final document = decodeBackup(
      Uint8List.fromList(utf8.encode(jsonEncode(json))),
    );
    final result = decodeBackup(encodeBackup(document));
    expect(result.version, 1);
    expect(result.subscriptions.single.panel, 'remnawave');
    expect(result.subscriptions.single.mode, 'providerManaged');
  });

  test('fragment must be a boolean when present', () {
    final json = sample().toJson();
    (json['smartRouting'] as Map<String, dynamic>)['fragment'] = 'true';
    expect(
      () => decodeBackup(Uint8List.fromList(utf8.encode(jsonEncode(json)))),
      throwsFormatException,
    );
  });

  test('ignores unknown fields in every backup section', () {
    final expected = sample().toJson();
    expected['routingProfiles'] = [
      const BackupRoutingProfile('Route', false, 'e30=').toJson(),
    ];
    final json = jsonDecode(jsonEncode(expected)) as Map<String, dynamic>;
    json['files'] = [];
    for (final key in [
      'coreConfigs',
      'subscriptions',
      'routingProfiles',
      'geoData',
    ]) {
      for (final row in json[key] as List) {
        (row as Map<String, dynamic>)['futureField'] = {'enabled': true};
      }
    }
    (json['smartRouting'] as Map<String, dynamic>)['finalExitId'] = 7;

    final document = decodeBackup(
      Uint8List.fromList(utf8.encode(jsonEncode(json))),
    );
    expect(document.toJson(), expected);
  });

  test('rejects missing partitions and unsupported formats or versions', () {
    for (final json in [
      sample().toJson()..remove('subscriptions'),
      sample().toJson()..remove('version'),
      sample().toJson()..['format'] = 'future-backup',
      sample().toJson()..['version'] = 4,
    ]) {
      expect(
        () => decodeBackup(Uint8List.fromList(utf8.encode(jsonEncode(json)))),
        throwsFormatException,
      );
    }
  });

  test('diagnostics do not echo malformed credentials', () {
    expect(
      () => decodeBackup(Uint8List.fromList(utf8.encode('{"secret":"private'))),
      throwsA(
        isA<FormatException>().having(
          (e) => e.toString(),
          'safe message',
          isNot(contains('private')),
        ),
      ),
    );
    expect(
      () => decodeBackupConfiguration('invalid private'),
      throwsFormatException,
    );
    expect(
      () => decodeBackupConfiguration(base64Encode(utf8.encode('[]'))),
      throwsFormatException,
    );
  });

  test('bounds reads before decoding', () {
    expect(
      () => decodeBackup(Uint8List(backupByteLimit + 1)),
      throwsFormatException,
    );
    expect(() => decodeBackup(Uint8List(0)), throwsFormatException);
  });

  test('backup encoding checks actual UTF-8 size', () {
    // Characters fit below the byte limit; UTF-8 bytes do not.
    final oversized = BackupDocument(
      createdAt: 1000,
      coreConfigs: [
        BackupCoreConfig('中文' * (backupByteLimit ~/ 6), 'raw', '', 'e30='),
      ],
      subscriptions: const [],
      routingProfiles: const [],
      smartRouting: smart,
      geoData: const [],
    );
    expect(() => encodeBackup(oversized), throwsFormatException);
  });

  test('empty asset collections are a valid replacement backup', () {
    final document = BackupDocument(
      createdAt: 1000,
      coreConfigs: const [],
      subscriptions: const [],
      routingProfiles: const [],
      smartRouting: smart,
      geoData: const [],
    );
    expect(decodeBackup(encodeBackup(document)).toJson(), document.toJson());
  });

  test('invalid UTF-8 and field types are rejected without echoing values', () {
    expect(
      () => decodeBackup(Uint8List.fromList([0xff])),
      throwsFormatException,
    );
    for (final json in [
      sample().toJson()..['createdAt'] = 'not a timestamp',
      sample().toJson()..['coreConfigs'] = {},
      sample().toJson()
        ..['subscriptions'] = [
          {'name': 'private-fixture'},
        ],
      sample().toJson()..['createdAt'] = -1,
    ]) {
      expect(
        () => decodeBackup(Uint8List.fromList(utf8.encode(jsonEncode(json)))),
        throwsFormatException,
      );
    }
  });
}
