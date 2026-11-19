import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/model/geo_dat.dart';
import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/gen/assets.gen.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/advanced/xray/geodata/download.dart';
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:onexray/service/advanced/xray/geodata/system_state.dart';
import 'package:onexray/service/shared/in_flight_operations.dart';
import 'package:onexray/service/shared/command_serial_executor.dart';
import 'package:onexray/service/shared/xray/provider_geodata.dart';
import 'package:path/path.dart' as p;

/// Runs a confirmed save against staged dependencies. The callback includes
/// writeMetadata in the same database transaction as its configuration write.
/// File publication, rollback and cleanup remain private to this module.
abstract interface class GeoDataImport {
  Future<T> save<T>(
    Future<T> Function(Future<void> Function() writeMetadata) action,
  );
  Future<void> dispose();
}

/// All installed Geodata lives directly in one flat directory. Downloads and
/// rollback backups use short-lived sibling directories only.
class GeoDataService {
  Future<Map<int, Object>>? _updateAll;
  static final GeoDataService _singleton = GeoDataService._(
    null,
    null,
    downloadGeoData,
    _countNative,
    copyBundledTo,
  );
  factory GeoDataService() => _singleton;
  GeoDataService._(
    this._database,
    this._directory,
    this._downloadFile,
    this._count,
    this._copyBundled,
  );

  factory GeoDataService.forTesting({
    required AppDatabase database,
    required String directory,
    required Future<void> Function(String, File) download,
    required Future<void> Function(String, String, GeoDataType) count,
    required Future<void> Function(String) copyBundled,
  }) => GeoDataService._(database, directory, download, count, copyBundled);

  final AppDatabase? _database;
  final String? _directory;
  final Future<void> Function(String, File) _downloadFile;
  final Future<void> Function(String, String, GeoDataType) _count;
  final Future<void> Function(String) _copyBundled;
  final _commands = CommandSerialExecutor();
  final _updates = InFlightOperations();

  Future<void> pauseForDataClear() => _updates.pause();

  void resumeAfterDataClear() => _updates.resume();
  final _fileScopeKey = Object();
  Object? _fileScope;
  final _activeImportStages = <String>{};
  bool _installationPrepared = false;
  AppDatabase get _db => _database ?? AppDatabase();
  String get _root => _directory ?? VpnConstants.datDir;

  static final _defaults =
      <({int id, String name, GeoDataType type, String url})>[
        (
          id: SystemGeoDatId.geoIp.id,
          name: SystemGeoDatName.geoIp.name,
          type: GeoDataType.ip,
          url: SystemGeoDatURL.geoIp.name,
        ),
        (
          id: SystemGeoDatId.geoSite.id,
          name: SystemGeoDatName.geoSite.name,
          type: GeoDataType.domain,
          url: SystemGeoDatURL.geoSite.name,
        ),
      ];

  /// Only readers/publications of the canonical directory share this queue.
  /// Downloads and indexing of independent staging files stay outside it.
  Future<T> withFiles<T>(Future<T> Function() action) {
    if (_fileScope != null &&
        identical(Zone.current[_fileScopeKey], _fileScope)) {
      return action();
    }
    return _commands.run(() async {
      final scope = Object();
      _fileScope = scope;
      try {
        return await runZoned(action, zoneValues: {_fileScopeKey: scope});
      } finally {
        _fileScope = null;
      }
    });
  }

  Future<void> _download(String url, File destination) =>
      AppEventBus.instance.trackDownload(() => _downloadFile(url, destination));

  Future<void> ensureInstalled({bool resetOrphanedFiles = false}) =>
      withFiles(() async {
        await _ensureInstalled(resetOrphanedFiles: resetOrphanedFiles);
        _installationPrepared = true;
      });

  /// App data cleanup already paused updates and owns the file queue.
  Future<void> resetAfterDataClear() =>
      withFiles(() => _ensureInstalled(resetOrphanedFiles: true));

