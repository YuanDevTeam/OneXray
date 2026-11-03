import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/controller.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RoutingPage extends StatefulWidget {
  const RoutingPage({super.key});

  @override
  State<RoutingPage> createState() => _RoutingPageState();
}

class _RoutingPageState extends State<RoutingPage> {
  final controller = RoutingPageController();

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<RoutingPageController, RoutingPageState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final settings = state.configuration?.connection;
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        final gutter = mobile ? AppSpacing.mobilePage : AppSpacing.page;
        final palette = ColorManager.palette(context);
        return Scaffold(
          appBar: PageAppBar(title: Text(l.navigationRouting)),
          body: SafeArea(
            child: settings == null
                ? Center(
                    child: state.failed
                        ? TextButton(
                            onPressed: controller.load,
                            child: Text(l.prototypeRetry),
                          )
                        : const CircularProgressIndicator(),
                  )
                : SettingsPageScroll(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      gutter,
                      16,
                      gutter,
                      24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 16,
                      children: [
                        Text(
                          l.routingPageDescription,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.mutedForeground),
                        ),
                        if (state.completeConfiguration)
                          ShadAlert(
                            icon: const Icon(LucideIcons.info, size: 18),
                            description: Text(l.routingStoredPreferenceNotice),
                          ),
                        SettingSection(
                          title: l.prototypeTrafficMethod,
                          padding: EdgeInsets.zero,
                          dividerIndent: 0,
                          children: [
                            _choice(
                              context,
                              title: l.prototypeSmartRouting,
                              description: l.prototypeSmartRoutingDescription,
                              selected:
                                  settings.trafficMode == TrafficMode.smart,
                              icon: LucideIcons.sparkles,
                              onUse: () =>
                                  controller.select(context, TrafficMode.smart),
                              onEdit: () => context.pushScoped(
                                AppPageDestination.smartRouting,
                              ),
                            ),
                            _choice(
                              context,
                              title: l.prototypeAllViaVpn,
                              description: l.prototypeAllViaVpnDescription,
                              selected:
                                  settings.trafficMode == TrafficMode.allVpn,
                              icon: LucideIcons.shield,
                              onUse: () => controller.select(
                                context,
                                TrafficMode.allVpn,
                              ),
                            ),
                          ],
                        ),
                        SettingSection(
                          title: l.prototypeCustomRouting,
                          description: l.prototypeCustomRouteLimit,
                          action: ShadButton.outline(
                            size: ShadButtonSize.sm,
                            enabled: !state.busy && state.profiles.length < 3,
                            onPressed: () => controller.edit(context),
                            leading: const Icon(LucideIcons.plus, size: 16),
                            child: Text(l.prototypeNewCustomRoute),
                          ),
                          padding: EdgeInsets.zero,
                          dividerIndent: 0,
                          children: [
                            for (final row in state.profiles)
                              _choice(
                                context,
                                title: row.name,
                                description: row.advanced
                                    ? l.routingAdvancedJson
                                    : '${l.routingNormalConfiguration} · ${l.prototypeRuleCount(controller.configurationFor(row).ruleCount)}',
                                selected:
                                    settings.trafficMode ==
                                        TrafficMode.custom &&
                                    settings.customId == row.id,
                                icon: row.advanced
                                    ? LucideIcons.fileJson
                                    : LucideIcons.listOrdered,
                                onUse: () => controller.select(
                                  context,
                                  TrafficMode.custom,
                                  id: row.id,
                                ),
                                onEdit: () => controller.edit(context, row),
                                onDelete: () => controller.delete(context, row),
                              ),
                            if (state.profiles.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  l.prototypeCustomRoutingDescription,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: palette.mutedForeground,
                                      ),
                                ),
                              ),
                          ],
                        ),
                        SettingSection(
                          title: l.prototypeRoutingData,
                          padding: EdgeInsets.zero,
                          children: [
                            SettingRow(
                              title: l.prototypeRoutingDataSummary,
                              subtitle: l.prototypeRoutingDataHint,
                              leading: const Icon(
                                LucideIcons.database,
                                size: 19,
                              ),
                              decorateLeading: false,
                              showChevron: true,
                              onTap: () => context.pushScoped(
                                AppPageDestination.routingData,
                              ),
                            ),
                          ],
                        ),
                        if (state.failed || state.error != null)
                          ShadAlert.destructive(
                            description: Text(
                              state.error ?? l.prototypeTemporarilyUnavailable,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        );
      },
    ),
  );

  Widget _choice(
    BuildContext context, {
    required String title,
    required String description,
    required bool selected,
    required IconData icon,
    required VoidCallback onUse,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Semantics(
      selected: selected,
      child: Container(
        color: selected ? palette.selectedSurface : null,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12, top: 2),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected ? palette.primary : palette.mutedStrong,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: palette.mutedForeground),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: Icon(
                      LucideIcons.circleCheck,
                      size: 20,
                      color: palette.primary,
                    ),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ShadButton(
                  size: ShadButtonSize.sm,
                  enabled: !controller.state.busy && !selected,
                  onPressed: onUse,
                  child: Text(
                    selected ? l.prototypeCurrentSelection : l.prototypeUse,
                  ),
                ),
                if (onEdit != null)
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    enabled: !controller.state.busy,
                    onPressed: onEdit,
                    child: Text(l.prototypeEdit),
                  ),
                if (onDelete != null)
                  ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    enabled: !controller.state.busy,
                    onPressed: onDelete,
                    leading: const Icon(LucideIcons.trash2, size: 16),
                    child: Text(l.prototypeDelete),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
