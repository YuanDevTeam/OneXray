import 'package:onexray/service/shared/failure.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/data_update/controller.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AutoUpdatePage extends StatelessWidget {
  const AutoUpdatePage({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => AutoUpdateController(),
    child: BlocBuilder<AutoUpdateController, AutoUpdatePageState>(
      builder: (context, state) {
        final controller = context.read<AutoUpdateController>();
        final l = AppLocalizations.of(context)!;
        final value = state.autoUpdateState;
        final width = MediaQuery.sizeOf(context).width;
        final mobile = width <= AppLayout.mobileBreakpoint;
        final gutter = mobile ? 14.0 : AppSpacing.advancedDesktopGutter(width);
        return Scaffold(
          appBar: PageAppBar(
            title: Text(l.prototypeDataUpdates),
            actions: [
              const AppActivityIndicator(pinging: false),
              PageHelpButton(
                title: l.prototypeDataUpdates,
                messages: [
                  l.prototypeSubscriptionUpdateGuard,
                  l.prototypeGeodataUpdatesTogether,
                  l.prototypeUpdateTimingNotice,
                  l.prototypeDueUpdatesRetryNotice,
                ],
              ),
            ],
          ),
          bottomNavigationBar: PageActionBar(
            maxWidth: AppLayout.advancedMaxWidth,
            expandDesktop: true,
            horizontalPadding: mobile ? null : gutter,
            spacing: mobile ? AppSpacing.actionGap : 13,
            children: [
              OutlinedButton(
                onPressed: () => controller.cancel(context),
                child: Text(l.prototypeCancel),
              ),
              FilledButton(
                onPressed: !state.loaded || state.saving
                    ? null
                    : () => controller.save(context),
                child: ButtonProgress(
                  busy: state.saving,
                  child: Text(l.prototypeSave),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : !state.loaded
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l.prototypeTemporarilyUnavailable),
                        TextButton(
                          onPressed: controller.load,
                          child: Text(l.prototypeRetry),
                        ),
                      ],
                    ),
                  )
                : SettingsPageScroll(
                    desktopMaxWidth: AppLayout.advancedMaxWidth,
                    padding: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        mobile ? 12 : 48,
                        gutter,
                        mobile ? 26 : 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: mobile ? 25 : 28,
                        children: [
                          SettingSection(
                            title: l.prototypeSubscriptions,
                            icon: LucideIcons.refreshCw,
                            padding: EdgeInsets.zero,
                            dividerIndent: 0,
                            children: [
                              _automaticUpdates(
                                mobile: mobile,
                                title: l.prototypeAutomaticUpdates,
                                value: value.subscriptionEnabled,
                                onChanged: state.saving
                                    ? null
                                    : controller.updateSubscriptionEnabled,
                              ),
                              _interval(
                                l,
                                value.subscriptionInterval,
                                value.subscriptionEnabled && !state.saving,
                                controller.updateSubscriptionInterval,
                                mobile: mobile,
                              ),
                            ],
                          ),
                          SettingSection(
                            title: l.prototypeRoutingData,
                            icon: LucideIcons.globe2,
                            padding: EdgeInsets.zero,
                            dividerIndent: 0,
                            children: [
                              _automaticUpdates(
                                mobile: mobile,
                                title: l.prototypeAutomaticUpdates,
                                value: value.geoDataEnable,
                                onChanged: state.saving
                                    ? null
                                    : controller.updateGeoDataEnable,
                              ),
                              _interval(
                                l,
                                value.geoDataInterval,
                                value.geoDataEnable && !state.saving,
                                controller.updateGeoDataInterval,
                                mobile: mobile,
                              ),
                            ],
                          ),
                          if (state.failed)
                            Text(
                              appFailureMessage(l, state.failure),
                              style: AppTypography.settingsDetailNote.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    ),
  );

  Widget _automaticUpdates({
    required bool mobile,
    required String title,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) => SettingRow(
    title: title,
    titleStyle: AppTypography.settingsRow,
    minHeight: mobile ? 58 : 64,
    contentPadding: EdgeInsetsDirectional.symmetric(
      horizontal: mobile ? 13 : 14,
      vertical: mobile ? 7 : 9,
    ),
    enabled: onChanged != null,
    onTap: onChanged == null ? null : () => onChanged(!value),
    trailing: ShadSwitch(
      value: value,
      enabled: onChanged != null,
      onChanged: onChanged,
    ),
  );

  Widget _interval(
    AppLocalizations l,
    AutoUpdateInterval value,
    bool enabled,
    ValueChanged<AutoUpdateInterval?> onChanged, {
    required bool mobile,
  }) => SettingRow(
    title: l.prototypeUpdateInterval,
    titleStyle: mobile
        ? AppTypography.settingsRow
        : AppTypography.settingsSelect,
    minHeight: 62,
    contentPadding: const EdgeInsetsDirectional.symmetric(
      horizontal: 14,
      vertical: 10,
    ),
    trailing: SettingSelect<AutoUpdateInterval>(
      value: value,
      entries: {
        AutoUpdateInterval.oneDay: l.prototypeEveryDay,
        AutoUpdateInterval.threeDays: l.prototypeEveryThreeDays,
        AutoUpdateInterval.oneWeek: l.prototypeEveryWeek,
      },
      onChanged: enabled ? onChanged : null,
    ),
  );
}
