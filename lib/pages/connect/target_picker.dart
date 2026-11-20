import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
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

typedef _TargetOption = ({
  String title,
  String? detail,
  String? heading,
  bool active,
  ConnectionTargetChoice choice,
  IconData icon,
});

/// Tabs only browse. A resource click returns an intent for the coordinator.
class ConnectionTargetPicker extends StatefulWidget {
  const ConnectionTargetPicker({
    super.key,
    required this.settings,
    required this.catalog,
    required this.raws,
    required this.candidateCount,
    required this.selectionName,
  }) : _providerOnly = false,
       _providerSourceId = null;

  const ConnectionTargetPicker.providers({
    super.key,
    required this.settings,
    required this.catalog,
    int? sourceId,
  }) : raws = const [],
       candidateCount = null,
       selectionName = null,
       _providerOnly = true,
       _providerSourceId = sourceId;

  final ConnectionSettings settings;
  final ServerCatalog catalog;
  final List<CoreConfigData> raws;
  final int Function(ServerSelection)? candidateCount;
  final String Function(ServerSelection)? selectionName;
  final bool _providerOnly;
  final int? _providerSourceId;
  @override
  State<ConnectionTargetPicker> createState() => _ConnectionTargetPickerState();
}

enum _TargetTab { automatic, fixed, configurations }

class _ConnectionTargetPickerState extends State<ConnectionTargetPicker> {
  Iterable<CoreConfigData> get _providers =>
      widget.catalog.providerConfigurations.where(
        (row) =>
            widget._providerSourceId == null ||
            row.subId == widget._providerSourceId,
      );

  late _TargetTab tab = _initialTab();
  String query = '';

  _TargetTab _initialTab() {
    if (widget._providerOnly || widget.settings.expert) {
      return _TargetTab.configurations;
    }
    final selection = widget.settings.selection;
    if (selection.kind == SelectionKind.server) {
      return widget.catalog.servers.any(
            (row) =>
                row.id == selection.id &&
                row.type == CoreConfigType.Remnawave.name,
          )
          ? _TargetTab.configurations
          : _TargetTab.fixed;
    }
    if (selection.kind == SelectionKind.automatic &&
        widget.candidateCount!(selection) == 0 &&
        _providers.isNotEmpty) {
      return _TargetTab.configurations;
    }
    return _TargetTab.automatic;
  }

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
    Widget groupHeading(String title) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 6),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: AppTypography.control.copyWith(color: palette.foreground),
        ),
      ),
    );
    Widget option(
      String title,
      String? detail,
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
            subtitle: detail == null
                ? null
                : Text(
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
    final ordinarySettings = ConnectionSettings.fromJson({
      ...settings.toJson(),
      'expert': false,
    });
    final ordinary = widget.catalog.servers.where(
      (row) =>
          row.id > 0 &&
          row.id != ordinarySettings.finalExitId &&
          widget.catalog.outboundEligible(row) &&
          matches(widget.catalog.display(row).name),
    );
    final profiles = <SubscriptionData, List<CoreConfigData>>{};
    if (tab == _TargetTab.configurations) {
      for (final row in _providers) {
        final source = widget.catalog.sourcesById[row.subId];
        if (source != null && (matches(row.name) || matches(source.name))) {
          (profiles[source] ??= []).add(row);
        }
      }
    }
    final rawRows = widget.raws.where((r) => matches(r.name)).toList();
    final scopeSelections = <ServerSelection>[
      const ServerSelection.automatic(),
      const ServerSelection.source(0),
      for (final source in widget.catalog.sources.where(
        (s) => s.mode == SubscriptionMode.appManaged.name,
      ))
        ServerSelection.source(source.id),
    ];
    final rawEntries = <_TargetOption>[
      if (tab == _TargetTab.configurations)
        for (final (index, row) in rawRows.indexed)
          (
            title: row.name,
            detail: l.xrayRawPageTitle,
            heading: index == 0 ? l.xrayRawPageTitle : null,
            active: settings.expert && settings.rawId == row.id,
            choice: ConnectionTargetChoice(rawId: row.id),
            icon: LucideIcons.fileJson,
          ),
    ];
    final entries = <_TargetOption>[
      if (tab == _TargetTab.automatic)
        for (final scope in scopeSelections.where(
          (s) => matches(widget.selectionName!(s)),
        ))
          (
            title: widget.selectionName!(scope),
            detail: l.connectionCandidates(widget.candidateCount!(scope)),
            heading: null,
            active: selected(scope),
            choice: ConnectionTargetChoice(selection: scope),
            icon: LucideIcons.layers3,
          ),
      if (tab == _TargetTab.fixed)
        for (final row in ordinary)
          (
            title: widget.catalog.display(row).name,
            detail: widget.catalog.display(row).protocol,
            heading: null,
            active: selected(ServerSelection.server(row.id)),
            choice: ConnectionTargetChoice(
              selection: ServerSelection.server(row.id),
            ),
            icon: LucideIcons.server,
          ),
      if (tab == _TargetTab.configurations) ...[
        ...rawEntries,
        for (final group in profiles.entries)
          for (final (index, row) in group.value.indexed)
            (
              title: row.name,
              detail: widget._providerOnly
                  ? null
                  : l.providerConfigurationTitle,
              heading: index == 0 ? group.key.name : null,
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
          final minimumHeight = AppLayout.touchExtent(
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint
                ? 48
                : 42,
            platform: theme.platform,
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
          if (widget._providerOnly) return cancel;
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
          final manage = OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, minimumHeight),
              textStyle: AppTypography.control,
            ),
            onPressed: () => choose(const ConnectionTargetChoice(manage: true)),
            child: Text(l.prototypeServers),
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
                          widget._providerOnly
                              ? l.providerConfigurationsTitle
                              : l.prototypeServers,
                          style: AppTypography.dialogTitle,
                        ),
                      ),
                      if (!widget._providerOnly &&
                          tab == _TargetTab.configurations)
                        PageHelpButton(
                          title: l.serverCompleteConfigurationsTab,
                          messages: [l.completeConfigurationDefinition],
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
                      if (!widget._providerOnly)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: LayoutBuilder(
                              builder: (context, tabConstraints) => ChipTheme(
                                data: AppTheme.choiceChips(context),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final (kind, label) in [
                                      (
                                        _TargetTab.automatic,
                                        l.serverSelectionAutomaticScope,
                                      ),
                                      (
                                        _TargetTab.fixed,
                                        l.serverSelectionFixedNode,
                                      ),
                                      (
                                        _TargetTab.configurations,
                                        l.serverCompleteConfigurationsTab,
                                      ),
                                    ])
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
                                              label,
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                        labelPadding: EdgeInsets.zero,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        showCheckmark: false,
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(4),
                                          ),
                                        ),
                                        selected: tab == kind,
                                        onSelected: (_) =>
                                            setState(() => tab = kind),
                                      ),
                                  ],
                                ),
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
                      if (tab == _TargetTab.automatic &&
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
                              query.trim().isNotEmpty
                                  ? l.serverNoMatchingResources
                                  : widget._providerOnly
                                  ? l.prototypeTemporarilyUnavailable
                                  : l.prototypeNoServersYet,
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverList.builder(
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final e = entries[index];
                            final tile = option(
                              e.title,
                              e.detail,
                              e.active,
                              () => choose(e.choice),
                              e.icon,
                            );
                            final heading = e.heading;
                            if (heading == null) return tile;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [groupHeading(heading), tile],
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