  Future<void> _ensureInstalled({bool resetOrphanedFiles = false}) async {
    final root = Directory(_root);
    final rootWasMissing = !await root.exists();
    await _ensureRoot();
    _checkDefaultRows(await _db.geoDataDao.allSources);
    if (!_installationPrepared || rootWasMissing || resetOrphanedFiles) {
      await _recoverRestoredFiles(discard: rootWasMissing);
      await _recoverImportDrafts(
        await _db.geoDataDao.publishedRows,
        discard: rootWasMissing,
      );
    }
    final rows = await _db.geoDataDao.publishedRows;
    final existing = await _flatNames(root);
    final resetPublication =
        rootWasMissing ||
        (existing.isEmpty && rows.isNotEmpty) ||
        (resetOrphanedFiles && rows.isEmpty);
    if (!resetPublication && await _defaultFilesPresent()) {
      if (_defaults.every((source) => rows.any((row) => row.id == source.id))) {
        return;
      }
      // Older releases did not register the default pair. Reuse existing files
      // when their indexes can supply metadata; unrelated files are not a gate.
      try {
        await _db.transaction(() async {
          await _publishDefaults(_root, await _assetTimestamp(_root));
        });
        return;
      } on FormatException {
        // Unreadable default indexes are replaced with the bundled pair below.
      }
    }

    // Only missing/empty default resources require a local replacement. Existing
    // custom data and stray entries never participate in startup validation.
    final stage = await _newStage('install-');
    _FlatFileChange? change;
    try {
      await _copyBundled(stage.path);
      final indexes = <String, XrayGeoList>{};
      for (final source in _defaults) {
        indexes[source.name] = await _index(
          stage.path,
          source.name,
          source.type,
        );
      }
      final timestamp = await _assetTimestamp(stage.path);
      change = resetPublication
          ? await _replaceAll(stage)
          : await _applyFiles(await _stageFiles(stage));
      await _commitPublication(change, () async {
        if (resetPublication) {
          await _db.geoDataDao.clearPublished();
        }
        await _publishDefaults(_root, timestamp, indexes: indexes);
      });
    } finally {
      if (change == null) await _deleteStage(stage);
    }
  }

  Future<bool> _defaultFilesPresent() async {
    for (final source in _defaults) {
      for (final suffix in ['dat', 'json']) {
        final file = File(p.join(_root, '${source.name}.$suffix'));
        if (!await file.exists() || await file.length() == 0) return false;
      }
    }
    return true;
  }

  /// Only registered dependencies of the selected runtime are checked. This
  /// does not download, validate Xray semantics or block unrelated configs.
  Future<void> requireDependencies(
    Map<String, GeoDataType> references,
  ) => withFiles(() async {
    for (final file in references.keys) {
      if (isProviderGeoDataFileName(file)) {
        try {
          await _regularFile(File(p.join(_root, file)));
        } on FormatException {
          throw FileSystemException(
            'Provider routing data is unavailable. Refresh the subscription.',
            file,
          );
        }
        continue;
      }
      final row = await _db.geoDataDao.searchRowByName(
        file.substring(0, file.length - 4),
      );
      if (row != null &&
          (!row.installed || !await File(p.join(_root, file)).exists())) {
        throw FileSystemException(
          'Routing data is not downloaded. Download it in Advanced > Xray > Routing data.',
          file,
        );
      }
    }
  });

  Stream<List<GeoDataFile>> watchPublished() =>
      _db.geoDataDao.publishedRowsStream.asyncMap(
        (rows) => withFiles(
          () async => [for (final row in rows) await _readSummary(row)],
        ),
      );

  Stream<PublishedGeoData?> watchFile(int id) => _db.geoDataDao
      .watchPublishedRow(id)
      .asyncMap(
        (row) => withFiles(
          () async => row == null ? null : await _readPublished(row),
        ),
      );

  Stream<List<GeoDataData>> watchPending() => _db.geoDataDao.allSourcesStream
      .map((rows) => rows.where((row) => !row.installed).toList());

  Future<GeoDataRestorePlan> previewRestore(
    List<GeoDataInput> sources,
  ) => withFiles(() async {
    final rows = await _db.geoDataDao.allRows;
    final reusable = <String, GeoDataData>{};
    final conflicts = <GeoDataData>[];
    for (final source in sources) {
      _requireCustomFileName(GeoDataInput.canonicalFileName(source.fileName));
      final old = rows
          .where((row) => row.name.toLowerCase() == source.name.toLowerCase())
          .firstOrNull;
      if (old == null) continue;
      if (old.name == source.name &&
          old.type == source.type.name &&
          old.url == source.url) {
        if (old.installed) {
          try {
            await _readPublished(old);
            reusable[source.name] = old;
          } on FileSystemException {
            // Unavailable candidates remain pending; unrelated files are not read.
          } on FormatException {
            // Invalid indexes are downloaded again after an offline restore.
          }
        }
      } else {
        conflicts.add(old);
      }
    }
    return GeoDataRestorePlan(
      sources: sources,
      reusable: reusable,
      conflicts: conflicts,
    );
  });

