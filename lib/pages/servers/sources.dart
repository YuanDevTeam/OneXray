import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/subscription/user_info.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';
import 'package:onexray/pages/servers/details.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/main/navigation.dart';

/// The subscription destination shares all operations with the existing source
/// workflow, while opening a full content page for inspection.
class ServerSourcesView extends StatelessWidget {
  const ServerSourcesView({super.key, required this.controller});
  final ServersController controller;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ServersController, ServersPageState>(
    bloc: controller,
    builder: (context, state) {
      final l = AppLocalizations.of(context)!;
      final query = controller.query.trim().toLowerCase();
      final sources = state.sources
          .where(
            (source) =>
                query.isEmpty ||
                '${source.name} ${source.url}'.toLowerCase().contains(query),
          )
          .toList();
      final material = MaterialLocalizations.of(context);
      String checkedAt(SubscriptionData source) =>
          controller.sourceCheckedLabel(l, source.timestamp) ??
          '${material.formatMediumDate(source.timestamp.toLocal())} '
              '${material.formatTimeOfDay(TimeOfDay.fromDateTime(source.timestamp.toLocal()))}';
      void open(SubscriptionData source) => context.pushScoped(
        AppPageDestination.sourceDetails,
        extra: ServerSourceParams(controller: controller, sourceId: source.id),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          if (sources.isEmpty)
            SettingSection(
              title: l.prototypeSubscriptions,
              padding: EdgeInsets.zero,
              children: [
                Text(
                  query.isEmpty
                      ? l.prototypeNoServersYet
                      : l.prototypeNoMatchingSubscriptions,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton(
                    onPressed: query.isEmpty
                        ? () => controller.addServers(context)
                        : controller.search.clear,
                    child: Text(
                      query.isEmpty
                          ? l.prototypeAddSubscription
                          : l.prototypeClear,
                    ),
                  ),
                ),
              ],
            ),
          for (final source in sources)
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.card),
                onTap: () => open(source),
                child: SettingSection(
                  title: source.name,
                  description:
                      '${controller.providerSource(source) ? l.subscriptionModeProviderManaged : l.subscriptionModeAppManaged} · ${checkedAt(source)}',
                  padding: EdgeInsets.zero,
                  action: AppActivityBuilder(
                    builder: (context, activity) =>
                        controller.sourceBusy(source.id) && activity.downloading
                        ? const ButtonProgressIndicator()
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: state.sourceErrors.containsKey(source.id)
                                  ? ColorManager.palette(context)
                                        .destructiveSurface
                                  : ColorManager.palette(context).secondary,
                              borderRadius: BorderRadius.circular(
                                AppRadii.control,
                              ),
                            ),
                            child: Text(
                              state.sourceErrors.containsKey(source.id)
                                  ? l.resultFailed
                                  : l.prototypeUpdated,
                              style: AppTypography.badge.copyWith(
                                color: state.sourceErrors.containsKey(source.id)
                                    ? ColorManager.palette(context).destructive
                                    : ColorManager.palette(context)
                                          .secondaryForeground,
                              ),
                            ),
                          ),
                  ),
                  children: [
                    Text(
                      controller.providerSource(source)
                          ? l.providerConfigurationCount(
                              controller.sourceCount(source.id),
                            )
                          : l.prototypeServerCount(
                              controller.sourceCount(source.id),
                            ),
                      style: AppTypography.supporting.copyWith(
                        color: ColorManager.palette(context).mutedForeground,
                      ),
                    ),
                    if (SubscriptionUserInfo.fromSubscription(source)
                        case final info?) ...[
                      const SizedBox(height: 8),
                      SubscriptionPackageSummary(info: info),
                    ],
                    if (state.sourceErrors[source.id] case final error?) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        error,
                        style: AppTypography.supporting.copyWith(
                          color: ColorManager.palette(context).destructive,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: controller.sourceBusy(source.id)
                              ? null
                              : () => controller.sourceAction(
                                  context,
                                  source,
                                  SourceAction.update,
                                ),
                          icon: const Icon(LucideIcons.refreshCw, size: 18),
                          label: Text(l.prototypeCheckForUpdates),
                        ),
                        IconButton(
                          tooltip: '${l.prototypeMoreActions}: ${source.name}',
                          onPressed: () => open(source),
                          icon: const Icon(
                            LucideIcons.chevronRightDir,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class ServerSourcesDialog extends StatelessWidget {
  const ServerSourcesDialog({super.key, required this.controller});

  final ServersController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      title: l.prototypeManageSources,
      subtitle: l.prototypeSourceUpdateGuard,
      body: BlocBuilder<ServersController, ServersPageState>(
        bloc: controller,
        builder: (context, _) {
          final material = MaterialLocalizations.of(context);
          final localCount = controller.sourceCount(0);
          String checkedAt(SubscriptionData source) =>
              controller.sourceCheckedLabel(l, source.timestamp) ??
              '${material.formatMediumDate(source.timestamp.toLocal())} '
                  '${material.formatTimeOfDay(TimeOfDay.fromDateTime(source.timestamp.toLocal()))}';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AppActivityIndicator(pinging: false),
                ),
                if (controller.sources.isEmpty && localCount == 0)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.prototypeNoServersYet),
                  ),
                if (localCount > 0)
                  _SourceRow(
                    name: l.prototypeManualAdditions,
                    detail:
                        '${l.prototypeServerCount(localCount)} · ${l.prototypeLocalOnly}',
                    status: l.prototypeStoredOnThisDevice,
                    showDivider: controller.sources.isNotEmpty,
                  ),
                for (final source in controller.sources)
                  _SourceRow(
                    name: source.name,
                    package: SubscriptionUserInfo.fromSubscription(source),
                    detail:
                        '${controller.providerSource(source) ? l.providerConfigurationCount(controller.sourceCount(source.id)) : l.prototypeServerCount(controller.sourceCount(source.id))} · '
                        '${checkedAt(source)}',
                    status:
                        controller.sourceErrors[source.id] ??
                        l.prototypeUpdated,
                    failed: controller.sourceErrors.containsKey(source.id),
                    showDivider: source != controller.sources.last,
                    subscription: true,
                    busy: controller.sourceBusy(source.id),
                    onMore: controller.sourceBusy(source.id)
                        ? null
                        : () =>
                              Navigator.of(context)
                                  .pop<SubscriptionData>(source),
                    onUpdate: controller.sourceBusy(source.id)
                        ? null
                        : () => controller.sourceAction(
                            context,
                            source,
                            SourceAction.update,
                          ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ServerHelpDialog extends StatelessWidget {
  const ServerHelpDialog({super.key, required this.canScanQr});

  final bool canScanQr;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      title: l.prototypeHowToGetServers,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 4),
        child: Column(
          children: [
            _HelpRow(icon: LucideIcons.link2, text: l.prototypeAskVpnProvider),
            const SizedBox(height: 15),
            _HelpRow(
              icon: canScanQr ? LucideIcons.qrCode : LucideIcons.fileInput,
              text: canScanQr
                  ? l.prototypeScanServerQrOrImportConfiguration
                  : l.prototypeImportConfigurationFileHint,
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.prototypeDone),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.prototypeAddServer),
        ),
      ],
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: palette.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTypography.dialogBody.copyWith(color: palette.foreground),
          ),
        ),
      ],
    );
  }
}

