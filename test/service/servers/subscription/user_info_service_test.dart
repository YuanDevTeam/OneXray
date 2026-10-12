import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

void main() {
  late AppDatabase database;
  final firstTime = DateTime.utc(2026, 9, 1);
  final nextTime = DateTime.utc(2026, 9, 22);
  const input = SubscriptionInput(
    name: 'Provider',
    url: 'https://example.com/sub',
  );
  final firstInfo = SubscriptionUserInfo(
    uploadBytes: 10,
    downloadBytes: 20,
    totalBytes: 100,
    expireTimestamp: 1790812800,
    updatedAt: firstTime,
  );

  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
    database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
  });

  SubscriptionLoadResult loaded(SubscriptionUserInfo? info) =>
      SubscriptionLoadResult(
        status: SubscriptionUpdateResult.success,
        rows: [
          outboundCompanion({'tag': 'Node', 'protocol': 'socks'}),
        ],
        userInfo: info,
      );

  SubscriptionService service(
    Future<SubscriptionLoadResult> Function(SubscriptionInput) load,
  ) => SubscriptionService.forTesting(
    database: database,
    loadRows: load,
    schedulePing: (_) {},
    readReferences: () => const SubscriptionNodeReferences(),
  );

  test(
    'insert and refresh commit metadata with nodes and stream updates',
    () async {
      var response = loaded(firstInfo);
      final subject = service((_) async => response);
      final inserted = await subject.insertSubscription(input);
      final source = (await database.subscriptionDao.searchRow(
        inserted.subId,
      ))!;
      expect(source.uploadBytes, 10);
      expect(source.downloadBytes, 20);
      expect(source.totalBytes, 100);
      expect(source.expireTimestamp, firstInfo.expireTimestamp);
      expect(source.userInfoUpdatedAt!.toUtc(), firstTime);
      final updated = database.subscriptionDao.allRowsStream.firstWhere(
        (rows) =>
            rows.single.userInfoUpdatedAt?.isAtSameMomentAs(nextTime) == true,
      );
      response = loaded(
        SubscriptionUserInfo(downloadBytes: 50, updatedAt: nextTime),
      );
      expect((await subject.refreshSubscriptionResult(source)).success, isTrue);
      final current = (await updated).single;
      expect(current.uploadBytes, isNull);
      expect(current.downloadBytes, 50);
      expect(current.totalBytes, isNull);
      expect(current.expireTimestamp, isNull);
      expect(current.userInfoUpdatedAt!.toUtc(), nextTime);
      response = loaded(null);
      expect(
        (await subject.refreshSubscriptionResult(current)).success,
        isTrue,
      );
      final withoutInfo = (await database.subscriptionDao.searchRow(
        source.id,
      ))!;
      expect(withoutInfo.downloadBytes, isNull);
      expect(withoutInfo.userInfoUpdatedAt, isNull);
    },
  );

  for (final failure in [
    SubscriptionUpdateResult.downloadFailed,
    SubscriptionUpdateResult.hwidRejected,
    SubscriptionUpdateResult.invalidContent,
    SubscriptionUpdateResult.success, // Zero nodes is not a valid replacement.
  ]) {
    test(
      '$failure with zero nodes preserves old metadata and timestamp',
      () async {
        var response = loaded(firstInfo);
        final subject = service((_) async => response);
        final inserted = await subject.insertSubscription(input);
        final source = (await database.subscriptionDao.searchRow(
          inserted.subId,
        ))!;
        final nodes = await database.coreConfigDao
            .allOutboundRowsWithDataBySubId(source.id);
        response = SubscriptionLoadResult(
          status: failure,
          userInfo: SubscriptionUserInfo(totalBytes: 0, updatedAt: nextTime),
        );
        expect(
          (await subject.refreshSubscriptionResult(source)).success,
          isFalse,
        );
        expect(await database.subscriptionDao.searchRow(source.id), source);
        expect(
          await database.coreConfigDao.allOutboundRowsWithDataBySubId(
            source.id,
          ),
          nodes,
        );
      },
    );
  }

  test('source edit clears cache; a rename alone retains it', () async {
    final subject = service((_) async => loaded(firstInfo));
    final edits = [
      const SubscriptionInput(
        name: 'Renamed',
        url: 'https://example.com/other',
      ),
      const SubscriptionInput(
        name: 'Renamed',
        url: 'https://example.com/sub',
        agePublicKey: 'public',
        ageSecretKey: 'secret',
      ),
      const SubscriptionInput(
        name: 'Renamed',
        url: 'https://example.com/sub',
        hwidEnabled: true,
      ),
    ];
    for (final edit in edits) {
      final inserted = await subject.insertSubscription(input);
      final source = (await database.subscriptionDao.searchRow(
        inserted.subId,
      ))!;
      await subject.saveSubscriptionInput(
        source.id,
        const SubscriptionInput(
          name: 'Renamed',
          url: 'https://example.com/sub',
        ),
      );
      expect(
        (await database.subscriptionDao.searchRow(source.id))!
            .userInfoUpdatedAt!
            .toUtc(),
        firstTime,
      );
      expect(
        await subject.saveSubscriptionInput(source.id, edit),
        SubscriptionUpdateResult.success,
      );
      final changed = (await database.subscriptionDao.searchRow(source.id))!;
      expect(changed.uploadBytes, isNull);
      expect(changed.downloadBytes, isNull);
      expect(changed.totalBytes, isNull);
      expect(changed.expireTimestamp, isNull);
      expect(changed.userInfoUpdatedAt, isNull);
      await subject.deleteSubscription(
        source.id,
        prepareDeletion: (_) async => true,
      );
    }
  });

  test(
    'mode and panel edits retain package cache, timestamp and node data',
    () async {
      var downloads = 0;
      final subject = service((_) async {
        downloads++;
        return loaded(firstInfo);
      });
      final inserted = await subject.insertSubscription(input);
      final original = (await database.subscriptionDao.searchRow(
        inserted.subId,
      ))!;
      final nodes = await database.coreConfigDao.allOutboundRowsWithDataBySubId(
        original.id,
      );
      final status = await subject.saveSubscriptionInput(
        original.id,
        const SubscriptionInput(
          name: 'Provider',
          url: 'https://example.com/sub',
          panel: SubscriptionPanel.remnawave,
          mode: SubscriptionMode.providerManaged,
        ),
      );
      expect(status, SubscriptionUpdateResult.success);
      expect(downloads, 1);
      final changed = (await database.subscriptionDao.searchRow(original.id))!;
      expect(changed.panel, 'remnawave');
      expect(changed.mode, 'providerManaged');
      expect(changed.timestamp, original.timestamp);
      expect(changed.uploadBytes, original.uploadBytes);
      expect(changed.downloadBytes, original.downloadBytes);
      expect(changed.totalBytes, original.totalBytes);
      expect(changed.expireTimestamp, original.expireTimestamp);
      expect(changed.userInfoUpdatedAt, original.userInfoUpdatedAt);
      expect(
        await database.coreConfigDao.allOutboundRowsWithDataBySubId(
          original.id,
        ),
        nodes,
      );

      await subject.saveSubscriptionInput(
        original.id,
        const SubscriptionInput(
          name: 'Renamed',
          url: 'https://example.com/sub',
          panel: SubscriptionPanel.remnawave,
        ),
      );
      expect(
        (await database.subscriptionDao.searchRow(original.id))!.mode,
        'providerManaged',
      );
    },
  );

  test(
    'mode edit supersedes an earlier response without clearing package cache',
    () async {
      final response = Completer<SubscriptionLoadResult>();
      final started = Completer<void>();
      var refreshing = false;
      final subject = service((_) async {
        if (!refreshing) return loaded(firstInfo);
        started.complete();
        return response.future;
      });
      final inserted = await subject.insertSubscription(input);
      final source = (await database.subscriptionDao.searchRow(
        inserted.subId,
      ))!;
      refreshing = true;
      final pending = subject.refreshSubscriptionResult(source);
      await started.future;
      await subject.saveSubscriptionInput(
        source.id,
        const SubscriptionInput(
          name: 'Provider',
          url: 'https://example.com/sub',
          mode: SubscriptionMode.providerManaged,
        ),
      );
      response.complete(loaded(null));
      expect((await pending).superseded, isTrue);
      final changed = (await database.subscriptionDao.searchRow(source.id))!;
      expect(changed.mode, 'providerManaged');
      expect(changed.totalBytes, source.totalBytes);
      expect(changed.userInfoUpdatedAt, source.userInfoUpdatedAt);
      expect(changed.timestamp, source.timestamp);
    },
  );

  for (final delete in [false, true]) {
    test(
      'late metadata cannot undo ${delete ? 'deletion' : 'source editing'}',
      () async {
        final response = Completer<SubscriptionLoadResult>();
        final started = Completer<void>();
        var refreshing = false;
        final subject = service((_) {
          if (!refreshing) return Future.value(loaded(firstInfo));
          started.complete();
          return response.future;
        });
        final inserted = await subject.insertSubscription(input);
        final source = (await database.subscriptionDao.searchRow(
          inserted.subId,
        ))!;
        refreshing = true;
        final pending = subject.refreshSubscriptionResult(source);
        await started.future;
        if (delete) {
          await subject.deleteSubscription(
            source.id,
            prepareDeletion: (_) async => true,
          );
        } else {
          await subject.saveSubscriptionInput(
            source.id,
            const SubscriptionInput(
              name: 'New',
              url: 'https://example.com/new',
            ),
          );
        }
        response.complete(loaded(firstInfo));
        expect((await pending).superseded, isTrue);
        final current = await database.subscriptionDao.searchRow(source.id);
        if (delete) {
          expect(current, isNull);
        } else {
          expect(current!.url, 'https://example.com/new');
          expect(current.userInfoUpdatedAt, isNull);
        }
      },
    );
  }

  test(
    'transaction failure rolls back metadata together with node replacement',
    () async {
      var response = loaded(firstInfo);
      final subject = service((_) async => response);
      final inserted = await subject.insertSubscription(input);
      final source = (await database.subscriptionDao.searchRow(
        inserted.subId,
      ))!;
      final localId = await database.coreConfigDao.insertRow(
        outboundCompanion({'tag': 'Local', 'protocol': 'socks'}),
      );
      response = SubscriptionLoadResult(
        status: SubscriptionUpdateResult.success,
        rows: [
          outboundCompanion({'tag': 'Conflict', 'protocol': 'socks'})
              .copyWith(id: Value(localId)),
        ],
        userInfo: SubscriptionUserInfo(totalBytes: 0, updatedAt: nextTime),
      );
      expect(
        (await subject.refreshSubscriptionResult(source)).status,
        SubscriptionUpdateResult.writeFailed,
      );
      expect(await database.subscriptionDao.searchRow(source.id), source);
      expect(
        (await database.coreConfigDao.allOutboundRowsWithDataBySubId(source.id))
            .single
            .name,
        'Node',
      );
    },
  );
}