  /// Offline restoration of declarations. The caller replaces connection
  /// assets in the same DB transaction as writeMetadata. No download or index
  /// generation is needed for sources that are intentionally pending.
  Future<T> restoreSources<T>(
    GeoDataRestorePlan preview,
    Future<T> Function(Future<void> Function() writeMetadata) action,
  ) => withFiles(() async {
    final current = await previewRestore(preview.sources);
    if (current.conflicts.any((row) => !preview.conflicts.contains(row))) {
      throw const AppFailure(FailureCategory.conflict, 'changed');
    }
    final removals = (await _db.geoDataDao.allRows)
        .where(
          (row) => row.installed && current.reusable[row.name]?.id != row.id,
        )
        .toList();
    Directory? journal;
    var committed = false;
    try {
      if (removals.isNotEmpty) {
        journal = await _newStage('restore-');
        await File(p.join(journal.path, 'restore.json')).writeAsString(
          jsonEncode([
            for (final row in removals) {'id': row.id, 'name': row.name},
          ]),
          flush: true,
        );
        for (final row in removals) {
          _checkName(row.name);
          for (final suffix in ['dat', 'json']) {
            final name = '${row.name}.$suffix';
            final file = File(p.join(_root, name));
            final type = await FileSystemEntity.type(
              file.path,
              followLinks: false,
            );
            if (type == FileSystemEntityType.notFound) continue;
            if (type != FileSystemEntityType.file) {
              throw FileSystemException(
                'Routing data must be a regular file',
                file.path,
              );
            }
            await file.rename(p.join(journal.path, name));
          }
        }
      }
      final result = await _db.transaction(
        () => action(() async {
          await _db.geoDataDao.clearCustom();
          for (final source in current.sources) {
            final previous = current.reusable[source.name];
            await _db.geoDataDao.insertRow(
              GeoDataCompanion.insert(
                name: source.name,
                type: source.type.name,
                url: source.url,
                timestamp:
                    previous?.timestamp ??
                    DateTime.fromMillisecondsSinceEpoch(0),
                categoryCount: previous?.categoryCount ?? 0,
                ruleCount: previous?.ruleCount ?? 0,
                installed: Value(previous != null),
              ),
            );
          }
        }),
      );
      committed = true;
      return result;
    } finally {
      if (journal != null) {
        if (!committed) {
          await _recoverRestoreJournal(journal, discard: false);
        } else {
          try {
            await _deleteStage(journal);
          } catch (_) {
            // New IDs prove the DB commit on the next cold start.
          }
        }
      }
    }
  });

  Future<void> _recoverRestoredFiles({required bool discard}) async {
    final parent = Directory(p.dirname(_root));
    await for (final entry in parent.list(followLinks: false)) {
      if (entry is Directory &&
          p.basename(entry.path).startsWith('.onexray-geodata-restore-')) {
        await _recoverRestoreJournal(entry, discard: discard);
      }
    }
  }

  Future<void> _recoverRestoreJournal(
    Directory journal, {
    required bool discard,
  }) async {
    final manifest = File(p.join(journal.path, 'restore.json'));
    if (!await manifest.exists()) {
      if ((await _flatNames(journal)).isEmpty) await _deleteStage(journal);
      return;
    }
    final entries = jsonDecode(await manifest.readAsString());
    if (entries is! List) throw StateError('Invalid Geodata restore journal');
    for (final entry in entries) {
      if (entry is! Map || entry['id'] is! int || entry['name'] is! String) {
        throw StateError('Invalid Geodata restore journal');
      }
      final id = entry['id'] as int;
      final name = entry['name'] as String;
      _checkName(name);
      if (id <= 0) throw StateError('Invalid Geodata restore identity');
      final old = await _db.geoDataDao.searchRow(id);
      if (!discard && old != null && old.installed && old.name == name) {
        for (final suffix in ['dat', 'json']) {
          final previous = File(p.join(journal.path, '$name.$suffix'));
          if (!await previous.exists()) continue;
          final target = File(p.join(_root, '$name.$suffix'));
          if (await target.exists()) {
            throw StateError('Conflicting Geodata restore files');
          }
          await previous.rename(target.path);
        }
      }
    }
    await _deleteStage(journal);
  }

  Future<void> add(GeoDataInput input) {
    final normalized = GeoDataInput(
      fileName: GeoDataInput.canonicalFileName(input.fileName),
      type: input.type,
      url: input.url.trim(),
    );
    return _updates.track(() async {
      final draft = await prepareImports([normalized]);
      try {
        await draft.save((writeMetadata) => _db.transaction(writeMetadata));
      } finally {
        await draft.dispose();
      }
    });
  }

  /// Manual updates keep independent failures, including a failed default pair.
  /// A caller may display the result, but never reconnects as part of an update.
  Future<Map<int, Object>> updateAll() => _updateAll ??= _updates
      .track(
        () => AppEventBus.instance.trackDownload(() async {
          final errors = <int, Object>{};
          final custom = await _db.geoDataDao.allRows;
          try {
            await updateDefaults();
          } catch (error) {
            errors[-1] = error;
          }
          for (final file in custom) {
            if (_updates.isPaused) {
              throw const AppFailure(FailureCategory.conflict, 'cancelled');
            }
            try {
              await updateCustom(file);
            } catch (error) {
              errors[file.id] = error;
            }
          }
          if (_updates.isPaused) {
            throw const AppFailure(FailureCategory.conflict, 'cancelled');
          }
          return errors;
        }),
      )
      .whenComplete(() => _updateAll = null);

