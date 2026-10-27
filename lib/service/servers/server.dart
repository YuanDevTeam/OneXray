import 'dart:convert';

import 'package:onexray/core/errors/failure.dart';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/asset_edit.dart';
import 'package:onexray/service/connect/preparation.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/raw/editor.dart';
import 'package:onexray/service/connect/raw/validator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:onexray/service/shared/xray/validation.dart';
import 'package:onexray/service/shared/xray/remnawave.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/manual_groups.dart';

class ServerEditDraft {
  final CoreConfigData original;
  final String text;
  const ServerEditDraft(this.original, this.text);
}

class ServerRemoval {
  final Set<int> ids;
  final int? sourceId;
  final int? manualGroupId;
  final ConnectionConfiguration configuration;
  final String expectedConfiguration;
  final bool affectsRuntime;
  final bool disconnect;
  const ServerRemoval({
    required this.ids,
    this.sourceId,
    this.manualGroupId,
    required this.configuration,
    required this.expectedConfiguration,
    required this.affectsRuntime,
    required this.disconnect,
  });
}

/// Asset changes use the same commit/rollback boundary as connection changes.
/// Candidate measurements and favorites never mutate the active runtime.
class ServerAssetService {
  final AppDatabase db;
  final ConnectionCoordinator coordinator;
  final Future<String> Function(String) _validate;
  final void Function(List<int>) _schedule;
  final SubscriptionService _subscriptions;
  final Future<ConnectionRuntime> Function(
    ConnectionConfiguration,
    Future<void>,
    Map<int, ResolvedServer>,
    Set<int>,
  )?
  prepare;

  ServerAssetService({
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
    Future<String> Function(String)? validate,
    void Function(List<int>)? schedule,
    SubscriptionService? subscriptions,
    this.prepare,
  }) : db = database ?? AppDatabase(),
       coordinator = coordinator ?? ConnectionCoordinator.instance,
       _validate = validate ?? AppHostApi().testXray,
       _subscriptions = subscriptions ?? SubscriptionService(),
       _schedule = schedule ?? PingService().schedulePingConfigIds;

  Stream<List<CoreConfigData>> watch() => db.coreConfigDao.watchServers();

  Future<List<CoreConfigData>> rows() =>
      (db.select(db.coreConfig)..where(
            (row) => row.type.isIn([
              CoreConfigType.outbound.name,
              CoreConfigType.Remnawave.name,
            ]),
          ))
          .get();

  static bool measured(CoreConfigData row) =>
      row.type == CoreConfigType.outbound.name &&
      row.delay != PingDelayConstants.unknown;

  static bool healthy(CoreConfigData row) =>
      row.type == CoreConfigType.outbound.name &&
      PingDelayConstants.isSuccessful(row.delay);

  static bool selectable(CoreConfigData row) {
    if (row.type == CoreConfigType.Remnawave.name) {
      return ServerDisplay.fromRow(row).readable;
    }
    if (measured(row) && !healthy(row)) return false;
    try {
      ResolvedServer.fromRow(row);
      return true;
    } on FormatException {
      return false;
    }
  }

  static String protocolLabel(CoreConfigData row) {
    if (row.type != CoreConfigType.outbound.name) return '';
    try {
      return outboundProtocolLabel(readOutboundFromDbData(row));
    } on FormatException {
      return '';
    }
  }

  Future<ServerEditDraft> load(int id) async {
    final row = await db.coreConfigDao.searchRow(id);
    if (row == null || row.type != 'outbound') {
      throw const FormatException('Server no longer exists');
    }
    String text;
    try {
      text = const JsonEncoder.withIndent('  ')
          .convert(readOutboundFromDbData(row));
    } on FormatException {
      text = row.data == null ? '{}' : utf8.decode(base64Decode(row.data!));
    }
    return ServerEditDraft(row, text);
  }

  /// A UI snapshot cannot select a cache after its source mode has changed.
  Future<void> validateSelection(ServerSelection selection) async {
    if (selection.kind == SelectionKind.automatic) return;
    if (selection.kind == SelectionKind.source) {
      if (selection.id == DBConstants.defaultId) return;
      final source = await db.subscriptionDao.searchRow(selection.id!);
      if (source == null) {
        throw const FormatException('Subscription no longer exists');
      }
      return;
    }
    final row = await db.coreConfigDao.searchActiveServerRow(selection.id!);
    if (row == null || !ServerDisplay.fromRow(row).readable) {
      throw const FormatException(
        'The selected configuration is unavailable in the subscription mode',
      );
    }
  }

  /// Provider JSON is viewed as stored; it is never projected to one outbound.
  Future<ServerEditDraft> loadComplete(int id) async {
    final row = await db.coreConfigDao.searchRow(id);
    if (row == null ||
        row.type != CoreConfigType.Remnawave.name ||
        await db.subscriptionDao.searchRow(row.subId) == null) {
      throw const FormatException('Provider configuration no longer exists');
    }
    ResolvedProfile.fromRow(row);
    return ServerEditDraft(row, utf8.decode(base64Decode(row.data!)));
  }

