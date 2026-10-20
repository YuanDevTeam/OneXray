import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'schema 5 adds nullable package cache and preserves all saved data',
    () async {
      final file = await _legacyDatabase(5);
      final old = sqlite.sqlite3.open(file.path);
      final before = _snapshotV5(old);
      old.close();

      final database = AppDatabase.forTesting(NativeDatabase(file));
      final subscription = (await database.subscriptionDao.allRows).single;
      _expectNoUserInfo(subscription);
      expect(subscription.id, 7);
      expect(subscription.ageSecretKey, 'AGE-SECRET-KEY-TEST');
      expect(subscription.agePublicKey, 'age1test');
      expect(subscription.hwidEnabled, isTrue);
      expect(subscription.hwid, 'keep-hwid');
      expect(
        (await database.routingProfileDao.allRows).single.advanced,
        isTrue,
      );
      expect((await database.geoDataDao.allRows).single.installed, isFalse);
      await database.close();

      final upgraded = sqlite.sqlite3.open(file.path);
      expect(upgraded.userVersion, 9);
      expect(_snapshotV5(upgraded), before);
      upgraded.close();

      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);
      expect((await reopened.subscriptionDao.allRows).single, subscription);
      final id = await reopened.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: 'After upgrade',
          url: 'https://example.com/new-sub',
          timestamp: DateTime(2026),
        ),
      );
      expect(id, greaterThan(7));
      _expectNoUserInfo((await reopened.subscriptionDao.searchRow(id))!);
    },
  );

  test(
    'package changes and cache clearing reach the existing subscription stream',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final dao = database.subscriptionDao;
      final id = await dao.insertRow(
        SubscriptionCompanion.insert(
          name: 'Provider',
          url: 'https://example.com/sub',
          timestamp: DateTime(2026),
        ),
      );
      final events = StreamIterator(dao.allRowsStream);
      addTearDown(events.cancel);
      expect(await events.moveNext(), isTrue);
      _expectNoUserInfo(events.current.single);

      final checkedAt = DateTime(2026, 9, 22, 12);
      final updated = events.current.single.copyWith(
        uploadBytes: const Value(1024),
        downloadBytes: const Value(2048),
        totalBytes: const Value(0),
        expireTimestamp: const Value(0),
        userInfoUpdatedAt: Value(checkedAt),
      );
      expect(await dao.updateRow(updated), isTrue);
      expect(await events.moveNext(), isTrue);
      expect(events.current.single.id, id);
      expect(events.current.single.uploadBytes, 1024);
      expect(events.current.single.downloadBytes, 2048);
      expect(events.current.single.totalBytes, 0);
      expect(events.current.single.expireTimestamp, 0);
      expect(events.current.single.userInfoUpdatedAt, checkedAt);

      expect(
        await dao.updateRow(
          updated.copyWith(
            uploadBytes: const Value(null),
            downloadBytes: const Value(null),
            totalBytes: const Value(null),
            expireTimestamp: const Value(null),
            userInfoUpdatedAt: const Value(null),
          ),
        ),
        isTrue,
      );
      expect(await events.moveNext(), isTrue);
      _expectNoUserInfo(events.current.single);
    },
  );

  test(
    'schema 4 adds routing mode without rewriting any configuration',
    () async {
      final file = await _legacyDatabase(4);
      final old = sqlite.sqlite3.open(file.path);
      final before = _snapshotV3(old);
      old.close();
      final database = AppDatabase.forTesting(NativeDatabase(file));
      final routes = await database.routingProfileDao.allRows;
      expect(routes.single.id, 9);
      expect(routes.single.advanced, false);
      expect((await database.coreConfigDao.allRawRowsWithData).length, 4);
      final sub = (await database.subscriptionDao.allRows).single;
      expect(sub.hwidEnabled, true);
      expect(sub.hwid, 'keep-hwid');
      _expectNoUserInfo(sub);
      expect(
        (await database.geoDataDao.allRows).every((row) => row.installed),
        true,
      );
      await database.close();
      final upgraded = sqlite.sqlite3.open(file.path);
      expect(upgraded.userVersion, 9);
      expect(_snapshotV3(upgraded), before);
      upgraded.close();
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);
      expect((await reopened.routingProfileDao.allRows).single, routes.single);
    },
  );

  test('an interrupted empty first creation retries', () async {
    final directory = await _fixtureDirectory('onexray-empty-db-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/db.sqlite');
    sqlite.sqlite3.open(file.path).close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);
    expect(await database.subscriptionDao.allRows, isEmpty);
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      9,
    );
  });

  test(
    'an unknown populated schema 0 database is rejected unchanged',
    () async {
      final directory = await _fixtureDirectory('onexray-unknown-db-test-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/db.sqlite');
      final unknown = sqlite.sqlite3.open(file.path);
      unknown.execute('CREATE TABLE important_data (value TEXT)');
      unknown.execute("INSERT INTO important_data VALUES ('Keep me')");
      unknown.close();

      final database = AppDatabase.forTesting(NativeDatabase(file));
      await expectLater(database.subscriptionDao.allRows, throwsStateError);
      await database.close();

      final check = sqlite.sqlite3.open(file.path);
      try {
        expect(check.userVersion, 0);
        expect(
          check.select('SELECT value FROM important_data').single['value'],
          'Keep me',
        );
        expect(
          check
              .select("SELECT name FROM sqlite_master WHERE type = 'table'")
              .map((row) => row['name']),
          ['important_data'],
        );
      } finally {
        check.close();
      }
    },
  );

  test(
    'upgrade preserves committed WAL data without creating a snapshot',
    () async {
      final file = await _legacyDatabase(2);
      final writer = sqlite.sqlite3.open(file.path);
      addTearDown(writer.close);
      writer.execute('PRAGMA journal_mode = WAL');
      writer.execute('PRAGMA wal_autocheckpoint = 0');
      writer.execute(
        "UPDATE core_config SET name = 'WAL-only name' WHERE id = 11",
      );
      final before = _snapshot(writer, hasAgeKeys: true);

      final database = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(database.close);
      expect(
        (await database
                .customSelect('SELECT name FROM core_config WHERE id = 11')
                .getSingle())
            .read<String>('name'),
        'WAL-only name',
      );
      expect(writer.userVersion, 9);
      expect(_snapshot(writer, hasAgeKeys: true), _afterUpgrade(before));
      expect(
        file.parent.listSync().where(
          (entry) => entry.path.contains('.pre-v3-'),
        ),
        isEmpty,
      );
    },
  );

  test('new installation creates schema 9 with empty assets and default connection configuration', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    expect(await database.coreConfigDao.allRawRowsWithData, isEmpty);
    expect(await database.routingProfileDao.allRows, isEmpty);
    expect(await database.subscriptionDao.allRows, isEmpty);
    expect((await database.connectionConfigDao.read()).configurationJson, '{}');
    final routingTables = await database.customSelect('''
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name IN ('routing_profile', 'custom_routing_profiles')
      ''').get();
    expect(routingTables.map((row) => row.read<String>('name')), [
      'routing_profile',
    ]);
    for (final entry in {
      'core_config': ['country_code', 'location_source', 'last_measured_at'],
      'subscription': [
        'parse_failure_count',
        'auto_update',
        'count',
        'expanded',
      ],
      'geo_data': ['generation'],
      'connection_config': ['revision'],
    }.entries) {
      final columns = await database
          .customSelect('PRAGMA table_info(${entry.key})')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        isNot(anyElement(isIn(entry.value))),
      );
    }
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      9,
    );
  });

  for (final version in [1, 2]) {
    test(
      'schema $version upgrades in place without rewriting assets',
      () async {
        final file = await _legacyDatabase(version);
        final before = _snapshotFile(file, hasAgeKeys: version == 2);

        final database = AppDatabase.forTesting(NativeDatabase(file));
        try {
          final subscriptions = await database.subscriptionDao.allRows;
          expect(subscriptions.single.id, 7);
          expect(subscriptions.single.hwidEnabled, isFalse);
          expect(subscriptions.single.hwid, isNull);
          _expectNoUserInfo(subscriptions.single);
          final subscriptionColumns = await database
              .customSelect('PRAGMA table_info(subscription)')
              .get();
          expect(
            subscriptionColumns.map((row) => row.read<String>('name')),
            isNot(anyElement(isIn(['auto_update', 'count', 'expanded']))),
          );
          final geoDataColumns = await database
              .customSelect('PRAGMA table_info(geo_data)')
              .get();
          expect(
            geoDataColumns.map((row) => row.read<String>('name')),
            isNot(contains('generation')),
          );
          expect(
            subscriptions.single.ageSecretKey,
            version == 2 ? 'AGE-SECRET-KEY-TEST' : null,
          );
          expect(
            subscriptions.single.agePublicKey,
            version == 2 ? 'age1test' : null,
          );
          final rawRows = await database.coreConfigDao.allRawRowsWithData;
          expect(rawRows, hasLength(4));
          expect(rawRows.every((row) => !row.favorite), isTrue);
          expect(await database.routingProfileDao.allRows, isEmpty);
          expect(
            (await database.connectionConfigDao.read()).configurationJson,
            '{}',
          );
          final routingTables = await database.customSelect('''
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name IN ('routing_profile', 'custom_routing_profiles')
          ''').get();
          expect(routingTables.map((row) => row.read<String>('name')), [
            'routing_profile',
          ]);
        } finally {
          await database.close();
        }

        expect(_snapshotFile(file, hasAgeKeys: true), _afterUpgrade(before));
        final reopened = AppDatabase.forTesting(NativeDatabase(file));
        try {
          expect(await reopened.coreConfigDao.allRawRowsWithData, hasLength(4));
          expect(
            (await reopened.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            9,
          );
          final subId = await reopened.subscriptionDao.insertRow(
            SubscriptionCompanion.insert(
              name: 'After upgrade',
              url: 'https://example.com/new-sub',
              timestamp: DateTime(2026),
            ),
          );
          expect(subId, greaterThan(7));
          expect(
            (await reopened.subscriptionDao.searchRow(subId))!.name,
            'After upgrade',
          );
          await reopened.subscriptionDao.deleteRow(subId);
        } finally {
          await reopened.close();
        }
        expect(_snapshotFile(file, hasAgeKeys: true), _afterUpgrade(before));
      },
    );

    test(
      'schema $version custom Geodata gains the default manifest in place',
      () async {
        final file = await _legacyDatabase(version);
        final datRoot = Directory(p.join(file.parent.path, 'dat'));
        await datRoot.create();
        for (final name in ['geoip', 'geosite', 'legacy-geosite']) {
          await File(p.join(datRoot.path, '$name.dat')).writeAsString(name);
          await File(p.join(datRoot.path, '$name.json')).writeAsString(
            jsonEncode({
              'categoryCount': 1,
              'ruleCount': 2,
              'codes': [
                {'code': 'CN', 'ruleCount': 2},
              ],
            }),
          );
        }
        await File(p.join(datRoot.path, 'timestamp.txt')).writeAsString('123');

        final database = AppDatabase.forTesting(NativeDatabase(file));
        addTearDown(database.close);
        final service = GeoDataService.forTesting(
          database: database,
          directory: datRoot.path,
          download: (_, _) async => fail('Upgrade must not download Geodata'),
          count: (_, _, _) async => fail('Upgrade must not rebuild indexes'),
          copyBundled: (_) async => fail('Upgrade must reuse valid files'),
        );

        await service.ensureInstalled();

        final rows = await database.geoDataDao.publishedRows;
        expect(rows.map((row) => row.id).toSet(), {-2, -1, 5});
        expect(rows.singleWhere((row) => row.id == 5).name, 'legacy-geosite');
        expect(
          await File(p.join(datRoot.path, 'legacy-geosite.dat')).readAsString(),
          'legacy-geosite',
        );
        expect(await service.watchPublished().first, hasLength(3));
      },
    );
  }

  test(
    'missing subscription cache and GeoData do not block upgrading',
    () async {
      final file = await _legacyDatabase(2);
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('DELETE FROM core_config WHERE sub_id <> 0');
      legacy.execute('DELETE FROM geo_data');
      legacy.close();
      final before = _snapshotFile(file, hasAgeKeys: true);

      final database = AppDatabase.forTesting(NativeDatabase(file));
      try {
        expect(await database.subscriptionDao.allRows, hasLength(1));
        expect(await database.geoDataDao.allRows, isEmpty);
      } finally {
        await database.close();
      }
      expect(_snapshotFile(file, hasAgeKeys: true), _afterUpgrade(before));
    },
  );

  test('released schema 3 preserves all data and defaults HWID off', () async {
    final file = await _legacyDatabase(3);
    final beforeDb = sqlite.sqlite3.open(file.path);
    final before = _snapshotV3(beforeDb);
    beforeDb.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    final source = (await database.subscriptionDao.allRows).single;
    expect(source.id, 7);
    expect(source.hwidEnabled, isFalse);
    expect(source.hwid, isNull);
    _expectNoUserInfo(source);
    await database.close();

    final upgraded = sqlite.sqlite3.open(file.path);
    expect(upgraded.userVersion, 9);
    expect(_snapshotV3(upgraded), before);
    upgraded.close();

    final reopened = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(reopened.close);
    expect((await reopened.subscriptionDao.allRows).single, source);
  });

  test('schema 6 removes country cache and preserves package and configuration data', () async {
    final file = await _legacyDatabase(6);
    final legacy = sqlite.sqlite3.open(file.path);
    final before = _snapshotV6(legacy);
    final originalConfiguration = legacy
        .select('SELECT configuration_json FROM connection_config')
        .single['configuration_json'];
    legacy.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    final source = (await database.subscriptionDao.allRows).single;
    expect(source.panel, 'generic');
    expect(source.mode, 'appManaged');
    expect(source.uploadBytes, 10);
    expect(source.downloadBytes, 20);
    expect(source.totalBytes, 100);
    expect(source.hwid, 'keep-hwid');
    expect(
      (await database.connectionConfigDao.read()).configurationJson,
      originalConfiguration,
    );
    expect((await database.coreConfigDao.searchRow(12))!.favorite, isTrue);
    final columns = await database
        .customSelect('PRAGMA table_info(core_config)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      isNot(contains('country_code')),
    );
    await database.close();

    final upgraded = sqlite.sqlite3.open(file.path);
    expect(upgraded.userVersion, 9);
    expect(_snapshotV6(upgraded), before);
    upgraded.close();
    final reopened = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(reopened.close);
    expect((await reopened.subscriptionDao.allRows).single, source);
  });

  test('schema 7 adds an optional UA and preserves provider assets', () async {
    final file = await _legacyDatabase(7);
    final old = sqlite.sqlite3.open(file.path);
    final before = _snapshotV6(old);
    old.close();
    final database = AppDatabase.forTesting(NativeDatabase(file));
    final source = (await database.subscriptionDao.allRows).single;
    expect(source.userAgent, isNull);
    expect(source.panel, 'remnawave');
    expect(source.mode, 'providerManaged');
    expect(source.ageSecretKey, 'AGE-SECRET-KEY-TEST');
    expect(source.hwid, 'keep-hwid');
    await database.subscriptionDao.updateRow(
      source.copyWith(userAgent: const Value('v2rayN/test')),
    );
    await database.close();
    final upgraded = sqlite.sqlite3.open(file.path);
    expect(upgraded.userVersion, 9);
    expect(_snapshotV6(upgraded), before);
    upgraded.close();
    final reopened = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(reopened.close);
    final persisted = (await reopened.subscriptionDao.allRows).single;
    expect(persisted.userAgent, 'v2rayN/test');
    expect(persisted.id, source.id);
    expect(persisted.panel, source.panel);
    expect(persisted.mode, source.mode);
  });

  test(
    'schema 8 adds manual groups without touching existing assets',
    () async {
      final file = await _legacyDatabase(8);
      final old = sqlite.sqlite3.open(file.path);
      final before = _snapshotV6(old);
      old.close();
      final database = AppDatabase.forTesting(NativeDatabase(file));
      expect(await database.manualServerGroupDao.allRows, isEmpty);
      expect(
        (await database.subscriptionDao.allRows).single.userAgent,
        'Saved custom UA',
      );
      final rows = await database.select(database.coreConfig).get();
      expect(rows.every((row) => row.manualGroupId == null), isTrue);
      expect(rows.every((row) => row.manualSortOrder == 0), isTrue);
      await database.close();
      final upgraded = sqlite.sqlite3.open(file.path);
      expect(upgraded.userVersion, 9);
      expect(_snapshotV6(upgraded), before);
      upgraded.close();
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);
      expect(await reopened.manualServerGroupDao.allRows, isEmpty);
      expect(
        (await reopened.subscriptionDao.allRows).single.userAgent,
        'Saved custom UA',
      );
    },
  );

  test(
    'a future schema is rejected without changing the original database',
    () async {
      final file = await _legacyDatabase(2);
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.userVersion = 10;
      legacy.close();
      final before = _snapshotFile(file, hasAgeKeys: true);
      final database = AppDatabase.forTesting(NativeDatabase(file));
      await expectLater(database.subscriptionDao.allRows, throwsStateError);
      await database.close();
      expect(await file.exists(), isTrue);
      final check = sqlite.sqlite3.open(file.path);
      try {
        expect(check.userVersion, 10);
        expect(_snapshot(check, hasAgeKeys: true), before);
      } finally {
        check.close();
      }
    },
  );
}

