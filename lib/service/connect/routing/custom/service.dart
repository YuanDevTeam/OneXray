import 'package:onexray/core/db/database/database.dart';
import 'package:collection/collection.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/state_db.dart';
import 'package:onexray/service/connect/routing/dns.dart';
import 'package:onexray/service/shared/xray/runtime_outbounds.dart';
import 'package:onexray/service/shared/xray/runtime_inbounds.dart';
import 'package:onexray/service/shared/xray/validation.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';
import 'package:onexray/service/shared/xray/fragment.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';

/// Persists validated Custom-routing state. Applying a currently used profile
/// remains the connection coordinator's responsibility.
class CustomRoutingService {
  final AppDatabase database;

  CustomRoutingService(this.database);

  static RoutingProfileState read(RoutingProfileData row) =>
      RoutingProfileStateDb.read(row);

  static RoutingConfiguration readConfiguration(RoutingProfileData row) =>
      RoutingProfileStateDb.readConfiguration(row);

  /// Empty entry slots are editor metadata, not runnable Xray outbounds.
  /// Use local placeholders for validation; never resolve or connect a server.
  static Future<void> validate(
    RoutingConfiguration state, {
    Future<String> Function(String)? testXray,
  }) => GeoDataService().withFiles(() async {
    final error = await (testXray ?? AppHostApi().testXray)(
      validationJson(state),
    );
    if (error.isNotEmpty) {
      throw AppFailure(
        FailureCategory.configuration,
        'xrayValidation',
        cause: error,
      );
    }
  });

  /// Shared by the editor and local API; this does not select stored nodes.
  static String validationJson(RoutingConfiguration state) {
    if (state is AdvancedRoutingProfile) {
      final config = state.fillSlots([
        for (var i = 0; i < state.entryCount; i++)
          createFreedomOutbound(tag: 'app-entry-$i').toJson(),
      ]);
      return XrayValidation.raw(config);
    }
    state as RoutingProfileState;
    final config = state.xrayJson;
    config.dns = RoutingDns.compile(
      settings: state.dns,
      fakeDns: state.fakeDns,
      rules: config.routing?.rules ?? const [],
    );
    config.fakedns = FakeDns.poolsFor(config.dns);
    final tags = [for (var i = 0; i < state.entryCount; i++) 'app-entry-$i'];
    final fragment = state.fragmentOutbound;
    final helpers = <Map<String, dynamic>>[?fragment];
    config.outbounds = [
      ...XrayFragment.connectEntries([
        for (final tag in tags) createFreedomOutbound(tag: tag).toJson(),
      ], helpers),
      ...helpers,
      createFreedomOutbound(tag: 'direct').toJson(),
      createBlackholeOutbound(tag: 'block').toJson(),
    ];
    config.inbounds = [
      createSocksInbound(
        '1080',
        fakeDns: state.fakeDns,
        sniffing: state.sniffing,
      ),
    ];
    final selection = state.selection.compile(selector: tags);
    (config.routing ??= XrayRouting()).balancers = [selection.balancer];
    config.observatory = selection.observatory;
    return XrayValidation.normal(config);
  }

  /// A preflight before confirmation; the write repeats this inside its transaction.
  Future<RoutingProfileData?> checkSave(
    RoutingConfiguration state, {
    RoutingProfileData? original,
  }) async {
    final name = state.name.trim();
    if (name.isEmpty || name.runes.length > 32) {
      throw const CustomRoutingEditorException('name');
    }
    final rows = await database.routingProfileDao.allRows;
    if (rows.any(
      (row) =>
          row.id != state.id &&
          row.name.trim().toLowerCase() == name.toLowerCase(),
    )) {
      throw const CustomRoutingEditorException('duplicate');
    }
    final previous = rows.firstWhereOrNull((row) => row.id == state.id);
    if (original != null && previous != original) {
      throw const CustomRoutingEditorException('changed');
    }
    if (state.id == null && rows.length >= 3) {
      throw const CustomRoutingEditorException('limit');
    }
    if (state.id != null) {
      if (previous == null) throw const CustomRoutingEditorException('missing');
      if (previous.advanced != state.advanced) {
        throw const FormatException('Custom routing mode cannot be changed');
      }
    }
    return previous;
  }

  Future<int> save(
    RoutingConfiguration state, {
    RoutingProfileData? original,
  }) async {
    final value = state.copyWith(name: state.name.trim());
    return database.transaction(() async {
      final previous = await checkSave(value, original: original);
      if (value.id == null) {
        return database.routingProfileDao.insertRow(value.insertCompanion);
      }
      await database.routingProfileDao.updateRow(value.updateData(previous!));
      return value.id!;
    });
  }
}