  Future<void> updateDefaults() => _updates.track(() async {
    final stage = await _newStage('download-');
    _FlatFileChange? change;
    try {
      final indexes = <String, XrayGeoList>{};
      for (final source in _defaults) {
        await _download(
          source.url,
          File(p.join(stage.path, '${source.name}.dat')),
        );
        indexes[source.name] = await _index(
          stage.path,
          source.name,
          source.type,
        );
      }
      await withFiles(() async {
        change = await _applyFiles(await _stageFiles(stage));
        await _commitPublication(
          change!,
          () => _publishDefaults(_root, DateTime.now(), indexes: indexes),
        );
      });
    } finally {
      if (change == null) await _deleteStage(stage);
    }
  });

  Future<void> updateCustom(GeoDataData original) => _updates.track(() async {
    if (original.id <= 0) {
      throw StateError('Default routing data updates together');
    }
    _checkName(original.name);
    GeoDataInput.httpsUri(original.url);
    final stage = await _newStage('download-');
    _FlatFileChange? change;
    try {
      await _download(
        original.url,
        File(p.join(stage.path, '${original.name}.dat')),
      );
      final index = await _index(
        stage.path,
        original.name,
        _type(original.type),
      );
      await withFiles(() async {
        change = await _applyFiles(await _stageFiles(stage));
        await _commitPublication(change!, () async {
          final current = await _db.geoDataDao.searchRow(original.id);
          if (current == null || current != original) {
            throw StateError('Routing data source changed during update');
          }
          if (!await _db.geoDataDao.updateRow(
            current.copyWith(
              timestamp: DateTime.now(),
              categoryCount: index.categoryCount!,
              ruleCount: index.ruleCount!,
              installed: true,
            ),
          )) {
            throw StateError('Routing data source is unavailable');
          }
        });
      });
    } finally {
      if (change == null) await _deleteStage(stage);
    }
  });

  Future<void> deleteGeoDat(GeoDataData row) => withFiles(() async {
    if (row.id <= 0) {
      throw StateError('Default routing data cannot be deleted');
    }
    _checkName(row.name);
    final change = await _applyFiles({
      '${row.name}.dat': null,
      '${row.name}.json': null,
    });
    await _commitPublication(change, () async {
      final current = await _db.geoDataDao.searchRow(row.id);
      if (current == null || current != row) {
        throw StateError('Routing data source changed before deletion');
      }
      if (await _db.geoDataDao.deleteRow(row.id) != 1) {
        throw StateError('Routing data source is unavailable');
      }
    });
  });

  Future<void> _commitPublication(
    _FlatFileChange change,
    Future<void> Function() writeMetadata,
  ) async {
    try {
      await _db.transaction(writeMetadata);
    } catch (_) {
      await change.rollback();
      rethrow;
    }
    // Cleanup cannot roll back files whose metadata already committed.
    await change.complete();
  }

  /// Validate new resources before exposing them under immutable names. The
  /// action validates the Provider configs and commits them with this binding
  /// while the file publication queue is held.
  Future<T> withProviderAssets<T>(
    ProviderGeoDataUrls urls, {
    required String scope,
    required Future<T> Function(ProviderGeoDataBinding binding) action,
    required bool Function(T result) committed,
  }) => _updates.track(() async {
    final stage = await _newStage('provider-');
    final stagePath = p.normalize(stage.path);
    _activeImportStages.add(stagePath);
    try {
      final sources = [
        if (urls.geoIpUrl case final url?)
          (name: 'geoip', type: GeoDataType.ip, url: url),
        if (urls.geoSiteUrl case final url?)
          (name: 'geosite', type: GeoDataType.domain, url: url),
      ];
      final scopeDigest = sha256.convert(utf8.encode(scope));
      final filenames = <String, String>{};
      final stagedFiles = <String, ({File data, Digest digest})>{};
      for (final source in sources) {
        GeoDataInput.httpsUri(source.url);
        final data = File(p.join(stage.path, '${source.name}.dat'));
        await _download(source.url, data);
        await _index(stage.path, source.name, source.type);
        final digest = await sha256.bind(data.openRead()).first;
        final version = sha256.convert([...scopeDigest.bytes, ...digest.bytes]);
        final filename = 'onexray-provider-${source.name}-$version.dat';
        filenames[source.name] = filename;
        final namedData = await data.rename(p.join(stage.path, filename));
        stagedFiles[filename] = (data: namedData, digest: digest);
      }
      final binding = ProviderGeoDataBinding(
        geoIpFile: filenames['geoip'],
        geoSiteFile: filenames['geosite'],
        geoIpUrl: urls.geoIpUrl,
        geoSiteUrl: urls.geoSiteUrl,
      );
      return await withFiles(() async {
        final customNames = {
          for (final row in await _db.geoDataDao.allRows)
            '${row.name}.dat'.toLowerCase(),
        };
        final additions = <String, File>{};
        for (final entry in stagedFiles.entries) {
          final filename = entry.key;
          if (customNames.contains(filename)) {
            throw const FormatException(
              'Provider routing data name is occupied',
            );
          }
          final installed = File(p.join(_root, filename));
          if (await FileSystemEntity.type(installed.path, followLinks: false) ==
              FileSystemEntityType.notFound) {
            additions[filename] = entry.value.data;
            continue;
          }
          await _regularFile(installed);
          if (await sha256.bind(installed.openRead()).first !=
              entry.value.digest) {
            throw const FormatException('Provider routing data is damaged');
          }
        }
        final change = additions.isEmpty ? null : await _applyFiles(additions);
        return _commitProviderAssets(change, () => action(binding), committed);
      });
    } finally {
      try {
        await _deleteStage(stage);
      } on FileSystemException {
        // A completed configuration/file transaction remains committed.
        // Cold-start recovery removes an idle Provider staging directory.
      } finally {
        _activeImportStages.remove(stagePath);
      }
    }
  });

