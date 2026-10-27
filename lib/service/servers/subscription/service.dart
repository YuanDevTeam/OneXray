import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:onexray/core/errors/failure.dart';
import 'package:flutter/foundation.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/network/model.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/db/config_writer.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/in_flight_operations.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:onexray/service/servers/subscription/reader.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';
import 'package:onexray/service/servers/subscription/validator.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:uuid/uuid.dart';

final class SubscriptionLoadResult {
  const SubscriptionLoadResult({
    required this.status,
    this.rows = const [],
    this.error,
    this.userInfo,
    this.mode = SubscriptionMode.appManaged,
    this.convertedToOrdinary = false,
  });

  final SubscriptionUpdateResult status;
  final List<CoreConfigCompanion> rows;
  final Object? error;
  final SubscriptionUserInfo? userInfo;
  final SubscriptionMode mode;
  final bool convertedToOrdinary;

  int get count => rows
      .where(
        (row) =>
            row.type.present &&
            row.type.value ==
                (mode == SubscriptionMode.appManaged
                    ? CoreConfigType.outbound.name
                    : CoreConfigType.Remnawave.name),
      )
      .length;

  bool get hasUsableRows =>
      status == SubscriptionUpdateResult.success &&
      count > 0 &&
      rows.every(
        (row) =>
            row.type.present &&
            (row.type.value == CoreConfigType.outbound.name ||
                row.type.value == CoreConfigType.Remnawave.name),
      );
}

typedef SubscriptionReferenceReader =
    FutureOr<SubscriptionNodeReferences> Function();

final class _SupersededSubscriptionUpdate implements Exception {
  const _SupersededSubscriptionUpdate();
}

final class _PendingSubscriptionRefresh {
  _PendingSubscriptionRefresh(this.confirmOrdinary);

  SubscriptionFormatConfirmation? confirmOrdinary;
  late final Future<SubscriptionRefreshResult> result;

  Future<bool> confirm(String name) {
    final confirmation = confirmOrdinary;
    if (confirmation == null) {
      throw const RemnawaveResponseFormatException();
    }
    return confirmation(name);
  }
}

class SubscriptionService {
  static final SubscriptionService _singleton = SubscriptionService._internal();

  factory SubscriptionService() => _singleton;

  SubscriptionService._internal()
    : _databaseOverride = null,
      _loadRowsOverride = null,
      _configurationReaderOverride = null,
      _client = NetClient(),
      _pingOverride = null {
    referenceReader = _storedReferences;
  }

  @visibleForTesting
  SubscriptionService.forTesting({
    required AppDatabase database,
    Future<SubscriptionLoadResult> Function(SubscriptionInput)? loadRows,
    NetClient? client,
    SubscriptionConfigurationReader? configurationReader,
    required void Function(int) schedulePing,
    SubscriptionReferenceReader? readReferences,
  }) : _databaseOverride = database,
       _loadRowsOverride = loadRows,
       _configurationReaderOverride = configurationReader,
       _client = client ?? NetClient(),
       _pingOverride = schedulePing {
    referenceReader = readReferences ?? _storedReferences;
  }

  final AppDatabase? _databaseOverride;
  final NetClient _client;
  final Future<SubscriptionLoadResult> Function(SubscriptionInput)?
  _loadRowsOverride;
  final SubscriptionConfigurationReader? _configurationReaderOverride;
  final void Function(int)? _pingOverride;
  final _generations = <int, int>{};
  final _refreshes = <int, _PendingSubscriptionRefresh>{};
  Future<Map<SubscriptionData, SubscriptionRefreshResult>>? _refreshAll;
  SubscriptionFormatConfirmation? _refreshAllConfirmation;
  var _nextGeneration = 0;
  final _downloads = InFlightOperations();

  Future<void> pauseForDataClear() => _downloads.pause();

  void resumeAfterDataClear() => _downloads.resume();

  /// The database protects persisted selections before connection initialization.
  /// The coordinator replaces this reader to also protect live/prepared nodes.
  /// Favorites are checked in the same database transaction as replacement.
  late SubscriptionReferenceReader referenceReader;

  AppDatabase get _database => _databaseOverride ?? AppDatabase();

  /// An app-generated identity for one subscription, never a hardware ID.
  static String createHwid() => const Uuid().v4();

