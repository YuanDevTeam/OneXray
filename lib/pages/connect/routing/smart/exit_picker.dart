import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/connect/routing/smart/exit_picker_controller.dart';
import 'package:onexray/pages/servers/page.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';

class ServerExitPickerPage extends StatefulWidget {
  const ServerExitPickerPage({super.key, required this.params});

  final ServerExitPickerParams params;

  @override
  State<ServerExitPickerPage> createState() => _ServerExitPickerPageState();
}

class _ServerExitPickerPageState extends State<ServerExitPickerPage> {
  late final controller = ServerExitPickerController(widget.params);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.initialize();
    });
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ServerExitPickerView(controller: controller);
}

class ServerExitPickerView extends StatelessWidget {
  const ServerExitPickerView({super.key, required this.controller});

  final ServerExitPickerController controller;

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<ServerExitPickerController, ServerExitPickerState>(
      builder: (context, _) {
        final l = AppLocalizations.of(context)!;
        final palette = ColorManager.palette(context);
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        final groups = controller.selectionGroups(l);
        return Scaffold(
          appBar: PageAppBar(
            title: Text(l.prototypeVpnFinalExit),
            actions: const [AppActivityIndicator()],
          ),
          body: SafeArea(
            child: ServerLoadState(
              ready: controller.ready,
              failed: controller.failed,
              onRetry: controller.initialize,
              child: ResponsiveContent(
                desktopMaxWidth:
                    AppLayout.routingEditorMaxWidth + AppSpacing.page * 2,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    mobile ? AppSpacing.mobilePage : AppSpacing.page,
                    mobile ? 12 : AppSpacing.desktopPageTop,
                    mobile ? AppSpacing.mobilePage : AppSpacing.page,
                    mobile ? 18 : AppSpacing.desktopPageBottom,
                  ),
                  children: [
                    RoutingCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SelectionRow(
                            icon: LucideIcons.shield,
                            title: l.prototypeNoAdditionalExit,
                            detail: l.prototypeEntryConnectsDirectly,
                            selected: controller.selectedId == null,
                            onTap: controller.busy
                                ? null
                                : () => controller.selectDraft(null),
                          ),
                          _search(context, mobile),
                          for (final group in groups) ...[
                            Container(
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 7),
                              color: palette.muted,
                              child: Text(
                                group.name.toUpperCase(),
                                style: AppTypography.routingSelectionGroup
                                    .copyWith(color: palette.mutedForeground),
                              ),
                            ),
                            for (final row in group.visibleRows)
                              _SelectionRow(
                                key: ValueKey('final-exit:${row.id}'),
                                icon: LucideIcons.server,
                                title: controller.serverName(row),
                                detail: controller.exitRowDetail(l, row),
                                type: row.type,
                                protocol: controller.protocol(row),
                                selected: controller.selectedId == row.id,
                                onTap:
                                    controller.busy ||
                                        !controller.canSelect(row)
                                    ? null
                                    : () => controller.selectDraft(row),
                              ),
                          ],
                          if (groups.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 28,
                              ),
                              child: Text(
                                l.prototypeNoMatchingServers,
                                textAlign: TextAlign.center,
                                style: AppTypography.routingSelectionInput
                                    .copyWith(color: palette.mutedForeground),
                              ),
                            ),
                          Container(
                            constraints: const BoxConstraints(minHeight: 52),
                            padding: EdgeInsets.symmetric(
                              horizontal: mobile ? 12 : 14,
                              vertical: 10,
                            ),
                            color: palette.muted,
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.info,
                                  size: 17,
                                  color: palette.mutedForeground,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    l.prototypeFinalExitSelectionNote,
                                    style: AppTypography.routingSelectionNote
                                        .copyWith(
                                          color: palette.mutedForeground,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: PageActionBar(
            maxWidth: AppLayout.routingEditorMaxWidth,
            children: [
              if (!mobile)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.prototypeCancel),
                ),
              FilledButton(
                onPressed: controller.canFinish
                    ? () => controller.complete(context)
                    : null,
                child: Text(l.prototypeDone),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _search(BuildContext context, bool mobile) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Container(
      constraints: BoxConstraints(minHeight: mobile ? 54 : 58),
      padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 18, color: palette.mutedForeground),
          const SizedBox(width: 10),
          Expanded(
            child: RoutingSearchField(
              label: l.prototypeSearchServers,
              hint: l.prototypeSearchSubscriptionsServers,
              controller: controller.search,
              onChanged: controller.searchChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionRow extends StatelessWidget {
  const _SelectionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    this.type,
    this.protocol,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final String? type;
  final String? protocol;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return Opacity(
      opacity: onTap == null ? .48 : 1,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: onTap != null,
        child: Material(
          color: selected ? palette.selectedSurface : palette.card,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 62),
              padding: EdgeInsets.symmetric(
                horizontal: mobile ? 12 : 14,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.border)),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: icon == LucideIcons.shield ? 20 : 19,
                    color: palette.mutedStrong,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: AppTypography.routingSelectionTitle.copyWith(
                            color: palette.foreground,
                          ),
                        ),
                        for (final label in [
                          ?type,
                          if (protocol != null && protocol!.isNotEmpty)
                            protocol!,
                        ]) ...[
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: palette.surfaceHover,
                              border: Border.all(color: palette.border),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              label,
                              textDirection: TextDirection.ltr,
                              style: AppTypography.serverProtocol.copyWith(
                                color: palette.mutedStrong,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.routingSelectionDescription
                              .copyWith(color: palette.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 11),
                  Icon(
                    selected ? LucideIcons.check : LucideIcons.circle,
                    size: selected ? 19 : 18,
                    color: palette.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
