import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';

/// App routing and LAN sharing remain stored preferences while the selected or
/// already running session is a complete provider graph.
Future<bool> usesProviderConfiguration(
  AppDatabase db,
  ConnectionSettings settings, {
  ConnectionRuntime? runtime,
}) async {
  if (runtime?.profile != null) return true;
  if (settings.expert || settings.selection.kind != SelectionKind.server) {
    return false;
  }
  return (await db.coreConfigDao.searchActiveServerRow(settings.selection.id!))
          ?.type ==
      CoreConfigType.Remnawave.name;
}