  Future<SubscriptionNodeReferences> _storedReferences() async {
    final value = jsonDecode(
      (await _database.connectionConfigDao.read()).configurationJson,
    ) as Map<String, dynamic>;
    final settings = ConnectionSettings.fromJson(
      value['connection'] as Map<String, dynamic>? ?? {},
    );
    return SubscriptionNodeReferences(
      fixedId: settings.selection.kind == SelectionKind.server
          ? settings.selection.id
          : null,
      finalExitId: settings.smart.finalExitId,
    );
  }

  void _schedulePing(int subId) {
    final schedule = _pingOverride;
    if (_downloads.isPaused) return;
    if (schedule != null) {
      schedule(subId);
    } else {
      PingService().schedulePingSubscription(subId);
    }
  }

  int _beginUpdate(int subId) {
    final generation = ++_nextGeneration;
    _generations[subId] = generation;
    return generation;
  }

  void _ensureCurrent(int subId, int generation) {
    if (_generations[subId] != generation) {
      throw const _SupersededSubscriptionUpdate();
    }
  }

  void _finishUpdate(int subId, int generation) {
    if (_generations[subId] == generation) {
      _generations.remove(subId);
    }
  }

  Future<SubscriptionInsertResult> insertSubscription(
    SubscriptionInput input, {
    SubscriptionFormatConfirmation? confirmOrdinary,
  }) => _downloads.track(
    () => _insertAndProbeSubscription(input, confirmOrdinary: confirmOrdinary),
  );

  Future<SubscriptionInsertResult> _insertAndProbeSubscription(
    SubscriptionInput input, {
    SubscriptionFormatConfirmation? confirmOrdinary,
  }) async {
    final result = await _insertSubscription(
      input,
      confirmOrdinary: confirmOrdinary,
    );

    if (result.success &&
        (await _database.subscriptionDao.searchRow(result.subId))?.mode ==
            SubscriptionMode.appManaged.name) {
      _schedulePing(result.subId);
    }

    return result;
  }

  Future<SubscriptionInsertResult> _insertSubscription(
    SubscriptionInput input, {
    SubscriptionFormatConfirmation? confirmOrdinary,
  }) async {
    final problem = SubscriptionValidator.validate(input);
    if (problem != null) return SubscriptionInsertResult(status: problem);
    try {
      if (await _database.subscriptionDao.urlExists(input.url)) {
        return const SubscriptionInsertResult(
          status: SubscriptionUpdateResult.duplicateUrl,
        );
      }
      if (input.hwidEnabled && input.hwid == null) {
        input = input.withHwid(createHwid());
      }
      final loaded = await _loadRows(input, confirmOrdinary: confirmOrdinary);
      if (!loaded.hasUsableRows ||
          (!loaded.convertedToOrdinary &&
              input.mode != null &&
              input.mode != loaded.mode)) {
        return SubscriptionInsertResult(
          error: loaded.error,
          status: loaded.status == SubscriptionUpdateResult.success
              ? SubscriptionUpdateResult.invalidContent
              : loaded.status,
        );
      }
      final rows = loaded.rows;
      final db = _database;
      return await db.transaction(() async {
        // A concurrent import may have completed while this source downloaded.
        if (await db.subscriptionDao.urlExists(input.url)) {
          return const SubscriptionInsertResult(
            status: SubscriptionUpdateResult.duplicateUrl,
          );
        }
        final row = SubscriptionCompanion.insert(
          name: input.name,
          url: input.url,
          userAgent: Value(input.normalizedUserAgent),
          panel: Value(
            loaded.convertedToOrdinary
                ? SubscriptionPanel.generic.name
                : input.panel.name,
          ),
          mode: Value(loaded.mode.name),
          ageSecretKey: Value(input.normalizedAgeSecretKey),
          agePublicKey: Value(input.normalizedAgePublicKey),
          hwidEnabled: Value(input.hwidEnabled),
          hwid: Value(input.hwid),
          timestamp: DateTime.now(),
          uploadBytes: Value(loaded.userInfo?.uploadBytes),
          downloadBytes: Value(loaded.userInfo?.downloadBytes),
          totalBytes: Value(loaded.userInfo?.totalBytes),
          expireTimestamp: Value(loaded.userInfo?.expireTimestamp),
          userInfoUpdatedAt: Value(loaded.userInfo?.updatedAt),
        );
        final nextSubId = await db.subscriptionDao.insertRow(row);
        if (nextSubId <= DBConstants.defaultId) {
          throw StateError('insert subscription failed');
        }
        await ConfigWriter.writeRowsBatchInTransaction(db, rows, nextSubId);
        return SubscriptionInsertResult(
          status: SubscriptionUpdateResult.success,
          subId: nextSubId,
          count: loaded.count,
        );
      });
    } catch (error, stackTrace) {
      ygLogger(
        'insert subscription failed (${error.runtimeType})\n$stackTrace',
      );
      return SubscriptionInsertResult(
        status: SubscriptionUpdateResult.writeFailed,
        error: error,
      );
    }
  }