class SourceUpdateErrorDialog extends StatelessWidget {
  const SourceUpdateErrorDialog({
    super.key,
    required this.sourceName,
    this.reason,
    this.existingNodesKept = true,
  });

  final String sourceName;
  final String? reason;
  final bool existingNodesKept;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return AppDialog(
      title: l.prototypeSubscriptionUpdateFailed,
      subtitle: sourceName,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.destructiveSurface,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.circleAlert,
                    size: 21,
                    color: palette.destructive,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: SelectableText(
                      [
                        ?reason,
                        if (existingNodesKept)
                          l.prototypeSubscriptionExistingNodesKept,
                      ].join('\n\n'),
                      style: AppTypography.dialogCallout.copyWith(
                        color: palette.destructive,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.prototypeDone),
        ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.name,
    required this.detail,
    required this.status,
    required this.showDivider,
    this.subscription = false,
    this.failed = false,
    this.busy = false,
    this.onMore,
    this.onUpdate,
    this.package,
  });

  final String name;
  final String detail;
  final String status;
  final bool showDivider;
  final bool subscription;
  final bool failed;
  final bool busy;
  final VoidCallback? onMore;
  final VoidCallback? onUpdate;
  final SubscriptionUserInfo? package;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final statusLabel = Text(
      status,
      style: AppTypography.serverSelectionHealth.copyWith(
        color: failed ? palette.destructive : palette.running,
      ),
    );
    final actionStyle = IconButton.styleFrom(
      foregroundColor: palette.mutedStrong,
      iconSize: 18,
      padding: EdgeInsets.zero,
      minimumSize: Size.square(
        AppLayout.touchExtent(36, platform: Theme.of(context).platform),
      ),
      fixedSize: Size.square(
        AppLayout.touchExtent(36, platform: Theme.of(context).platform),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: EdgeInsets.symmetric(horizontal: mobile ? 14 : 18, vertical: 11),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: palette.border))
            : null,
      ),
      child: Row(
        children: [
          AppActivityBuilder(
            builder: (context, activity) =>
                subscription && busy && activity.downloading
                ? const ButtonProgressIndicator(size: 20)
                : Icon(LucideIcons.link2, size: 20, color: palette.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.serverMenuTitle.copyWith(
                    color: palette.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.serverMenuHint.copyWith(
                    color: palette.mutedForeground,
                  ),
                ),
                if (package != null) ...[
                  const SizedBox(height: 4),
                  SubscriptionPackageSummary(info: package!),
                ],
                if (mobile) ...[const SizedBox(height: 10), statusLabel],
              ],
            ),
          ),
          if (!mobile) ...[const SizedBox(width: 10), statusLabel],
          if (subscription) ...[
            if (!mobile) ...[
              const SizedBox(width: 10),
              IconButton(
                tooltip: l.prototypeCheckForUpdates,
                style: actionStyle,
                onPressed: onUpdate,
                icon: AppActivityBuilder(
                  builder: (context, activity) => busy && activity.downloading
                      ? const ButtonProgressIndicator()
                      : const Icon(LucideIcons.refreshCw),
                ),
              ),
            ],
            const SizedBox(width: 10),
            IconButton(
              tooltip: '${l.prototypeMoreActions}: $name',
              style: actionStyle,
              onPressed: onMore,
              icon: busy && mobile
                  ? const ButtonProgressIndicator()
                  : const Icon(LucideIcons.ellipsis),
            ),
          ],
        ],
      ),
    );
  }
}
