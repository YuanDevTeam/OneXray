import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/servers/sort.dart';

class ServerSortButton extends StatelessWidget {
  const ServerSortButton({super.key, required this.controller});

  final ServersController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final labels = {
      ServerSortOrder.defaultOrder: l.serverSortDefault,
      ServerSortOrder.name: l.serverSortName,
      ServerSortOrder.delay: l.serverSortLatency,
    };
    return PopupMenuButton<ServerSortOrder>(
      key: const ValueKey('server-sort-menu'),
      tooltip: l.serverSortTitle,
      enabled: !controller.state.sortSaving,
      initialValue: controller.catalog.sortOrder,
      icon: controller.state.sortSaving
          ? const ButtonProgressIndicator()
          : const Icon(LucideIcons.arrowDownWideNarrow, size: 20),
      onSelected: (order) => controller.setSortOrder(context, order),
      itemBuilder: (_) => [
        for (final order in ServerSortOrder.values)
          PopupMenuItem(
            value: order,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: controller.catalog.sortOrder == order
                      ? const Icon(LucideIcons.check, size: 17)
                      : null,
                ),
                Text(labels[order]!),
              ],
            ),
          ),
      ],
    );
  }
}