  /// Editing a source changes future downloads, not its current node assets.
  Future<SubscriptionUpdateResult> saveSubscriptionInput(
    int id,
    SubscriptionInput input,
  ) async {
    final problem = SubscriptionValidator.validate(input);
    if (problem != null) return problem;
    _refreshes.remove(id);
    final generation = _beginUpdate(id);
    try {
      return await _database.transaction(() async {
        final row = await _database.subscriptionDao.searchRow(id);
        _ensureCurrent(id, generation);
        if (row == null) return SubscriptionUpdateResult.notFound;
        if (await _database.subscriptionDao.urlExists(
          input.url,
          excludingId: id,
        )) {
          return SubscriptionUpdateResult.duplicateUrl;
        }
        // Once generated, the identity belongs to this subscription, not its URL.
        final hwid =
            row.hwid ?? input.hwid ?? (input.hwidEnabled ? createHwid() : null);
        var next = row.copyWith(
          name: input.name,
          url: input.url,
          userAgent: Value(input.normalizedUserAgent),
          panel: input.panel.name,
          mode: input.mode?.name ?? row.mode,
          ageSecretKey: Value(input.normalizedAgeSecretKey),
          agePublicKey: Value(input.normalizedAgePublicKey),
          hwidEnabled: input.hwidEnabled,
          hwid: Value(hwid),
        );
        if (!_sameRequestSource(next, row)) {
          next = next.copyWith(
            uploadBytes: const Value(null),
            downloadBytes: const Value(null),
            totalBytes: const Value(null),
            expireTimestamp: const Value(null),
            userInfoUpdatedAt: const Value(null),
          );
        }
        final updated = await _database.subscriptionDao.updateRow(next);
        _ensureCurrent(id, generation);
        return updated
            ? SubscriptionUpdateResult.success
            : SubscriptionUpdateResult.writeFailed;
      });
    } on _SupersededSubscriptionUpdate {
      throw const AppFailure(
        FailureCategory.conflict,
        'changed',
        cause: 'The subscription changed during this operation. Reopen it and try again.',
      );
    } finally {
      _finishUpdate(id, generation);
    }
  }

  Future<SubscriptionModeAvailability> modeAvailability(int id) async {
    final source = await _database.subscriptionDao.searchRow(id);
    if (source == null) {
      throw const FormatException('Subscription no longer exists');
    }
    final rows = (await _database.coreConfigDao.allActiveServerRows())
        .where((row) => row.subId == id && ServerDisplay.fromRow(row).readable)
        .toList();
    final value = jsonDecode(
      (await _database.connectionConfigDao.read()).configurationJson,
    ) as Map<String, dynamic>;
    final settings = ConnectionSettings.fromJson(
      value['connection'] as Map<String, dynamic>? ?? {},
    );
    var selectedCompatible = true;
    if (settings.selection.kind == SelectionKind.server) {
      final selected = await _database.coreConfigDao.searchRow(
        settings.selection.id!,
      );
      if (selected == null) {
        selectedCompatible = false;
      } else if (selected.subId == id) {
        selectedCompatible = rows.any((row) => row.id == selected.id);
      }
    } else if (settings.selection.kind == SelectionKind.source &&
        settings.selection.id == id) {
      selectedCompatible = rows.isNotEmpty;
    }
    return SubscriptionModeAvailability(
      count: rows.length,
      selectedCompatible: selectedCompatible,
    );
  }

  /// The connection layer must confirm deletion and resolve affected running or
  /// persisted references before approving this destructive operation.
  Future<int> deleteSubscription(
    int id, {
    required Future<bool> Function(SubscriptionData) prepareDeletion,
  }) async {
    final db = _database;
    final source = await db.subscriptionDao.searchRow(id);
    if (source == null || !await prepareDeletion(source)) {
      return 0;
    }
    _refreshes.remove(id);
    final generation = _beginUpdate(id);
    try {
      return await db.transaction(() async {
        _ensureCurrent(id, generation);
        final current = await db.subscriptionDao.searchRow(id);
        if (current != source) {
          throw const _SupersededSubscriptionUpdate();
        }
        final deleted = await db.subscriptionDao.deleteRow(id);
        _ensureCurrent(id, generation);
        return deleted;
      });
    } on _SupersededSubscriptionUpdate {
      return 0;
    } finally {
      _finishUpdate(id, generation);
    }
  }