  /// A personal Raw is a separate asset, validated and limited by its editor.
  Future<int> copyAsRaw(int id, {String? name}) async {
    final draft = await loadComplete(id);
    final config = RemnawaveAdapter.adapt(
      jsonDecode(draft.text) as Map<String, dynamic>,
    );
    final saved =
        await RawEditorService(
          database: db,
          coordinator: coordinator,
          validate: (text) async {
            await XrayRawValidator.validateParsed(
              XrayRawValidator.normalize(text),
              testXray: _validate,
            );
          },
        ).save(
          RawEditorDraft(
            name: name ?? draft.original.name,
            text: jsonEncode(config),
          ),
          confirmReconnect: () async => false,
        );
    if (saved == null) throw const RawEditorException('changed');
    return saved;
  }

  Future<bool> save(
    ServerEditDraft draft, {
    required Future<bool> Function() confirmReconnect,
  }) async {
    if (draft.original.type != CoreConfigType.outbound.name) {
      throw const FormatException('A provider configuration is read-only');
    }
    if (utf8.encode(draft.text).length > 16 * 1024 * 1024) {
      throw const FormatException('Server configuration is too large');
    }
    final outbound = jsonDecode(draft.text);
    if (outbound is! Map<String, dynamic>) {
      throw const FormatException('An outbound object is required');
    }
    final validation = await _validate(XrayValidation.nodes([outbound]));
    if (validation.isNotEmpty) {
      throw AppFailure(
        FailureCategory.configuration,
        'xrayValidation',
        cause: validation,
      );
    }
    final configuration = await coordinator.readForEditing();
    final original = draft.original;
    var semanticChange = true;
    try {
      semanticChange = !const DeepCollectionEquality().equals(
        {...readOutboundFromDbData(original)}..remove('tag'),
        {...outbound}..remove('tag'),
      );
    } on FormatException {
      // A repaired legacy row is not a metadata-only edit.
    }
    final active =
        coordinator.state.value.runtime?.nodeIds.contains(original.id) == true;
    final affectsRuntime = semanticChange && active;
    final companion = outboundCompanion(outbound);
    final drafts = {
      original.id: ResolvedServer(
        id: original.id,
        sourceId: original.subId,
        outbound: outbound,
      ),
    };
    final saved = await coordinator.saveEditedAsset(
      configuration,
      confirmReconnect: confirmReconnect,
      affectsRuntime: affectsRuntime,
      prepare: affectsRuntime
          ? (next, cancelled) => _prepare(next, cancelled, drafts, const {})
          : null,
      writeAssets: () async {
        if (semanticChange &&
            !affectsRuntime &&
            coordinator.state.value.runtime?.nodeIds.contains(original.id) ==
                true) {
          throw const FormatException('Server became active while editing');
        }
        final current = await db.coreConfigDao.searchRow(original.id);
        if (current == null ||
            current.type != 'outbound' ||
            current.data != original.data) {
          throw const FormatException('Server changed while editing');
        }
        await db.coreConfigDao.updateRow(
          current.copyWith(
            name: companion.name.value,
            tags: companion.tags.value,
            data: companion.data,
            delay: semanticChange ? PingDelayConstants.unknown : current.delay,
          ),
        );
      },
    );
    if (saved && semanticChange) _schedule([original.id]);
    return saved;
  }

  Future<void> favorite(int id, bool value) async {
    await (db.update(db.coreConfig)..where(
          (row) =>
              row.id.equals(id) &
              row.type.isIn([
                CoreConfigType.outbound.name,
                CoreConfigType.Remnawave.name,
              ]),
        ))
        .write(CoreConfigCompanion(favorite: Value(value)));
  }

  Future<int> copyLocal(CoreConfigData row, String suffix) async {
    final id = await db.transaction(() async {
      final current = await db.coreConfigDao.searchRow(row.id);
      if (current == null || current.type != 'outbound') {
        throw const FormatException('Server no longer exists');
      }
      final outbound = readOutboundFromDbData(current);
      outbound['tag'] = '${outboundDisplayName(outbound)} · $suffix';
      return db.coreConfigDao.insertAssetRow(
        outboundCompanion(outbound).copyWith(favorite: const Value(false)),
      );
    });
    _schedule([id]);
    return id;
  }

