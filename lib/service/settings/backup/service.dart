import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/backup/codec.dart';
import 'package:onexray/core/backup/model.dart';
import 'package:onexray/core/backup/storage.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/settings/backup/assets.dart';
import 'package:onexray/service/settings/data_cleanup.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

enum BackupOperation { loading, saving, selecting, writing, reading, restoring }

enum BackupExistingAction { restore, overwrite }

typedef ResolveExistingBackup = Future<BackupExistingAction?> Function(
  BackupTarget target,
  Future<BackupPreview> Function() preview,
);

class BackupSettings {
  final BackupTarget? target;
  final DateTime? boundAt;
  final DateTime? lastSuccess;
  final DateTime? lastAttempt;
  const BackupSettings({
    this.target,
    this.boundAt,
    this.lastSuccess,
    this.lastAttempt,
  });

  bool get usesICloud => target?.identifier == backupContainerId;

  factory BackupSettings.fromJson(Map<String, dynamic> json) {
    // A legacy file selection was not a binding until the user confirmed it.
    if (json['confirmed'] == false) return const BackupSettings();
    return BackupSettings(
      target: json['target'] == null
          ? null
          : BackupTarget.fromJson(json['target'] as Map<String, dynamic>),
      boundAt: _date(json['boundAt']),
      lastSuccess: _date(json['lastSuccess']),
      lastAttempt: _date(json['lastAttempt']),
    );
  }
  Map<String, dynamic> toJson() => {
    'target': target?.toJson(),
    'boundAt': boundAt?.millisecondsSinceEpoch,
    'lastSuccess': lastSuccess?.millisecondsSinceEpoch,
    'lastAttempt': lastAttempt?.millisecondsSinceEpoch,
  };
  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.fromMillisecondsSinceEpoch(value as int);
}

class BackupState {
  final BackupSettings settings;
  final bool automatic;
  final bool changingAutomatic;
  final AutoUpdateInterval interval;
  final BackupOperation? operation;
  final Object? error;
  const BackupState({
    this.settings = const BackupSettings(),
    this.automatic = true,
    this.changingAutomatic = false,
    this.interval = AutoUpdateInterval.threeDays,
    this.operation,
    this.error,
  });

  BackupState copyWith({
    BackupSettings? settings,
    bool? automatic,
    bool? changingAutomatic,
    AutoUpdateInterval? interval,
    BackupOperation? operation,
    bool idle = false,
    Object? error,
    bool clearError = false,
  }) => BackupState(
    settings: settings ?? this.settings,
    automatic: automatic ?? this.automatic,
    changingAutomatic: changingAutomatic ?? this.changingAutomatic,
    interval: interval ?? this.interval,
    operation: idle ? null : operation ?? this.operation,
    error: clearError ? null : error ?? this.error,
  );
}

/// Device-local binding and schedule. These values never enter a backup file.
class BackupPreferences {
  Future<BackupSettings> read() async =>
      BackupSettings.fromJson(await PreferencesKey().readBackup() ?? {});
  Future<void> save(BackupSettings value) =>
      PreferencesKey().saveBackup(value.toJson());
  Future<bool> automatic() => PreferencesKey().readAutomaticBackup();
  Future<void> saveAutomatic(bool value) =>
      PreferencesKey().saveAutomaticBackup(value);
  Future<AutoUpdateInterval> interval() async => AutoUpdateInterval.fromInt(
    await PreferencesKey().readBackupInterval() ??
        AutoUpdateInterval.threeDays.value,
  );
  Future<void> saveInterval(AutoUpdateInterval value) =>
      PreferencesKey().saveBackupInterval(value.value);
}

class BackupPreview {
  final BackupDocument _document;
  final GeoDataRestorePlan _resources;
  const BackupPreview._(this._document, this._resources);
  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(_document.createdAt);
  int get nodes =>
      _document.coreConfigs.where((row) => row.type == 'outbound').length;
  int get raw => _document.coreConfigs.where((row) => row.type == 'raw').length;
  int get subscriptions => _document.subscriptions.length;
  int get groups => _document.manualGroups.length;
  int get routes => _document.routingProfiles.length;
  int get pending => _resources.pendingCount;
  List<String> get conflicts => [
    for (final row in _resources.conflicts) '${row.name}.dat',
  ];
  bool get empty => nodes + raw + subscriptions + routes + groups == 0;
}