  Future<T> _commitProviderAssets<T>(
    _FlatFileChange? change,
    Future<T> Function() action,
    bool Function(T result) committed,
  ) async {
    final T result;
    final bool keep;
    try {
      result = await action();
      keep = committed(result);
    } catch (_) {
      await change?.rollback();
      rethrow;
    }
    if (keep) {
      try {
        await change?.complete();
      } on FileSystemException {
        // The new aliases were already published and their DB references
        // committed. Never report a transaction failure for cleanup alone.
      }
    } else {
      await change?.rollback();
    }
    return result;
  }

  /// Prepare private staging files only. A later confirmed save publishes them
  /// while the caller commits metadata with its configuration.
  Future<GeoDataImport> prepareImports(List<GeoDataInput> inputs) async {
    if (inputs.isEmpty) {
      throw ArgumentError.value(inputs, 'inputs', 'No Geodata dependencies');
    }
    final sources = List<GeoDataInput>.unmodifiable(inputs);
    for (final source in sources) {
      if (GeoDataInput.canonicalFileName(source.fileName) != source.fileName) {
        throw const FormatException('Geodata filename is not canonical');
      }
      _requireCustomFileName(source.fileName);
      GeoDataInput.httpsUri(source.url);
    }
    await withFiles(() async {
      await _ensureRoot();
      await _checkConflicts(sources, checkFiles: true);
    });
    final draft = _GeoDataImportDraft(
      this,
      await _newStage('import-'),
      sources,
    );
    await draft._prepare();
    return draft;
  }

  Future<void> _publishDefaults(
    String directory,
    DateTime timestamp, {
    Map<String, XrayGeoList>? indexes,
  }) async {
    final existing = await _db.geoDataDao.allSources;
    _checkDefaultRows(existing);
    for (final source in _defaults) {
      await _regularFile(File(p.join(directory, '${source.name}.dat')));
      final index =
          indexes?[source.name] ??
          await _readIndex(File(p.join(directory, '${source.name}.json')));
      final old = existing.where((row) => row.id == source.id).firstOrNull;
      final next = GeoDataCompanion.insert(
        id: Value(source.id),
        name: source.name,
        type: source.type.name,
        url: source.url,
        timestamp: timestamp,
        categoryCount: index.categoryCount!,
        ruleCount: index.ruleCount!,
      );
      if (old == null) {
        await _db.geoDataDao.insertRow(next);
      } else if (!await _db.geoDataDao.updateRow(
        old.copyWith(
          timestamp: timestamp,
          categoryCount: index.categoryCount!,
          ruleCount: index.ruleCount!,
          installed: true,
        ),
      )) {
        throw StateError('Default routing data is unavailable');
      }
    }
  }

  Future<void> _recoverImportDrafts(
    List<GeoDataData> rows, {
    required bool discard,
  }) async {
    final parent = Directory(p.dirname(_root));
    if (!await parent.exists()) return;
    final registered = {for (final row in rows) row.name.toLowerCase()};
    await for (final entry in parent.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final directoryName = p.basename(entry.path);
      final stageIsActive = _activeImportStages.contains(
        p.normalize(entry.path),
      );
      if (directoryName.startsWith('.onexray-geodata-provider-')) {
        if (!stageIsActive) await _deleteStage(entry);
        continue;
      }
      if (directoryName.startsWith('.onexray-geodata-backup-')) {
        if ((await _flatNames(entry)).isEmpty) await _deleteStage(entry);
        continue;
      }
      if (!directoryName.startsWith('.onexray-geodata-import-') ||
          stageIsActive) {
        continue;
      }
      for (final name in await _flatNames(entry)) {
        _checkFileName(name);
        final extension = p.extension(name).toLowerCase();
        if (extension != '.dat' && extension != '.json') {
          throw StateError('Invalid routing data import journal');
        }
        final basename = p.basenameWithoutExtension(name).toLowerCase();
        final target = File(p.join(_root, name));
        if (!discard && registered.contains(basename)) {
          if (!await target.exists()) {
            await _copyFile(File(p.join(entry.path, name)), target);
          }
        } else if (await target.exists()) {
          await target.delete();
        }
      }
      await _deleteStage(entry);
    }
  }

