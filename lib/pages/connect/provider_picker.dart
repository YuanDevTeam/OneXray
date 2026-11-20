import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/connect/target_picker.dart';
import 'package:onexray/pages/shared/connection_action.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/server.dart';

/// Shared by the Connect page and successful subscription imports.
Future<void> chooseProviderConfiguration(
  BuildContext context, {
  int? sourceId,
  ServerCatalog? catalog,
  AppDatabase? database,
  ConnectionCoordinator? coordinator,
}) async {
  final connection = coordinator ?? ConnectionCoordinator.instance;
  if (connection.state.value.busy) return;
  final db = database ?? AppDatabase();
  await runConnectionAction(context, connection, () async {
    final choices =
        catalog ??
        await db.transaction<ServerCatalog>(
          () async => ServerCatalog(
            servers: [
              for (final row in await db.coreConfigDao.allActiveServerRows())
                if (row.type == CoreConfigType.Remnawave.name &&
                    (sourceId == null || row.subId == sourceId))
                  row,
            ],
            sources: await db.subscriptionDao.allRows,
          ),
        );
    final settings = (await connection.configuration).connection;
    if (!context.mounted || connection.state.value.busy) return;
    final choice = await showConnectDialog<ConnectionTargetChoice>(
      context,
      (_) => ConnectionTargetPicker.providers(
        settings: settings,
        catalog: choices,
        sourceId: sourceId,
      ),
    );
    final selection = choice?.selection;
    if (selection == null || !context.mounted || connection.state.value.busy) {
      return;
    }
    final profile = choices.providerConfigurations
        .where((row) => row.id == selection.id)
        .firstOrNull;
    if (profile == null || (sourceId != null && profile.subId != sourceId)) {
      return;
    }
    final assets = ServerAssetService(database: db, coordinator: connection);
    Future<void> validate() => assets.validateSelection(selection);
    await validate();
    final current = (await connection.configuration).connection;
    if (!context.mounted || connection.state.value.busy) return;
    if (!current.expert &&
        current.selection.kind == selection.kind &&
        current.selection.id == selection.id) {
      return;
    }
    await applyConnectionChange(
      context,
      connection,
      {'expert': false, 'selection': selection.toJson()},
      label: (_) => profile.name,
      validateAssets: validate,
      writeAssets: validate,
    );
  });
}