Future<File> _legacyDatabase(int version) async {
  final directory = await _fixtureDirectory('onexray-schema-test-');
  addTearDown(() => directory.delete(recursive: true));
  final file = File('${directory.path}/db.sqlite');
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      CREATE TABLE core_config (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, type TEXT NOT NULL, tags TEXT NOT NULL,
        data TEXT, delay INTEGER NOT NULL, sub_id INTEGER NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE subscription (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, url TEXT NOT NULL, timestamp INTEGER NOT NULL,
        count INTEGER NOT NULL,
        expanded INTEGER NOT NULL CHECK (expanded IN (0, 1))
      )
    ''');
    database.execute('''
      CREATE TABLE geo_data (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, type TEXT NOT NULL, url TEXT NOT NULL,
        timestamp INTEGER NOT NULL, category_count INTEGER NOT NULL,
        rule_count INTEGER NOT NULL
      )
    ''');
    database.execute('''
      INSERT INTO subscription (id, name, url, timestamp, count, expanded)
      VALUES (7, 'Existing', 'https://example.com/sub', 123, 1, 1)
    ''');
    if (version >= 2) {
      database.execute(
        'ALTER TABLE subscription ADD COLUMN age_secret_key TEXT',
      );
      database.execute(
        'ALTER TABLE subscription ADD COLUMN age_public_key TEXT',
      );
      database.execute('''
        UPDATE subscription SET
          age_secret_key = 'AGE-SECRET-KEY-TEST', age_public_key = 'age1test'
      ''');
    }
    final entries = [
      [11, 'outbound', 0, base64Encode(utf8.encode('{"tag":"本地😀"}'))],
      [12, 'outbound', 7, 'not base64!'],
      [13, 'outbound', 0, null],
      [14, 'outbound', 0, base64Encode(utf8.encode('not JSON'))],
      for (var id = 21; id <= 24; id++)
        [id, 'raw', 0, base64Encode(utf8.encode('{"legacy":$id}'))],
      [31, 'setting', 0, 'retired profile data'],
      [32, 'full', 0, 'retired multi-node data'],
      [33, 'unknown-type', 0, 'future data'],
    ];
    for (final entry in entries) {
      database.execute(
        '''
        INSERT INTO core_config (id, name, type, tags, data, delay, sub_id)
        VALUES (?, ?, ?, 'legacy-tags', ?, 123, ?)
      ''',
        [entry[0], 'Config ${entry[0]}', entry[1], entry[3], entry[2]],
      );
    }
    database.execute('''
      INSERT INTO geo_data
        (id, name, type, url, timestamp, category_count, rule_count)
      VALUES (5, 'legacy-geosite', 'domain', 'https://example.com/geo', 123, 2, 3)
    ''');
    if (version >= 3) {
      database.execute('''
        ALTER TABLE subscription DROP COLUMN count;
        ALTER TABLE subscription DROP COLUMN expanded;
        ALTER TABLE core_config ADD COLUMN country_code TEXT;
        ALTER TABLE core_config ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0;
        UPDATE core_config SET country_code = 'JP', favorite = 1 WHERE id = 12;
        CREATE TABLE routing_profile (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, data TEXT NOT NULL
        );
        INSERT INTO routing_profile VALUES (9, 'Saved routing', 'eyJydWxlcyI6W119');
        CREATE TABLE connection_config (
          id INTEGER NOT NULL DEFAULT 1 PRIMARY KEY CHECK (id = 1),
          configuration_json TEXT NOT NULL DEFAULT '{}'
        );
        INSERT INTO connection_config VALUES (1, '{"connection":{"selection":{"kind":"server","id":12}}}');
      ''');
    }
    if (version >= 4) {
      database.execute(
        'ALTER TABLE subscription ADD COLUMN hwid_enabled INTEGER NOT NULL DEFAULT 0',
      );
      database.execute('ALTER TABLE subscription ADD COLUMN hwid TEXT');
      database.execute(
        "UPDATE subscription SET hwid_enabled = 1, hwid = 'keep-hwid'",
      );
    }
    if (version >= 5) {
      database.execute(
        'ALTER TABLE routing_profile ADD COLUMN advanced INTEGER NOT NULL DEFAULT 0',
      );
      database.execute('UPDATE routing_profile SET advanced = 1');
      database.execute(
        'ALTER TABLE geo_data ADD COLUMN installed INTEGER NOT NULL DEFAULT 1',
      );
      database.execute('UPDATE geo_data SET installed = 0');
    }
    if (version >= 6) {
      database.execute('''
        ALTER TABLE subscription ADD COLUMN upload_bytes INTEGER;
        ALTER TABLE subscription ADD COLUMN download_bytes INTEGER;
        ALTER TABLE subscription ADD COLUMN total_bytes INTEGER;
        ALTER TABLE subscription ADD COLUMN expire_timestamp INTEGER;
        ALTER TABLE subscription ADD COLUMN user_info_updated_at INTEGER;
        UPDATE subscription SET upload_bytes = 10, download_bytes = 20,
          total_bytes = 100, expire_timestamp = 1790812800,
          user_info_updated_at = 1234;
        UPDATE connection_config SET configuration_json =
          '{"connection":{"selection":{"kind":"region","region":"JP"},"smart":{"directRegions":["CN"]}}}';
      ''');
    }
    if (version >= 7) {
      database.execute('''
        ALTER TABLE core_config DROP COLUMN country_code;
        ALTER TABLE subscription ADD COLUMN panel TEXT NOT NULL DEFAULT 'generic';
        ALTER TABLE subscription ADD COLUMN mode TEXT NOT NULL DEFAULT 'appManaged';
        UPDATE subscription SET panel = 'remnawave', mode = 'providerManaged';
        INSERT INTO core_config
          (id, name, type, tags, data, delay, sub_id, favorite)
        VALUES (34, 'Provider profile', 'Remnawave', '', 'eyJkbnMiOnt9fQ==', -1, 7, 0);
      ''');
    }
    if (version >= 8) {
      database.execute('ALTER TABLE subscription ADD COLUMN user_agent TEXT');
      database.execute(
        "UPDATE subscription SET user_agent = 'Saved custom UA'",
      );
    }
    database.execute('PRAGMA user_version = $version');
  } finally {
    database.close();
  }
  return file;
}

void _expectNoUserInfo(SubscriptionData subscription) {
  expect(subscription.uploadBytes, isNull);
  expect(subscription.downloadBytes, isNull);
  expect(subscription.totalBytes, isNull);
  expect(subscription.expireTimestamp, isNull);
  expect(subscription.userInfoUpdatedAt, isNull);
}

Map<String, List<List<Object?>>> _snapshotV6(sqlite.Database database) => {
  ..._snapshotV5(database),
  'subscription': database
      .select(
        'SELECT id, name, url, timestamp, age_secret_key, age_public_key, hwid_enabled, hwid, upload_bytes, download_bytes, total_bytes, expire_timestamp, user_info_updated_at FROM subscription ORDER BY id',
      )
      .map((row) => row.values.toList())
      .toList(),
};

Map<String, List<List<Object?>>> _snapshotV5(sqlite.Database database) => {
  for (final table in [
    'subscription',
    'core_config',
    'geo_data',
    'routing_profile',
    'connection_config',
  ])
    table: database
        .select(
          table == 'subscription'
              ? 'SELECT id, name, url, timestamp, age_secret_key, age_public_key, hwid_enabled, hwid FROM subscription ORDER BY id'
              : table == 'core_config'
              ? 'SELECT id, name, type, tags, data, delay, sub_id, favorite FROM core_config ORDER BY id'
              : 'SELECT * FROM $table ORDER BY id',
        )
        .map((row) => row.values.toList())
        .toList(),
};

Map<String, List<List<Object?>>> _snapshotV3(sqlite.Database database) => {
  for (final table in [
    'subscription',
    'core_config',
    'geo_data',
    'routing_profile',
    'connection_config',
  ])
    table: database
        .select(
          table == 'subscription'
              ? 'SELECT id, name, url, timestamp, age_secret_key, age_public_key FROM subscription ORDER BY id'
              : table == 'routing_profile'
              ? 'SELECT id, name, data FROM routing_profile ORDER BY id'
              : table == 'geo_data'
              ? 'SELECT id, name, type, url, timestamp, category_count, rule_count FROM geo_data ORDER BY id'
              : table == 'core_config'
              ? 'SELECT id, name, type, tags, data, delay, sub_id, favorite FROM core_config ORDER BY id'
              : 'SELECT * FROM $table ORDER BY id',
        )
        .map((row) => row.values.toList())
        .toList(),
};

Future<Directory> _fixtureDirectory(String prefix) async {
  final fixtures = await Directory(
    '../references/onexray-refactor-validation/test-fixtures',
  ).absolute.create(recursive: true);
  return fixtures.createTemp(prefix);
}

Map<String, List<List<Object?>>> _snapshotFile(
  File file, {
  required bool hasAgeKeys,
}) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    return _snapshot(database, hasAgeKeys: hasAgeKeys);
  } finally {
    database.close();
  }
}

Map<String, List<List<Object?>>> _snapshot(
  sqlite.Database database, {
  required bool hasAgeKeys,
}) {
  final columns = {
    'core_config': 'id, name, type, tags, data, delay, sub_id',
    'subscription':
        'id, name, url, timestamp, '
        '${hasAgeKeys ? 'age_secret_key, age_public_key' : 'NULL, NULL'}',
    'geo_data': 'id, name, type, url, timestamp, category_count, rule_count',
  };
  return {
    for (final entry in columns.entries)
      entry.key: database
          .select('SELECT ${entry.value} FROM ${entry.key} ORDER BY id')
          .map((row) => row.values.toList())
          .toList(),
  };
}

Map<String, List<List<Object?>>> _afterUpgrade(
  Map<String, List<List<Object?>>> before,
) => {
  ...before,
  'core_config': [
    for (final row in before['core_config']!)
      [
        for (var index = 0; index < row.length; index++)
          if (row[2] == 'outbound' && index == 5)
            PingDelayConstants.unknown
          else
            row[index],
      ],
  ],
};
