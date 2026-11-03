import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
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
        color: active ? palette.selectedSurface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          side: active
              ? BorderSide(color: palette.primary.withValues(alpha: .2))
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          selected: active,
          button: true,
          child: ListTile(
            minTileHeight: 56,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            leading: Icon(
              icon,
              size: 20,
              color: active ? palette.primaryText : palette.mutedForeground,
            ),
            title: Text(
              title,
              style:
                  (active
                          ? AppTypography.control
                          : AppTypography.serverNodeTitle)
                      .copyWith(
                        color: active
                            ? palette.primaryText
                            : palette.foreground,
                      ),
            ),
            subtitle: Text(
              detail,
              style: AppTypography.supporting.copyWith(
                color: palette.mutedForeground,
              ),
            ),
            trailing: active
                ? Icon(
                    LucideIcons.circleCheck,
                    color: palette.foreground,
                    size: 18,
                  )
                : const SizedBox(width: 18),
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
    final footer = Padding(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final theme = Theme.of(context);
          final cancelStyle =
              ShadTheme.of(context).outlineButtonTheme.textStyle ??
              theme.textTheme.labelLarge!;
          final manageStyle =
              theme.outlinedButtonTheme.style?.textStyle?.resolve({}) ??
              theme.textTheme.labelLarge!;
          double labelWidth(String label, TextStyle style) {
            final painter = TextPainter(
              text: TextSpan(text: label, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          }

          final halfWidth = (constraints.maxWidth - 12) / 2;
          final stacked =
              labelWidth(l.prototypeServers, manageStyle) + 48 > halfWidth ||
              labelWidth(l.prototypeCancel, cancelStyle) + 48 > halfWidth;
          final minimumHeight = AppLayout.touchExtent(
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint
                ? 48
                : 42,
            platform: theme.platform,
          );
          final manage = OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, minimumHeight),
              textStyle: AppTypography.control,
            ),
            onPressed: () => choose(const ConnectionTargetChoice(manage: true)),
            child: Text(l.prototypeServers),
          );
          final cancel = ConstrainedBox(
            constraints: BoxConstraints(minHeight: minimumHeight),
            child: ShadButton.outline(
              expands: true,
              height: 0,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.prototypeCancel),
            ),
          );
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [manage, const SizedBox(height: 8), cancel],
                )
              : Row(
                  children: [
                    Expanded(child: manage),
                    const SizedBox(width: 12),
                    Expanded(child: cancel),
                  ],
                );
        },
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < 380;
        return Material(
          color: palette.background,
          borderRadius: BorderRadius.circular(
            MediaQuery.sizeOf(context).width < 640 ? 0 : 8,
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.prototypeServers,
                          style: AppTypography.dialogTitle,
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
                Expanded(
                  child: CustomScrollView(
                    key: const ValueKey('connection-target-options'),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: LayoutBuilder(
                            builder: (context, tabConstraints) => Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final entry in [
                                  l.serverSelectionAutomaticScope,
                                  l.serverSelectionFixedNode,
                                  l.serverCompleteConfigurationsTab,
                                ].indexed)
                                  ChoiceChip(
                                    label: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: 36,
                                        maxWidth: math.max(
                                          1.0,
                                          tabConstraints.maxWidth - 24,
                                        ),
                                      ),
                                      child: Align(
                                        widthFactor: 1,
                                        heightFactor: 1,
                                        child: Text(
                                          entry.$2,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                    labelStyle: AppTypography.control.copyWith(
                                      color: palette.foreground,
                                    ),
                                    labelPadding: EdgeInsets.zero,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    showCheckmark: false,
                                    side: BorderSide.none,
                                    backgroundColor: palette.muted,
                                    selectedColor: palette.background,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(4),
                                      ),
                                    ),
                                    selected: tab == entry.$1,
                                    onSelected: (_) =>
                                        setState(() => tab = entry.$1),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: TextField(
                            key: const ValueKey('connection-target-search'),
                            style: AppTypography.rowValue,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(
                                LucideIcons.search,
                                size: 18,
                              ),
                              hintText: l.prototypeSearchSubscriptionsServers,
                            ),
                            onChanged: (value) => setState(() => query = value),
                          ),
                        ),
                      ),
                      if (tab == 0 &&
                          (settings.expert ||
                              widget.catalog.servers.any(
                                (r) =>
                                    r.type == CoreConfigType.Remnawave.name &&
                                    selected(ServerSelection.server(r.id)),
                              )))
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: TextButton(
                              onPressed: () => choose(
                                const ConnectionTargetChoice(restore: true),
                              ),
                              child: Text(l.connectionRestoreOrdinary),
                            ),
                          ),
                        ),
                      if (entries.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              query.trim().isEmpty
                                  ? l.prototypeNoServersYet
                                  : l.serverNoMatchingResources,
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverList.builder(
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
                      if (short) SliverToBoxAdapter(child: footer),
                    ],
                  ),
                ),
                if (!short) footer,
              ],
            ),
          ),
        );
      },
    );
  }
}