  Future<ServerRemoval> previewRemoval({
    Set<int> ids = const {},
    int? sourceId,
    int? manualGroupId,
  }) async {
    if (manualGroupId != null && sourceId != null) {
      throw ArgumentError('Choose a subscription or a manual group');
    }
    if (manualGroupId != null &&
        await db.manualServerGroupDao.searchRow(manualGroupId) == null) {
      throw const FormatException('Manual group no longer exists');
    }
    final current = await coordinator.readForEditing();
    final all = await rows();
    final removed = manualGroupId != null
        ? all
              .where(
                (row) =>
                    ManualServerGroupService.isManual(row) &&
                    row.manualGroupId == manualGroupId,
              )
              .map((row) => row.id)
              .toSet()
        : sourceId == null
        ? ids
        : all
              .where((row) => row.subId == sourceId)
              .map((row) => row.id)
              .toSet();
    final remaining = all.where((row) => !removed.contains(row.id)).toList();
    final activeServerIds = (await db.coreConfigDao.allActiveServerRows())
        .map((row) => row.id)
        .toSet();
    final selection = current.connection.selection;
    final invalidSelection = switch (selection.kind) {
      SelectionKind.automatic => false,
      SelectionKind.server => removed.contains(selection.id),
      SelectionKind.source =>
        selection.id == sourceId ||
            (all.any(
                  (row) =>
                      row.subId == selection.id &&
                      activeServerIds.contains(row.id) &&
                      removed.contains(row.id),
                ) &&
                !remaining.any(
                  (row) =>
                      row.subId == selection.id &&
                      activeServerIds.contains(row.id),
                )),
    };
    final next = ConnectionConfiguration(
      policy: current.policy,
      connection: ConnectionSettings.fromJson({
        ...current.connection.toJson(),
        if (invalidSelection)
          'selection': const ServerSelection.automatic().toJson(),
        'smart': {
          ...current.connection.smart.toJson(),
          if (removed.contains(current.connection.smart.finalExitId))
            'finalExitId': null,
        },
      }),
    );
    final active =
        coordinator.state.value.phase == ConnectionPhase.connected &&
        coordinator.state.value.runtime?.nodeIds.any(removed.contains) == true;
    return ServerRemoval(
      ids: Set.unmodifiable(removed),
      sourceId: sourceId,
      manualGroupId: manualGroupId,
      configuration: next,
      expectedConfiguration: current.encode(),
      affectsRuntime: active,
      disconnect:
          active &&
          !remaining.any(
            (row) =>
                activeServerIds.contains(row.id) &&
                selectable(row) &&
                row.id != next.connection.finalExitId,
          ),
    );
  }

  /// The UI confirms this preview before calling. A changed source aborts instead
  /// of removing servers not included in the confirmation.
  Future<void> remove(ServerRemoval preview) async {
    final refreshed = await previewRemoval(
      ids: preview.ids,
      sourceId: preview.sourceId,
      manualGroupId: preview.manualGroupId,
    );
    if (!const SetEquality<int>().equals(preview.ids, refreshed.ids) ||
        refreshed.configuration.encode() != preview.configuration.encode() ||
        refreshed.expectedConfiguration != preview.expectedConfiguration ||
        refreshed.affectsRuntime != preview.affectsRuntime ||
        refreshed.disconnect != preview.disconnect) {
      throw const FormatException('Deletion preview changed');
    }
    await coordinator.apply(
      preview.configuration,
      expectedConfiguration: preview.expectedConfiguration,
      disconnect: preview.disconnect,
      allowReconnect: preview.affectsRuntime,
      affectsRuntime: preview.affectsRuntime && !preview.disconnect,
      prepare: preview.affectsRuntime && !preview.disconnect
          ? (next, cancelled) =>
                _prepare(next, cancelled, const {}, preview.ids)
          : null,
      writeAssets: () async {
        if (!preview.affectsRuntime &&
            coordinator.state.value.runtime?.nodeIds.any(
                  preview.ids.contains,
                ) ==
                true) {
          throw const FormatException('Server became active before deletion');
        }
        if (preview.sourceId case final id?) {
          final currentIds = (await rows())
              .where((row) => row.subId == id)
              .map((row) => row.id)
              .toSet();
          if (!const SetEquality<int>().equals(currentIds, preview.ids)) {
            throw const FormatException('Subscription changed before deletion');
          }
          await _subscriptions.deleteSubscription(
            id,
            prepareDeletion: (_) async => true,
          );
        } else {
          if (preview.manualGroupId case final groupId?) {
            final group = await db.manualServerGroupDao.searchRow(groupId);
            final currentIds = (await rows())
                .where(
                  (row) =>
                      ManualServerGroupService.isManual(row) &&
                      row.manualGroupId == groupId,
                )
                .map((row) => row.id)
                .toSet();
            if (group == null ||
                !const SetEquality<int>().equals(currentIds, preview.ids)) {
              throw const FormatException(
                'Manual group changed before deletion',
              );
            }
            await db.manualServerGroupDao.deleteRow(groupId);
          }
          await (db.delete(db.coreConfig)..where(
                (row) =>
                    row.id.isIn(preview.ids) &
                    row.type.isIn([
                      CoreConfigType.outbound.name,
                      CoreConfigType.Remnawave.name,
                    ]),
              ))
              .go();
        }
      },
    );
  }

  Future<ConnectionRuntime> _prepare(
    ConnectionConfiguration next,
    Future<void> cancelled,
    Map<int, ResolvedServer> drafts,
    Set<int> removed,
  ) =>
      prepare?.call(next, cancelled, drafts, removed) ??
      ConnectionPreparation(
        db: db,
        resolver: ConnectionResolver(
          rows: () => watch().map(
            (rows) => rows.where((row) => !removed.contains(row.id)).toList(),
          ),
        ),
      ).prepare(
        next,
        cancelled: cancelled,
        serverDrafts: drafts,
        onResolved: coordinator.reportResolvedNodes,
      );
}
