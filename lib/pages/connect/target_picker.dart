import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ConnectionTargetChoice {
  const ConnectionTargetChoice({
    this.selection,
    this.rawId,
    this.restore = false,
    this.manage = false,
  });
  final ServerSelection? selection;
  final int? rawId;
  final bool restore, manage;
}

/// Tabs only browse. A resource click returns an intent for the coordinator.
class ConnectionTargetPicker extends StatefulWidget {
  const ConnectionTargetPicker({
    super.key,
    required this.settings,
    required this.catalog,
    required this.raws,
    required this.candidateCount,
    required this.selectionName,
  });
  final ConnectionSettings settings;
  final ServerCatalog catalog;
  final List<CoreConfigData> raws;
  final int Function(ServerSelection) candidateCount;
  final String Function(ServerSelection) selectionName;
  @override
  State<ConnectionTargetPicker> createState() => _ConnectionTargetPickerState();
}

class _ConnectionTargetPickerState extends State<ConnectionTargetPicker> {
  late int tab =
      widget.settings.expert ||
          (widget.settings.selection.kind == SelectionKind.server &&
              widget.catalog.servers.any(
                (r) =>
                    r.id == widget.settings.selection.id &&
                    r.type == CoreConfigType.Remnawave.name,
              ))
      ? 2
      : widget.settings.selection.kind == SelectionKind.server
      ? 1
      : 0;
  String query = '';
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final settings = widget.settings;
    bool selected(ServerSelection s) =>
        !settings.expert &&
        s.kind == settings.selection.kind &&
        s.id == settings.selection.id;
    void choose(ConnectionTargetChoice choice) =>
        Navigator.of(context).pop(choice);
    bool matches(String name) =>
        name.toLowerCase().contains(query.trim().toLowerCase());
    Widget option(
      String title,
      String detail,
      bool active,
      VoidCallback onTap,
      IconData icon,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active ? palette.selectedSurface : palette.muted,
        borderRadius: BorderRadius.circular(12),
        child: Semantics(
          selected: active,
          button: true,
          child: ListTile(
            minTileHeight: 64,
            leading: Icon(icon, size: 19),
            title: Text(title),
            subtitle: Text(detail),
            trailing: active
                ? Icon(LucideIcons.check, color: palette.primary, size: 20)
                : null,
            onTap: onTap,
          ),
        ),
      ),
    );
    final rows = widget.catalog.servers
        .where(
          (r) =>
              r.id > 0 &&
              widget.catalog.selectable(r) &&
              matches(widget.catalog.display(r).name),
        )
        .toList();
    final ordinarySettings = ConnectionSettings.fromJson({
      ...settings.toJson(),
      'expert': false,
    });
    final ordinary = rows
        .where(
          (r) =>
              r.type == CoreConfigType.outbound.name &&
              r.id != ordinarySettings.finalExitId,
        )
        .toList();
    final profiles = rows
        .where((r) => r.type == CoreConfigType.Remnawave.name)
        .toList();
    final rawRows = widget.raws.where((r) => matches(r.name)).toList();
    final scopeSelections = <ServerSelection>[
      const ServerSelection.automatic(),
      const ServerSelection.source(0),
      for (final source in widget.catalog.sources.where(
        (s) => s.mode == SubscriptionMode.appManaged.name,
      ))
        ServerSelection.source(source.id),
    ];
    final entries =
        <
          ({
            String title,
            String detail,
            bool active,
            ConnectionTargetChoice choice,
            IconData icon,
          })
        >[
          if (tab == 0)
            for (final scope in scopeSelections.where(
              (s) => matches(widget.selectionName(s)),
            ))
              (
                title: widget.selectionName(scope),
                detail: l.connectionCandidates(widget.candidateCount(scope)),
                active: selected(scope),
                choice: ConnectionTargetChoice(selection: scope),
                icon: LucideIcons.layers3,
              ),
          if (tab == 1)
            for (final row in ordinary)
              (
                title: widget.catalog.display(row).name,
                detail: widget.catalog.display(row).protocol,
                active: selected(ServerSelection.server(row.id)),
                choice: ConnectionTargetChoice(
                  selection: ServerSelection.server(row.id),
                ),
                icon: LucideIcons.server,
              ),
          if (tab == 2) ...[
            for (final row in rawRows)
              (
                title: row.name,
                detail: l.xrayRawPageTitle,
                active: settings.expert && settings.rawId == row.id,
                choice: ConnectionTargetChoice(rawId: row.id),
                icon: LucideIcons.fileJson,
              ),
            for (final row in profiles)
              (
                title: row.name,
                detail: l.providerConfigurationTitle,
                active: selected(ServerSelection.server(row.id)),
                choice: ConnectionTargetChoice(
                  selection: ServerSelection.server(row.id),
                ),
                icon: LucideIcons.fileJson,
              ),
          ],
        ];
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.prototypeServers,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l.prototypeClose,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in [
                    l.serverSelectionAutomaticScope,
                    l.serverSelectionFixedNode,
                    l.serverCompleteConfigurationsTab,
                  ].indexed)
                    ChoiceChip(
                      label: Text(entry.$2),
                      selected: tab == entry.$1,
                      onSelected: (_) => setState(() => tab = entry.$1),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const ValueKey('connection-target-search'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  hintText: l.prototypeSearchSubscriptionsServers,
                ),
                onChanged: (value) => setState(() => query = value),
              ),
            ),
            if (tab == 0 &&
                (settings.expert ||
                    widget.catalog.servers.any(
                      (r) =>
                          r.type == CoreConfigType.Remnawave.name &&
                          selected(ServerSelection.server(r.id)),
                    )))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextButton(
                  onPressed: () =>
                      choose(const ConnectionTargetChoice(restore: true)),
                  child: Text(l.connectionRestoreOrdinary),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          query.trim().isEmpty
                              ? l.prototypeNoServersYet
                              : l.serverNoMatchingResources,
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: const ValueKey('connection-target-options'),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        return option(
                          e.title,
                          e.detail,
                          e.active,
                          () => choose(e.choice),
                          e.icon,
                        );
                      },
                    ),
            ),
            PageActionBar(
              children: [
                OutlinedButton(
                  onPressed: () =>
                      choose(const ConnectionTargetChoice(manage: true)),
                  child: Text(l.prototypeServers),
                ),
                ShadButton.outline(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.prototypeCancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