/// Only backup operations are mutually exclusive. Ordinary save/probe/download
/// operations do not join this gate. Destructive restore uses the cleanup gate.
class BackupService extends Cubit<BackupState> {
  static final BackupService _singleton = BackupService._(
    PlatformBackupStorage(),
    BackupPreferences(),
    null,
    DateTime.now,
    null,
    PlatformBackupStorage.supported,
  );
  factory BackupService() => _singleton;
  BackupService._(
    this._storage,
    this._preferences,
    this._assetsInstance,
    this._now,
    this._restoreOverride,
    this._supported,
  ) : super(const BackupState());
  @visibleForTesting
  factory BackupService.forTesting({
    required BackupStorage storage,
    required BackupPreferences preferences,
    required BackupAssets assets,
    required DateTime Function() now,
    Future<void> Function(Future<void> Function())? restore,
  }) => BackupService._(storage, preferences, assets, now, restore, true);

  static bool get supported => PlatformBackupStorage.supported;
  final BackupStorage _storage;
  final BackupPreferences _preferences;
  BackupAssets? _assetsInstance;
  // Loading settings, unconfigured checks and teardown must not open storage.
  BackupAssets get _assets =>
      _assetsInstance ??= BackupAssets(AppDatabase(), GeoDataService());
  final DateTime Function() _now;
  final Future<void> Function(Future<void> Function())? _restoreOverride;
  final bool _supported;
  Completer<void>? _operation;
  Completer<void>? _toggle;
  bool _paused = false;
  int _automaticRevision = 0;

  Future<void> load() async {
    if (state.operation == BackupOperation.loading) {
      await _operation?.future;
      return;
    }
    if (_operation != null || _paused) return;
    try {
      await _run(BackupOperation.loading, _reload, clearError: false);
    } catch (_) {
      // _run exposes a local settings failure without affecting startup.
    }
  }

  Future<void> _reload({bool forAutomaticCheck = false}) async {
    final automaticRevision = _automaticRevision;
    final settings = await _preferences.read();
    final automatic = await _preferences.automatic();
    final interval =
        !forAutomaticCheck || (automatic && settings.target != null)
        ? await _preferences.interval()
        : state.interval;
    emit(
      state.copyWith(
        settings: settings,
        automatic: _toggle == null && automaticRevision == _automaticRevision
            ? automatic
            : state.automatic,
        interval: interval,
      ),
    );
  }

  Future<void> setAutomatic(bool enabled) async {
    if (_paused || _toggle != null) {
      throw StateError('Another backup setting operation is in progress.');
    }
    final task = Completer<void>();
    _toggle = task;
    _automaticRevision++;
    final previous = state.automatic;
    emit(state.copyWith(automatic: enabled, changingAutomatic: true));
    try {
      await _preferences.saveAutomatic(enabled);
    } catch (error) {
      emit(state.copyWith(automatic: previous, error: error));
      rethrow;
    } finally {
      _automaticRevision++;
      emit(state.copyWith(changingAutomatic: false));
      _toggle = null;
      task.complete();
    }
    if (enabled) unawaited(checkAutomatic());
  }

  Future<void> setInterval(AutoUpdateInterval value) =>
      _run(BackupOperation.saving, () async {
        await _preferences.saveInterval(value);
        emit(state.copyWith(interval: value));
      }, clearError: false);

  Future<bool> select({
    required bool create,
    bool local = false,
    ResolveExistingBackup? onExisting,
  }) => _run(BackupOperation.selecting, () async {
    await _reload();
    final selected = await _storage.select(create: create, local: local);
    if (selected == null) return false;
    final previous = state.settings;
    var bound = false;
    try {
      if (_paused) return false;
      final hasContents = await _storage.hasContents(selected);
      Future<BackupPreview>? preview;
      Future<BackupPreview> prepareRestore() => preview ??= _preview(selected);
      final action = hasContents
          ? await onExisting?.call(selected, prepareRestore)
          : null;
      if (_paused || (hasContents && action == null)) return false;
      BackupPreview? document;
      if (action == BackupExistingAction.restore) {
        document = await prepareRestore();
        if (_paused) return false;
      }
      // Only an imported backup starts a cycle without a successful file write.
      final settings = BackupSettings(
        target: selected,
        boundAt: action == BackupExistingAction.restore ? _now() : null,
      );
      await _preferences.save(settings);
      bound = true;
      emit(state.copyWith(settings: settings));
      if (document != null) {
        emit(state.copyWith(operation: BackupOperation.restoring));
        try {
          await _restore(document);
        } catch (_) {
          // Keep the new grant if rolling back persisted preferences also fails.
          await _preferences.save(previous);
          emit(state.copyWith(settings: previous));
          bound = false;
          rethrow;
        }
      }
      final previousTarget = previous.target;
      if (previousTarget != null &&
          previousTarget.identifier != selected.identifier) {
        await _storage.release(previousTarget);
      }
      if (action != BackupExistingAction.restore) {
        emit(state.copyWith(operation: BackupOperation.writing));
        await _write(automatic: false);
      }
      return true;
    } finally {
      if (!bound && previous.target?.identifier != selected.identifier) {
        await _storage.release(selected);
      }
    }
  });

