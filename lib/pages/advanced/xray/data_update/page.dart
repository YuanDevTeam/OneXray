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
import 'package:onexray/pages/advanced/xray/fields.dart';

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
        final gutter = mobile
            ? AppSpacing.mobilePage
            : AppSpacing.advancedDesktopGutter(width);
        return Scaffold(
          appBar: PageAppBar.forPage(
            context,
            title: Text(l.prototypeAutomaticUpdates),
            description: l.pageXrayConfigurationDescription,
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
            expandDesktop: false,
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
                        20,
                        gutter,
                        mobile ? 26 : 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 20,
                        children: [
                          SettingSection(
                            title: l.prototypeUpdateInterval,
                            padding: EdgeInsets.zero,
                            children: [
                              XrayToggleField(
                                title: l.xrayAutomaticSubscriptionUpdates,
                                value: value.subscriptionEnabled,
                                onChanged: state.saving
                                    ? null
                                    : controller.updateSubscriptionEnabled,
                              ),
                              const SizedBox(height: 16),
                              XrayLabeledField(
                                key: const ValueKey(
                                  'subscription-update-interval-field',
                                ),
                                label: l.xraySubscriptionUpdateInterval,
                                child: SettingSelect<AutoUpdateInterval>(
                                  key: const ValueKey(
                                    'subscription-update-interval',
                                  ),
                                  value: value.subscriptionInterval,
                                  entries: _intervals(l),
                                  onChanged:
                                      value.subscriptionEnabled && !state.saving
                                      ? controller.updateSubscriptionInterval
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 24),
                              XrayToggleField(
                                title: l.xrayAutomaticGeodataUpdates,
                                value: value.geoDataEnable,
                                onChanged: state.saving
                                    ? null
                                    : controller.updateGeoDataEnable,
                              ),
                              const SizedBox(height: 16),
                              XrayLabeledField(
                                key: const ValueKey(
                                  'geodata-update-interval-field',
                                ),
                                label: l.xrayGeodataUpdateInterval,
                                child: SettingSelect<AutoUpdateInterval>(
                                  key: const ValueKey(
                                    'geodata-update-interval',
                                  ),
                                  value: value.geoDataInterval,
                                  entries: _intervals(l),
                                  onChanged:
                                      value.geoDataEnable && !state.saving
                                      ? controller.updateGeoDataInterval
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          if (state.failed)
                            Text(
                              appFailureMessage(l, state.failure),
                              style: AppTypography.supporting.copyWith(
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

  Map<AutoUpdateInterval, String> _intervals(AppLocalizations l) => {
    AutoUpdateInterval.oneDay: l.prototypeEveryDay,
    AutoUpdateInterval.threeDays: l.prototypeEveryThreeDays,
    AutoUpdateInterval.oneWeek: l.prototypeEveryWeek,
  };
}