  /// Explicit refresh, independent of the automatic-update interval. Keep the
  /// whole batch visible to loading/clear-data without waiting for probes.
  Future<Map<SubscriptionData, SubscriptionRefreshResult>> refreshAll({
    SubscriptionFormatConfirmation? confirmOrdinary,
  }) {
    if (confirmOrdinary != null) {
      _refreshAllConfirmation = confirmOrdinary;
      if (_refreshAll != null) {
        for (final pending in _refreshes.values) {
          pending.confirmOrdinary = confirmOrdinary;
        }
      }
    }
    return _refreshAll ??= _downloads
        .track(
          () => AppEventBus.instance.trackDownload(() async {
            final results = <SubscriptionData, SubscriptionRefreshResult>{};
            for (final source in await _database.subscriptionDao.allRows) {
              if (_downloads.isPaused) {
                throw const AppFailure(FailureCategory.conflict, 'cancelled');
              }
              results[source] = await refreshSubscriptionResult(
                source,
                confirmOrdinary: _refreshAllConfirmation,
              );
            }
            if (_downloads.isPaused) {
              throw const AppFailure(FailureCategory.conflict, 'cancelled');
            }
            return results;
          }),
        )
        .whenComplete(() {
          _refreshAll = null;
          _refreshAllConfirmation = null;
        });
  }

  /// Prefer this result for reporting: an obsolete request is not a zero-node
  /// success, and unavailable parse statistics remain null.
  Future<SubscriptionRefreshResult> refreshSubscriptionResult(
    SubscriptionData subscription, {
    SubscriptionFormatConfirmation? confirmOrdinary,
  }) => _downloads.track(
    () => _refreshSubscriptionResult(
      subscription,
      confirmOrdinary: confirmOrdinary,
    ),
  );

  Future<SubscriptionRefreshResult> _refreshSubscriptionResult(
    SubscriptionData subscription, {
    SubscriptionFormatConfirmation? confirmOrdinary,
  }) {
    final pending = _refreshes[subscription.id];
    if (pending != null) {
      if (confirmOrdinary != null) pending.confirmOrdinary = confirmOrdinary;
      return pending.result;
    }
    if (_generations.containsKey(subscription.id)) {
      // A background refresh must not cancel an in-flight user edit/deletion.
      return Future.value(
        const SubscriptionRefreshResult(
          status: SubscriptionUpdateResult.writeFailed,
          superseded: true,
        ),
      );
    }
    final generation = _beginUpdate(subscription.id);
    final refresh = _PendingSubscriptionRefresh(confirmOrdinary);
    refresh.result =
        _refreshSubscription(
          subscription.id,
          generation,
          confirmOrdinary: refresh.confirm,
        ).whenComplete(() {
          if (identical(_refreshes[subscription.id], refresh)) {
            _refreshes.remove(subscription.id);
          }
          _finishUpdate(subscription.id, generation);
        });
    _refreshes[subscription.id] = refresh;
    return refresh.result;
  }

