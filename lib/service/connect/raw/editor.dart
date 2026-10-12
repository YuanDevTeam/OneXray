import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Value;
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/asset_edit.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/preparation.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/connect/raw/db.dart';
import 'package:onexray/service/connect/raw/validator.dart';

class RawEditorException extends AppFailure {
  final String reason;
  const RawEditorException(this.reason, {super.cause})
    : super(
        reason == 'changed' || reason == 'missing'
            ? FailureCategory.conflict
            : FailureCategory.input,
        reason,
      );
}

class RawEditorDraft {
  final CoreConfigData? original;
  final String name;
  final String text;
  const RawEditorDraft({this.original, required this.name, required this.text});
}

class RawEditorService {
  final AppDatabase db;
  final ConnectionCoordinator coordinator;
  final Future<void> Function(String)? validate;
  final Future<ConnectionRuntime> Function(
    ConnectionConfiguration,
    Future<void>,
    String,
  )?
  prepare;

  RawEditorService({
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
    this.validate,
    this.prepare,
  }) : db = database ?? AppDatabase(),
       coordinator = coordinator ?? ConnectionCoordinator.instance;

  Future<RawEditorDraft> load(int? id) async {
    if (id == null) {
      return const RawEditorDraft(name: '', text: '{\n  "outbounds": []\n}');
    }
    final row = await db.coreConfigDao.searchRow(id);
    if (row == null || row.type != 'raw') {
      throw const RawEditorException('missing');
    }
    return RawEditorDraft(
      original: row,
      name: row.name,
      text: XrayRawDb.readFromDbData(row),
    );
  }

  /// Null means the user declined reconnection. No asset is written before it.
  Future<int?> save(
    RawEditorDraft draft, {
    required Future<bool> Function() confirmReconnect,
    ConfigurationImportDraft? imported,
  }) async {
    final parsed = namedConfiguration(draft.name, draft.text);
    final text = parsed.text;
    final original = draft.original;
    if (original == null &&
        (await db.coreConfigDao.allRawRowsWithData).length >= 3) {
      throw const RawEditorException('limit');
    }
    final configuration = await coordinator.readForEditing();
    final runtime = coordinator.state.value.runtime;
    if (original != null) _checkRunningRaw(original, configuration);
    final selected =
        original != null &&
        configuration.connection.expert &&
        configuration.connection.rawId == original.id;
    // Offline saves need no runtime options. Keep the queued reconnect guard
    // for a selected asset if the VPN connects before the save is executed.
    var affectsRuntime = selected;
    if (selected &&
        coordinator.state.value.phase == ConnectionPhase.connected) {
      final options = _comparisonOptions(configuration, runtime);
      try {
        affectsRuntime = !const DeepCollectionEquality().equals(
          ConnectionCompiler.rawSemanticJson(
            ConnectionCompiler.parseRawJson(XrayRawDb.readFromDbData(original)),
            options,
          ),
          ConnectionCompiler.rawSemanticJson(parsed.json, options),
        );
      } on FormatException {
        // A repaired old configuration cannot be classified as metadata-only.
        affectsRuntime = true;
      }
    }
    var savedId = original?.id;
    final saved = await coordinator.saveEditedAsset(
      configuration,
      confirmReconnect: confirmReconnect,
      imported: imported,
      validateAssets: () => _validateParsed(parsed),
      affectsRuntime: affectsRuntime,
      prepare: affectsRuntime
          ? (next, cancelled) =>
                prepare?.call(next, cancelled, text) ??
                ConnectionPreparation(db: db).prepare(
                  next,
                  cancelled: cancelled,
                  rawDraft: text,
                  onResolved: coordinator.reportResolvedNodes,
                )
          : null,
      writeAssets: () async {
        if (original == null) {
          savedId = await db.coreConfigDao.insertAssetRow(
            XrayRawDb.configCompanion(draft.name.trim(), text),
          );
        } else {
          final current = await _checkOriginal(original);
          final saved = current.copyWith(
            name: draft.name.trim(),
            data: Value(base64Encode(utf8.encode(text))),
          );
          if (!await db.coreConfigDao.updateRow(saved)) {
            throw const RawEditorException('missing');
          }
        }
      },
    );
    return saved ? savedId : null;
  }