  void _checkDefaultRows(List<GeoDataData> rows) {
    for (final row in rows) {
      final expected = _defaults
          .where((value) => value.id == row.id)
          .firstOrNull;
      if ((row.id <= 0 &&
              (expected == null ||
                  row.name != expected.name ||
                  row.type != expected.type.name)) ||
          (row.id > 0 &&
              {'geoip', 'geosite'}.contains(row.name.toLowerCase()))) {
        throw StateError('Reserved routing data identity is occupied');
      }
    }
  }

  Future<GeoDataFile> _readSummary(GeoDataData row) async {
    final data = File(p.join(_root, '${row.name}.dat'));
    final index = File(p.join(_root, '${row.name}.json'));
    try {
      await _ensureRoot();
      _checkDefaultRows([row]);
      _checkName(row.name);
      await _regularFile(data);
      await _regularFile(index, limit: 32 * 1024 * 1024);
      return GeoDataFile(
        row: row,
        data: data,
        indexFile: index,
        bytes: await data.length(),
      );
    } catch (error) {
      return GeoDataFile(
        row: row,
        data: data,
        indexFile: index,
        failure: error,
      );
    }
  }

  Future<PublishedGeoData> _readPublished(GeoDataData row) async {
    await _ensureRoot();
    _checkDefaultRows([row]);
    _checkName(row.name);
    final data = File(p.join(_root, '${row.name}.dat'));
    final index = File(p.join(_root, '${row.name}.json'));
    await _regularFile(data);
    return PublishedGeoData(
      row: row,
      data: data,
      indexFile: index,
      index: await _readIndex(index),
      bytes: await data.length(),
    );
  }

  Future<void> _checkConflicts(
    List<GeoDataInput> sources, {
    required bool checkFiles,
  }) async {
    final names = <String>{};
    final files = <String>{};
    for (final source in sources) {
      if (!names.add(source.name.toLowerCase())) {
        throw const FormatException('Duplicate Geodata filename');
      }
      files.addAll({
        source.fileName.toLowerCase(),
        '${source.name}.json'.toLowerCase(),
      });
    }
    final rows = await _db.geoDataDao.allSources;
    if (rows.any((row) => names.contains(row.name.toLowerCase()))) {
      throw const FormatException('Geodata filename already exists');
    }
    if (checkFiles) {
      for (final name in await _flatNames(Directory(_root))) {
        if (files.contains(name.toLowerCase())) {
          throw const FormatException('Geodata filename already exists');
        }
      }
    }
  }

  Future<void> _ensureRoot() async {
    if (_root.isEmpty) {
      throw StateError('Routing data directory is unavailable');
    }
    final root = Directory(_root);
    await root.create(recursive: true);
  }

  Future<Directory> _newStage(String prefix) async {
    if (_root.isEmpty) {
      throw StateError('Routing data directory is unavailable');
    }
    final parent = Directory(p.dirname(_root));
    await parent.create(recursive: true);
    return parent.createTemp('.onexray-geodata-$prefix');
  }

  Future<Map<String, File?>> _stageFiles(Directory stage) async => {
    for (final name in await _flatNames(stage))
      name: File(p.join(stage.path, name)),
  };

  Future<_FlatFileChange> _replaceAll(Directory stage) async {
    await _ensureRoot();
    final replacements = <String, File?>{
      for (final name in await _flatNames(Directory(_root))) name: null,
      ...await _stageFiles(stage),
    };
    return _applyFiles(replacements);
  }

  Future<_FlatFileChange> _applyFiles(
    Map<String, File?> replacements, {
    bool retainSources = false,
  }) async {
    await _ensureRoot();
    final backup = await _newStage('backup-');
    final changed = _FlatFileChange(
      root: Directory(_root),
      backup: backup,
      sources: {
        for (final entry in replacements.entries)
          entry.key: entry.value?.parent,
      },
      sourcesRetained: retainSources,
    );
    try {
      for (final entry in replacements.entries) {
        _checkFileName(entry.key);
        final target = File(p.join(_root, entry.key));
        final type = await FileSystemEntity.type(
          target.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file) {
          await target.rename(p.join(backup.path, entry.key));
          changed.backedUp.add(entry.key);
        } else if (type != FileSystemEntityType.notFound) {
          throw StateError('Invalid routing data file');
        }
        final source = entry.value;
        if (source != null) {
          await _regularFile(source);
          if (retainSources) {
            await _copyFile(source, target);
          } else {
            await source.rename(target.path);
          }
          changed.installed.add(entry.key);
        }
      }
      return changed;
    } catch (_) {
      await changed.rollback();
      rethrow;
    }
  }

  Future<XrayGeoList> _index(
    String directory,
    String name,
    GeoDataType type,
  ) async {
    final data = File(p.join(directory, '$name.dat'));
    await _regularFile(data);
    await _count(directory, name, type);
    final file = File(p.join(directory, '$name.json'));
    final index = await _readIndex(file);
    await file.writeAsString(jsonEncode(index.toJson()), flush: true);
    return index;
  }

