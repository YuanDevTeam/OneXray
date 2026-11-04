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
