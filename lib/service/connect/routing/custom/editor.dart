import 'package:collection/collection.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/asset_edit.dart';
import 'package:onexray/service/connect/preparation.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';

class CustomRoutingEditorDraft {
  final RoutingProfileData? original;
  final RoutingConfiguration state;
  const CustomRoutingEditorDraft({this.original, required this.state});
}

/// Draft editing never resolves servers. Only applying an active semantic change
/// asks the coordinator to prepare/start; its transaction owns the asset write.
class CustomRoutingEditorService {
  final AppDatabase db;
  final ConnectionCoordinator coordinator;
  final Future<String> Function(String)? testXray;
  final Future<ConnectionRuntime> Function(
    ConnectionConfiguration,
    Future<void>,
    RoutingConfiguration,
  )?
  prepare;

  CustomRoutingEditorService({
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
    this.testXray,
    this.prepare,
  }) : db = database ?? AppDatabase(),
       coordinator = coordinator ?? ConnectionCoordinator.instance;

  Future<CustomRoutingEditorDraft> load(int? id) async {
    if (id == null) {
      return CustomRoutingEditorDraft(state: RoutingProfileState(name: ''));
    }
    final row = await db.routingProfileDao.searchRow(id);
    if (row == null) throw const CustomRoutingEditorException('missing');
    return CustomRoutingEditorDraft(
      original: row,
      state: CustomRoutingService.readConfiguration(row),
    );
  }

  Future<List<RoutingProfileData>> get rows => db.routingProfileDao.allRows;

  Future<int?> save(
    CustomRoutingEditorDraft draft, {
    required Future<bool> Function() confirmReconnect,
    ConfigurationImportDraft? imported,
  }) async {
    final name = draft.state.name.trim();
    final original = draft.original;
    final state = draft.state.copyWith(
      id: original?.id,
      clearId: original == null,
      name: name,
    );
    final service = CustomRoutingService(db);
    await service.checkSave(state, original: original);
    final configuration = await coordinator.readForEditing();
    final connection = configuration.connection;
    final selected = original != null && _selects(connection, original.id);
    final running = coordinator.state.value.runtime?.configuration.connection;
    if (original != null &&
        running != null &&
        !running.expert &&
        _selects(running, original.id) &&
        (!selected || connection.expert)) {
      throw const CustomRoutingEditorException('changed');
    }
    final affectsRuntime =
        selected &&
        !connection.expert &&
        !sameRouting(CustomRoutingService.readConfiguration(original), state);
    int? savedId = original?.id;
    final saved = await coordinator.saveEditedAsset(
      configuration,
      confirmReconnect: confirmReconnect,
      imported: imported,
      validateAssets: () =>
          CustomRoutingService.validate(state, testXray: testXray),
      affectsRuntime: affectsRuntime,
      prepare: affectsRuntime
          ? (next, cancelled) =>
                prepare?.call(next, cancelled, state) ??
                ConnectionPreparation(db: db).prepare(
                  next,
                  cancelled: cancelled,
                  customDraft: state,
                  onResolved: coordinator.reportResolvedNodes,
                )
          : null,
      writeAssets: () async {
        savedId = await service.save(state, original: original);
      },
    );
    return saved ? savedId : null;
  }

  Future<bool> delete(
    RoutingProfileData original, {
    required Future<bool> Function(bool selected, bool reconnect) confirm,
  }) async {
    await _checkOriginal(original);
    final configuration = await coordinator.readForEditing();
    final connection = configuration.connection;
    final selected = _selects(connection, original.id);
    final running = coordinator.state.value.runtime?.configuration.connection;
    if (running != null &&
        !running.expert &&
        _selects(running, original.id) &&
        (!selected || connection.expert)) {
      throw const CustomRoutingEditorException('changed');
    }
    final affectsRuntime = selected && !connection.expert;
    final reconnect =
        affectsRuntime &&
        coordinator.state.value.phase == ConnectionPhase.connected;
    if (!await confirm(selected, reconnect)) return false;
    final next = selected
        ? ConnectionConfiguration(
            connection: ConnectionSettings.fromJson({
              ...connection.toJson(),
              'trafficMode': TrafficMode.smart.name,
              'customId': null,
            }),
            policy: configuration.policy,
          )
        : configuration;
    await coordinator.apply(
      next,
      affectsRuntime: affectsRuntime,
      allowReconnect: reconnect,
      expectedConfiguration: configuration.encode(),
      writeAssets: () async {
        await _checkOriginal(original);
        if (await db.routingProfileDao.deleteRow(original.id) != 1) {
          throw const CustomRoutingEditorException('missing');
        }
      },
    );
    return true;
  }

  Future<void> _checkOriginal(RoutingProfileData original) async {
    final current = await db.routingProfileDao.searchRow(original.id);
    if (current == null ||
        current.data != original.data ||
        current.name != original.name ||
        current.advanced != original.advanced) {
      throw const CustomRoutingEditorException('changed');
    }
  }

  static bool _selects(ConnectionSettings value, int id) =>
      value.trafficMode == TrafficMode.custom && value.customId == id;

  static bool sameRouting(
    RoutingConfiguration before,
    RoutingConfiguration after,
  ) {
    if (before.advanced || after.advanced) {
      return before.advanced == after.advanced &&
          const DeepCollectionEquality().equals(
            before.toJson(),
            after.toJson(),
          );
    }
    Object semantic(RoutingProfileState state) => {
      'entries': state.entryCount,
      'dns': state.dns.effectiveJson(),
      'sniffing': state.sniffing.effectiveJson(fakeDns: state.fakeDns),
      'selection': state.selection.effectiveJson(entryCount: state.entryCount),
      'fakeDns': state.fakeDns,
      'fragmentOutbound': state.fragmentOutbound,
      'rules': [
        for (final rule in state.rules) {...rule.toJson()}..remove('ruleTag'),
      ],
    };
    return const DeepCollectionEquality().equals(
      semantic(before as RoutingProfileState),
      semantic(after as RoutingProfileState),
    );
  }
}
