import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';

class OrdinaryPlanRestore {
  final ConnectionConfiguration configuration;
  final bool requiresSelection;

  const OrdinaryPlanRestore(
    this.configuration, {
    required this.requiresSelection,
  });
}

/// Device-local intent bookkeeping, committed by the connection coordinator.
/// Reading a return plan neither changes saved settings nor starts a connection.
class OrdinaryPlanService {
  final AppDatabase db;
  OrdinaryPlanService(this.db);

  Future<bool> _provider(ServerSelection selection) async =>
      selection.kind == SelectionKind.server &&
      (await db.coreConfigDao.searchRow(selection.id!))?.type ==
          CoreConfigType.Remnawave.name;

  Future<bool> _ordinary(ServerSelection selection) async {
    if (selection.kind == SelectionKind.automatic) return true;
    if (selection.kind == SelectionKind.source) {
      if (selection.id == 0) return true;
      final source = await db.subscriptionDao.searchRow(selection.id!);
      return source != null && source.mode == SubscriptionMode.appManaged.name;
    }
    final row = await db.coreConfigDao.searchActiveOutboundRow(selection.id!);
    if (row == null) return false;
    try {
      ResolvedServer.fromRow(row);
      return true;
    } on FormatException {
      return false;
    }
  }

  Future<ConnectionConfiguration> retain(
    ConnectionConfiguration stored,
    ConnectionConfiguration next,
  ) async {
    var remembered = stored.connection.rememberedOrdinarySelection;
    if (!next.connection.expert) {
      if (await _provider(next.connection.selection)) {
        if (!await _provider(stored.connection.selection) &&
            await _ordinary(stored.connection.selection)) {
          remembered = stored.connection.selection;
        }
      } else if (_different(
            stored.connection.selection,
            next.connection.selection,
          ) &&
          await _ordinary(next.connection.selection)) {
        remembered = next.connection.selection;
      }
    }
    return ConnectionConfiguration(
      connection: ConnectionSettings.fromJson({
        ...next.connection.toJson(),
        'rememberedOrdinarySelection': remembered?.toJson(),
      }),
      policy: next.policy,
    );
  }

  Future<OrdinaryPlanRestore> restore(ConnectionConfiguration current) async {
    final selection = current.connection.selection;
    final candidate = await _provider(selection)
        ? current.connection.rememberedOrdinarySelection
        : selection;
    final valid = candidate != null && await _ordinary(candidate);
    final restored = valid ? candidate! : const ServerSelection.automatic();
    return OrdinaryPlanRestore(
      ConnectionConfiguration(
        connection: ConnectionSettings.fromJson({
          ...current.connection.toJson(),
          'expert': false,
          'selection': restored.toJson(),
          'rememberedOrdinarySelection': valid ? restored.toJson() : null,
        }),
        policy: current.policy,
      ),
      requiresSelection: !valid,
    );
  }

  bool _different(ServerSelection first, ServerSelection second) =>
      first.kind != second.kind || first.id != second.id;
}