  Future<SubscriptionRefreshResult> _refreshSubscription(
    int id,
    int generation, {
    SubscriptionFormatConfirmation? confirmOrdinary,
  }) async {
    try {
      final subscription = await _database.subscriptionDao.searchRow(id);
      _ensureCurrent(id, generation);
      if (subscription == null) {
        return const SubscriptionRefreshResult(
          status: SubscriptionUpdateResult.notFound,
        );
      }
      final loaded = await _loadRows(
        SubscriptionInput(
          name: subscription.name,
          url: subscription.url,
          userAgent: subscription.userAgent,
          ageSecretKey: subscription.ageSecretKey,
          agePublicKey: subscription.agePublicKey,
          hwidEnabled: subscription.hwidEnabled,
          hwid: subscription.hwid,
          panel:
              SubscriptionPanel.fromString(subscription.panel) ??
              (throw const FormatException('Unsupported subscription panel')),
          mode:
              SubscriptionMode.fromString(subscription.mode) ??
              (throw const FormatException('Unsupported subscription mode')),
        ),
        confirmOrdinary: confirmOrdinary,
      );
      _ensureCurrent(id, generation);
      if (!loaded.hasUsableRows ||
          (!loaded.convertedToOrdinary &&
              loaded.mode.name != subscription.mode)) {
        return SubscriptionRefreshResult(
          error: loaded.error,
          status: loaded.status == SubscriptionUpdateResult.success
              ? SubscriptionUpdateResult.invalidContent
              : loaded.status,
        );
      }
      final result = await _replaceSubscription(
        subscription,
        loaded,
        generation,
      );
      if (result.success && loaded.mode == SubscriptionMode.appManaged) {
        _schedulePing(id);
      }
      return result;
    } on _SupersededSubscriptionUpdate {
      return const SubscriptionRefreshResult(
        status: SubscriptionUpdateResult.writeFailed,
        superseded: true,
      );
    } catch (error, stackTrace) {
      ygLogger(
        'refresh subscription failed (${error.runtimeType})\n$stackTrace',
      );
      return SubscriptionRefreshResult(
        status: SubscriptionUpdateResult.writeFailed,
        error: error,
      );
    }
  }

  Future<SubscriptionRefreshResult> _replaceSubscription(
    SubscriptionData expected,
    SubscriptionLoadResult loaded,
    int generation,
  ) {
    final db = _database;
    return db.transaction(() async {
      _ensureCurrent(expected.id, generation);
      final current = await db.subscriptionDao.searchRow(expected.id);
      if (current == null) {
        return const SubscriptionRefreshResult(
          status: SubscriptionUpdateResult.notFound,
        );
      }
      if (!_sameSource(current, expected)) {
        throw const _SupersededSubscriptionUpdate();
      }
      final references = await referenceReader();
      _ensureCurrent(expected.id, generation);
      await db.subscriptionDao.deleteConfigs(
        current.id,
        protectedIds: references.protectedIds,
      );
      await ConfigWriter.writeRowsBatchInTransaction(
        db,
        loaded.rows,
        current.id,
      );
      final updated = current.copyWith(
        panel: loaded.convertedToOrdinary
            ? SubscriptionPanel.generic.name
            : current.panel,
        mode: loaded.mode.name,
        timestamp: DateTime.now(),
        uploadBytes: Value(loaded.userInfo?.uploadBytes),
        downloadBytes: Value(loaded.userInfo?.downloadBytes),
        totalBytes: Value(loaded.userInfo?.totalBytes),
        expireTimestamp: Value(loaded.userInfo?.expireTimestamp),
        userInfoUpdatedAt: Value(loaded.userInfo?.updatedAt),
      );
      _ensureCurrent(expected.id, generation);
      if (!await db.subscriptionDao.updateRow(updated)) {
        throw StateError('update subscription failed');
      }
      _ensureCurrent(expected.id, generation);
      return SubscriptionRefreshResult(
        status: SubscriptionUpdateResult.success,
        count: loaded.count,
      );
    });
  }

  static bool _sameSource(
    SubscriptionData current,
    SubscriptionData expected,
  ) =>
      _sameRequestSource(current, expected) &&
      current.panel == expected.panel &&
      current.mode == expected.mode;

  static bool _sameRequestSource(
    SubscriptionData current,
    SubscriptionData expected,
  ) =>
      current.url == expected.url &&
      current.userAgent == expected.userAgent &&
      current.ageSecretKey == expected.ageSecretKey &&
      current.agePublicKey == expected.agePublicKey &&
      current.hwidEnabled == expected.hwidEnabled &&
      current.hwid == expected.hwid;

  Future<SubscriptionLoadResult> _loadRows(
    SubscriptionInput input, {
    SubscriptionFormatConfirmation? confirmOrdinary,
  }) => AppEventBus.instance.trackDownload(
    () => _readSubscription(input, confirmOrdinary: confirmOrdinary),
  );