  Future<bool> backupNow() => _run(BackupOperation.writing, () async {
    await _reload();
    return _write(automatic: false);
  });

  Future<void> unbind() => _run(BackupOperation.selecting, () async {
    await _reload();
    final target = state.settings.target;
    await _preferences.save(const BackupSettings());
    emit(state.copyWith(settings: const BackupSettings(), clearError: true));
    if (target != null) await _storage.release(target);
  });

  Future<void> checkAutomatic() async {
    if (!_supported) return;
    if (_paused || _operation != null || _toggle != null) return;
    try {
      await _run(BackupOperation.writing, () async {
        await _reload(forAutomaticCheck: true);
        final settings = state.settings;
        if (!state.automatic || settings.target == null) {
          return;
        }
        final now = _now();
        final lastBackup =
            settings.lastSuccess ??
            (settings.lastAttempt == null ? settings.boundAt : null);
        if (lastBackup != null &&
            now.difference(lastBackup) <
                Duration(hours: state.interval.value)) {
          return;
        }
        if (settings.lastAttempt != null &&
            now.difference(settings.lastAttempt!) < const Duration(hours: 1)) {
          return;
        }
        await _write(automatic: true);
      }, clearError: false);
    } catch (_) {
      // _run retains the actionable failure. Background failure never affects
      // startup, VPN status or the other update task, and never opens a window.
    }
  }

  Future<bool> _write({required bool automatic}) async {
    final target = _target();
    if (_paused || (automatic && !state.automatic)) return false;
    final attempted = BackupSettings(
      target: target,
      boundAt: state.settings.boundAt,
      lastSuccess: state.settings.lastSuccess,
      lastAttempt: _now(),
    );
    await _preferences.save(attempted);
    emit(state.copyWith(settings: attempted));
    final document = await _assets.capture();
    final bytes = await compute(_encode, document);
    // Disabling auto backup before provider I/O starts must take effect even
    // while a large document was being read/encoded.
    if (_paused || (automatic && !state.automatic)) return false;
    await _storage.write(target, bytes);
    final saved = BackupSettings(
      target: target,
      boundAt: attempted.boundAt,
      lastAttempt: attempted.lastAttempt,
      lastSuccess: _now(),
    );
    await _preferences.save(saved);
    emit(state.copyWith(settings: saved, clearError: true));
    return true;
  }

  Future<BackupPreview> preview() => _run(BackupOperation.reading, () async {
    await _reload();
    return _preview(_target());
  });

  Future<BackupPreview> _preview(BackupTarget target) async {
    final bytes = await _storage.read(target);
    final document = await compute(_decode, bytes);
    await _assets.validatePlatformSettings(document);
    return BackupPreview._(
      document,
      await _assets.geodata.previewRestore(backupSources(document)),
    );
  }

  Future<int> restore(BackupPreview preview) =>
      _run(BackupOperation.restoring, () => _restore(preview));

  Future<int> _restore(BackupPreview preview) async {
    // Backup I/O is already exclusive. The second gate exists only for clear
    // and restore, where all old producers must drain before replacing assets.
    Future<void> commit() =>
        _assets.restore(preview._document, preview._resources);
    if (_restoreOverride case final restore?) {
      await restore(commit);
    } else {
      await AppDataCleanupService().runForRestore(commit);
      ConnectionCoordinator.instance.clearTrafficView();
      AppEventBus.instance.clearPingFailures();
    }
    // No post-restore download is a success requirement. Saved subscriptions
    // and pending resources are discovered by the existing periodic/manual paths.
    return (await _assets.db.geoDataDao.allRows)
        .where((row) => !row.installed)
        .length;
  }

  BackupTarget _target() =>
      state.settings.target ??
      (throw StateError('Choose a backup location first.'));

  Future<T> _run<T>(
    BackupOperation operation,
    Future<T> Function() action, {
    bool clearError = true,
  }) async {
    if (_paused || _operation != null) {
      throw StateError('Another backup or restore operation is in progress.');
    }
    final task = Completer<void>();
    _operation = task;
    emit(state.copyWith(operation: operation, clearError: clearError));
    try {
      return await action();
    } catch (error) {
      emit(state.copyWith(error: error));
      rethrow;
    } finally {
      _operation = null;
      emit(state.copyWith(idle: true));
      task.complete();
    }
  }

  Future<void> pauseForDataClear() async {
    _paused = true;
    await Future.wait([
      if (_operation != null) _operation!.future,
      if (_toggle != null) _toggle!.future,
    ]);
  }

  void resumeAfterDataClear() {
    _paused = false;
    unawaited(load());
  }
}

Uint8List _encode(BackupDocument document) {
  validateBackupAssets(document);
  return encodeBackup(document);
}

BackupDocument _decode(Uint8List bytes) {
  final document = decodeBackup(bytes);
  validateBackupAssets(document);
  return document;
}