  Future<bool> delete(
    CoreConfigData original, {
    required Future<bool> Function(
      bool selected,
      bool reconnect,
      bool disconnect,
    )
    confirm,
  }) async {
    await _checkOriginal(original);
    final configuration = await coordinator.readForEditing();
    _checkRunningRaw(original, configuration);
    final connection = configuration.connection;
    final selected = connection.expert && connection.rawId == original.id;
    final connected =
        coordinator.state.value.phase == ConnectionPhase.connected;
    final servers =
        await (db.select(db.coreConfig)
              ..where((row) => row.type.equals('outbound'))
              ..limit(1))
            .get();
    final disconnect = selected && connected && servers.isEmpty;
    final reconnect = selected && connected && !disconnect;
    if (!await confirm(selected, reconnect, disconnect)) return false;
    await coordinator.apply(
      ConnectionConfiguration(
        connection: ConnectionSettings.fromJson({
          ...connection.toJson(),
          if (connection.rawId == original.id) ...{
            'expert': false,
            'rawId': null,
          },
        }),
        policy: configuration.policy,
      ),
      affectsRuntime: selected && !disconnect,
      disconnect: disconnect,
      allowReconnect: connected,
      expectedConfiguration: configuration.encode(),
      writeAssets: () async {
        _checkRunningRaw(original, configuration);
        await _checkOriginal(original);
        if (await db.coreConfigDao.deleteRow(original) != 1) {
          throw const RawEditorException('missing');
        }
      },
    );
    return true;
  }

  void _checkRunningRaw(
    CoreConfigData original,
    ConnectionConfiguration configuration,
  ) {
    final running = coordinator.state.value.runtime?.configuration.connection;
    if (running?.expert == true &&
        running?.rawId == original.id &&
        (!configuration.connection.expert ||
            configuration.connection.rawId != original.id)) {
      throw const RawEditorException('changed');
    }
  }

  Future<CoreConfigData> _checkOriginal(CoreConfigData original) async {
    final current = await db.coreConfigDao.searchRow(original.id);
    if (current == null ||
        current.type != 'raw' ||
        current.data != original.data ||
        current.name != original.name) {
      throw const RawEditorException('changed');
    }
    return current;
  }

  static String namedText(String name, String text) =>
      namedConfiguration(name, text).text;

  static ParsedRawConfiguration namedConfiguration(String name, String text) {
    name = name.trim();
    if (name.isEmpty || name.runes.length > 32) {
      throw const RawEditorException('name');
    }
    return XrayRawValidator.normalize(text, nameOverride: name);
  }

  Future<void> _validateParsed(ParsedRawConfiguration parsed) async {
    if (validate != null) return validate!(parsed.text);
    await XrayRawValidator.validateParsed(parsed);
  }

  RuntimeOptions _comparisonOptions(
    ConnectionConfiguration configuration,
    ConnectionRuntime? runtime,
  ) {
    final policy = configuration.policy;
    final request = runtime?.request;
    final metricsPort = int.tryParse(request?.metricsPort ?? '');
    final socksPort = int.tryParse(request?.socksPort ?? '');
    final occupied = {?metricsPort, ?socksPort};
    // Disconnected semantic comparisons need stable placeholders, not sockets.
    final comparisonPorts = [
      for (final port in [65534, 65535, 65533])
        if (!occupied.contains(port)) port,
    ];
    return RuntimeOptions(
      platform: runtime?.platform ?? connectionPlatform,
      sessionDirectory: VpnConstants.runDir,
      metricsPort: metricsPort ?? comparisonPorts.removeAt(0),
      socksPort: socksPort ?? comparisonPorts.removeAt(0),
      ipv6: policy.ipv6Enabled,
      interfaceName: policy.xrayOutboundInterfaceName,
      logEnabled: policy.logEnabled,
      logLevel: policy.logLevel,
      dnsLog: policy.recordDns,
      maskAddress: policy.maskAddress,
    );
  }
}