  Future<SubscriptionLoadResult> _readSubscription(
    SubscriptionInput input, {
    SubscriptionFormatConfirmation? confirmOrdinary,
  }) async {
    if (input.hasIncompleteAgeKeyPair) {
      return const SubscriptionLoadResult(
        status: SubscriptionUpdateResult.invalidAgeSecretKey,
      );
    }
    final loadRows = _loadRowsOverride;
    if (loadRows != null) {
      return loadRows(input);
    }
    final ageContext = input.normalizedAgeContext;

    final String text;
    final SubscriptionUserInfo? userInfo;
    try {
      final response = await _client.getTextResponse(
        input.url,
        httpsOnly: true,
        requestHeaders: DownloadRequestHeaders(
          userAgent: input.normalizedUserAgent,
          agePublicKey: ageContext?.publicKey,
          hwid: input.hwidEnabled ? input.hwid : null,
        ),
      );
      final denied = _hwidErrorStatus(response.headers);
      if (denied != null) return SubscriptionLoadResult(status: denied);
      text = response.data ?? '';
      userInfo = SubscriptionUserInfo.parse(
        response.headers['subscription-userinfo']?.join(';'),
        updatedAt: DateTime.now(),
      );
    } catch (error) {
      if (error is DioException) {
        final denied = _hwidErrorStatus(error.response?.headers);
        if (denied != null) return SubscriptionLoadResult(status: denied);
      }
      return SubscriptionLoadResult(
        status: SubscriptionUpdateResult.downloadFailed,
        error: error,
      );
    }
    try {
      final reader =
          _configurationReaderOverride ?? SubscriptionConfigurationReader();
      final result = await reader.read(
        text,
        input,
        confirmOrdinary: confirmOrdinary,
      );
      return SubscriptionLoadResult(
        status: result.count == 0
            ? SubscriptionUpdateResult.invalidContent
            : SubscriptionUpdateResult.success,
        rows: result.rows,
        mode: result.mode,
        convertedToOrdinary: result.convertedToOrdinary,
        userInfo: userInfo,
      );
    } on RemnawaveResponseFormatException {
      return const SubscriptionLoadResult(
        status: SubscriptionUpdateResult.remnawaveFormatMismatch,
      );
    } on LibXrayInvokeException catch (error) {
      return SubscriptionLoadResult(
        status: _ageErrorStatus(error.message),
        error: error,
      );
    } catch (error, stackTrace) {
      if (!failureCancelled(error)) {
        ygLogger(
          'parse subscription failed (${error.runtimeType})\n$stackTrace',
        );
      }
      return SubscriptionLoadResult(
        status: SubscriptionUpdateResult.invalidContent,
        error: error,
      );
    }
  }

  static SubscriptionUpdateResult? _hwidErrorStatus(Headers? headers) {
    bool enabled(String name) =>
        headers?[name]?.any((value) => value.trim().toLowerCase() == 'true') ??
        false;
    if (enabled('x-hwid-not-supported')) {
      return SubscriptionUpdateResult.hwidRequired;
    }
    if (enabled('x-hwid-max-devices-reached')) {
      return SubscriptionUpdateResult.hwidLimitReached;
    }
    // Older providers use this for both missing IDs and device limits.
    if (enabled('x-hwid-limit')) return SubscriptionUpdateResult.hwidRejected;
    return null;
  }

  SubscriptionUpdateResult _ageErrorStatus(String error) {
    return switch (error) {
      LibXrayErrorMessage.invalidAgeSecretKey =>
        SubscriptionUpdateResult.invalidAgeSecretKey,
      LibXrayErrorMessage.missingAgeSecretKey =>
        SubscriptionUpdateResult.missingAgeSecretKey,
      LibXrayErrorMessage.ageDecryptFailed ||
      LibXrayErrorMessage.malformedAgeArmor =>
        SubscriptionUpdateResult.decryptFailed,
      LibXrayErrorMessage.agePlaintextTooLarge =>
        SubscriptionUpdateResult.contentTooLarge,
      LibXrayErrorMessage.agePlaintextUnsupported =>
        SubscriptionUpdateResult.invalidContent,
      _ => SubscriptionUpdateResult.invalidContent,
    };
  }

  Future<void> refreshOutdatedSubscription({
    AutoUpdateState? autoUpdateState,
    bool Function()? isCancelled,
  }) async {
    final updateState = autoUpdateState ?? AutoUpdateState();
    if (autoUpdateState == null) {
      await updateState.readFromPreferences();
    }
    if (!updateState.subscriptionEnabled) {
      return;
    }
    final interval = updateState.subscriptionInterval.value;
    final subs = await _database.subscriptionDao.allRows;
    final now = DateTime.now();
    for (final sub in subs) {
      if (_downloads.isPaused || (isCancelled?.call() ?? false)) break;
      if (now.difference(sub.timestamp).inHours >= interval) {
        await refreshSubscriptionResult(sub);
      }
    }
  }
}