  Future<XrayGeoList> _readIndex(File file) async {
    await _regularFile(file, limit: 32 * 1024 * 1024);
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid Geodata index');
    }
    final XrayGeoList index;
    try {
      index = XrayGeoList.fromJson(value);
    } on TypeError {
      throw const FormatException('Invalid Geodata index');
    }
    if ((index.categoryCount ?? 0) <= 0 ||
        (index.ruleCount ?? 0) <= 0 ||
        index.codes == null ||
        index.codes!.isEmpty ||
        index.codes!.any(
          (entry) =>
              entry.code == null ||
              entry.code!.isEmpty ||
              (entry.ruleCount ?? -1) < 0,
        )) {
      throw const FormatException('Invalid Geodata index');
    }
    return index;
  }

  static Future<Set<String>> _flatNames(Directory directory) async {
    if (!await directory.exists()) return {};
    final names = <String>{};
    await for (final entry in directory.list(followLinks: false)) {
      if (await FileSystemEntity.type(entry.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final name = p.basename(entry.path);
      names.add(name);
    }
    return names;
  }

  static Future<void> _regularFile(
    File file, {
    int limit = 512 * 1024 * 1024,
  }) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('Routing data file is unavailable');
    }
    final length = await file.length();
    if (length <= 0 || length > limit) {
      throw const FormatException('Invalid routing data file size');
    }
  }

  static Future<void> _copyFile(File source, File target) async {
    await _regularFile(source);
    final sink = target.openWrite();
    try {
      await sink.addStream(source.openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<void> _deleteStage(Directory stage) async {
    final expectedParent = p.normalize(p.dirname(_root));
    if (p.normalize(p.dirname(stage.path)) != expectedParent ||
        !p.basename(stage.path).startsWith('.onexray-geodata-')) {
      throw StateError('Invalid Geodata staging directory');
    }
    if (await stage.exists()) await stage.delete(recursive: true);
  }

  static void _checkFileName(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        p.posix.basename(name) != name ||
        p.windows.basename(name) != name ||
        name.contains(RegExp(r'[\\/:\x00-\x1f\x7f]'))) {
      throw const FormatException('Invalid routing data filename');
    }
  }

  static void _checkName(String name) => _checkFileName(name);

  static void _requireCustomFileName(String filename) {
    if (isProviderGeoDataFileName(filename.toLowerCase())) {
      throw const FormatException(
        'Provider routing data filenames are reserved',
      );
    }
  }

  static GeoDataType _type(String type) => GeoDataType.values.firstWhere(
    (value) => value.name == type,
    orElse: () => throw const FormatException('Invalid Geodata type'),
  );

  static Future<DateTime> _assetTimestamp(String directory) async {
    final file = File(p.join(directory, VpnConstants.systemGeoTimestamp));
    if (await file.exists()) {
      await _regularFile(file, limit: 64);
      final seconds = int.tryParse((await file.readAsString()).trim());
      if (seconds != null && seconds > 0) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }
    return File(p.join(directory, 'geoip.dat')).lastModified();
  }

  static Future<void> _countNative(
    String directory,
    String name,
    GeoDataType type,
  ) async {
    final error = await AppHostApi().countGeoData(
      CountGeoDataRequest(name, type.name, datDir: directory),
    );
    if (error.isNotEmpty) throw const FormatException('Geodata parsing failed');
  }

  static Future<void> copyBundledTo(String destination) async {
    await Directory(destination).create(recursive: true);
    for (final asset in Assets.dat.values) {
      final data = await rootBundle.load(asset);
      await File(p.join(destination, p.basename(asset))).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
  }
}

final class _GeoDataImportDraft implements GeoDataImport {
  final GeoDataService _files;
  final Directory _stage;
  final List<GeoDataInput> _sources;
  final _indexes = <String, XrayGeoList>{};
  _FlatFileChange? _change;
  bool _completed = false;
  bool _disposed = false;

  _GeoDataImportDraft(this._files, this._stage, this._sources) {
    _files._activeImportStages.add(p.normalize(_stage.path));
  }

  Future<void> _prepare() async {
    try {
      for (final source in _sources) {
        await _files._download(
          source.url,
          File(p.join(_stage.path, source.fileName)),
        );
        _indexes[source.name] = await _files._index(
          _stage.path,
          source.name,
          source.type,
        );
      }
      await _files.withFiles(
        () => _files._checkConflicts(_sources, checkFiles: true),
      );
    } catch (_) {
      await _files._deleteStage(_stage);
      _files._activeImportStages.remove(p.normalize(_stage.path));
      rethrow;
    }
  }

  @override
  Future<T> save<T>(
    Future<T> Function(Future<void> Function() writeMetadata) action,
  ) => _files.withFiles(() async {
    await _publish();
    final T result;
    try {
      result = await action(_writeMetadata);
      await _confirmMetadata();
    } catch (error, stackTrace) {
      await _rollback();
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _complete();
    return result;
  });

  Future<void> _publish() async {
    if (_disposed || _completed) {
      throw StateError('Routing data draft is unavailable');
    }
    if (_change != null) return;
    await _files._checkConflicts(_sources, checkFiles: true);
    _change = await _files._applyFiles(
      await _files._stageFiles(_stage),
      retainSources: true,
    );
  }

  Future<void> _writeMetadata() async {
    if (_disposed || _completed || _change == null) {
      throw StateError('Routing data draft is not published');
    }
    await _files._db.transaction(() async {
      await _files._checkConflicts(_sources, checkFiles: false);
      final timestamp = DateTime.now();
      for (final source in _sources) {
        await GeoDataService._regularFile(
          File(p.join(_files._root, source.fileName)),
        );
        await GeoDataService._regularFile(
          File(p.join(_files._root, '${source.name}.json')),
          limit: 32 * 1024 * 1024,
        );
        final index = _indexes[source.name]!;
        await _files._db.geoDataDao.insertRow(
          GeoDataCompanion.insert(
            name: source.name,
            type: source.type.name,
            url: source.url,
            timestamp: timestamp,
            categoryCount: index.categoryCount!,
            ruleCount: index.ruleCount!,
          ),
        );
      }
    });
  }

  Future<Set<String>> _publishedNames() async =>
      (await _files._db.geoDataDao.publishedRows)
          .map((row) => row.name.toLowerCase())
          .toSet();

  Future<void> _confirmMetadata() async {
    if (_completed) return;
    if (_disposed || _change == null) {
      throw StateError('Routing data draft was not committed');
    }
    final names = await _publishedNames();
    if (!_sources.every(
      (source) => names.contains(source.name.toLowerCase()),
    )) {
      throw StateError('Routing data metadata was not committed');
    }
  }

  Future<void> _complete() async {
    if (_completed) return;
    final current = _change!;
    _change = null;
    _completed = true;
    _files._activeImportStages.remove(p.normalize(_stage.path));
    try {
      await current.complete();
    } catch (_) {
      // Metadata already committed. Cold recovery finishes journal cleanup.
    }
  }

  Future<void> _rollback() async {
    if (_disposed || _completed || _change == null) return;
    final names = await _publishedNames();
    if (_sources.any((source) => names.contains(source.name.toLowerCase()))) {
      throw StateError('Committed routing data cannot be rolled back');
    }
    await _change!.rollback(preserveSources: true);
    _change = null;
  }

  @override
  Future<void> dispose() => _files.withFiles(_dispose);

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_completed) return;
    final current = _change;
    if (current == null) {
      await _files._deleteStage(_stage);
      _files._activeImportStages.remove(p.normalize(_stage.path));
      return;
    }
    final names = await _publishedNames();
    if (_sources.every((source) => names.contains(source.name.toLowerCase()))) {
      await current.complete();
    } else if (_sources.every(
      (source) => !names.contains(source.name.toLowerCase()),
    )) {
      await current.rollback();
    } else {
      // Preserve files if an externally corrupted transaction exposes only
      // part of the manifest; deleting them would create a database orphan.
      await current.complete();
      throw StateError('Routing data metadata is incomplete');
    }
    _change = null;
    _files._activeImportStages.remove(p.normalize(_stage.path));
  }
}

final class _FlatFileChange {
  final Directory root;
  final Directory backup;
  final Map<String, Directory?> sources;
  final bool sourcesRetained;
  final Set<String> backedUp = {};
  final Set<String> installed = {};
  bool _finished = false;

  _FlatFileChange({
    required this.root,
    required this.backup,
    required this.sources,
    required this.sourcesRetained,
  });

  Future<void> rollback({bool preserveSources = false}) async {
    if (_finished) return;
    await root.create(recursive: true);
    for (final name in installed) {
      final current = File(p.join(root.path, name));
      if (!await current.exists()) continue;
      final source = sources[name];
      if (preserveSources && source != null) {
        if (sourcesRetained) {
          await current.delete();
        } else {
          await source.create(recursive: true);
          await current.rename(p.join(source.path, name));
        }
      } else {
        await current.delete();
      }
    }
    for (final name in backedUp) {
      final previous = File(p.join(backup.path, name));
      if (await previous.exists()) {
        await previous.rename(p.join(root.path, name));
      }
    }
    _finished = true;
    await _cleanup(deleteSources: !preserveSources);
  }

  Future<void> complete() async {
    if (_finished) return;
    _finished = true;
    await _cleanup();
  }

  Future<void> _cleanup({bool deleteSources = true}) async {
    if (await backup.exists()) await backup.delete(recursive: true);
    if (deleteSources) {
      for (final directory in sources.values.whereType<Directory>().toSet()) {
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    }
  }
}
