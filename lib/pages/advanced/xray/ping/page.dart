import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/ping/controller.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/service/shared/ping/state.dart';

class PingPage extends StatelessWidget {
  const PingPage({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PingController(),
    child: BlocBuilder<PingController, PingPageState>(
      builder: (context, state) {
        final controller = context.read<PingController>();
        final l = AppLocalizations.of(context)!;
        final value = state.pingState;
        final palette = ColorManager.palette(context);
        final width = MediaQuery.sizeOf(context).width;
        final mobile = width <= AppLayout.mobileBreakpoint;
        final gutter = mobile ? 14.0 : AppSpacing.advancedDesktopGutter(width);
        return Scaffold(
          appBar: PageAppBar(
            title: Text(l.prototypeSpeedTest),
            actions: const [AppActivityIndicator(downloading: false)],
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
                        children: [
                          SettingSection(
                            title: l.prototypeTimeout,
                            icon: LucideIcons.activity,
                            description: l.prototypeTimeoutHint,
                            descriptionBelow: true,
                            padding: EdgeInsets.zero,
                            children: [
                              SettingRow(
                                title: l.prototypeTimeout,
                                titleStyle: AppTypography.settingsSelect,
                                contentPadding:
                                    const EdgeInsetsDirectional.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                trailing: SettingSelect<double>(
                                  value: value.timeout,
                                  entries: {
                                    for (
                                      var seconds = PingTimeout.min;
                                      seconds <= PingTimeout.max;
                                      seconds++
                                    )
                                      seconds: l.prototypeSeconds(
                                        seconds.round(),
                                      ),
                                  },
                                  onChanged: state.saving
                                      ? null
                                      : (seconds) {
                                          if (seconds != null) {
                                            controller.updateTimeout(seconds);
                                          }
                                        },
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: mobile ? 25 : 28),
                          SettingSection(
                            title: l.prototypeSpeedTestUrl,
                            icon: LucideIcons.globe,
                            description: l.prototypeSpeedTestUrlHint,
                            descriptionBelow: true,
                            padding: EdgeInsets.zero,
                            dividerIndent: 0,
                            children: [
                              SettingRow(
                                title: l.prototypeSpeedTestUrl,
                                titleStyle: AppTypography.settingsSelect,
                                contentPadding:
                                    const EdgeInsetsDirectional.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                trailing: SettingSelect<String>(
                                  value: value.url.name,
                                  entries: {
                                    for (final option in PingUrl.values)
                                      option.name: option == PingUrl.custom
                                          ? l.prototypeCustom
                                          : option.name,
                                  },
                                  onChanged: state.saving
                                      ? null
                                      : (url) {
                                          if (url != null) {
                                            controller.updateUrl(url);
                                          }
                                        },
                                ),
                              ),
                              if (value.url == PingUrl.custom)
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l.prototypeCustomUrl,
                                        style: AppTypography.settingsInput
                                            .copyWith(
                                              color: palette.foreground,
                                            ),
                                      ),
                                      const SizedBox(height: 9),
                                      TextField(
                                        controller:
                                            controller.customUrlController,
                                        enabled: !state.saving,
                                        textDirection: TextDirection.ltr,
                                        textAlign: TextAlign.left,
                                        keyboardType: TextInputType.url,
                                        autocorrect: false,
                                        style: AppTypography.settingsInput
                                            .copyWith(
                                              color: palette.foreground,
                                            ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          constraints: const BoxConstraints(
                                            minHeight: 40,
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 8,
                                              ),
                                          hintText: 'https://example.com/generate_204',
                                          hintTextDirection: TextDirection.ltr,
                                          hintStyle: AppTypography.settingsInput
                                              .copyWith(
                                                color: palette.mutedForeground,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                SizedBox(
                                  height: 46,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: SelectableText(
                                        value.realUrl,
                                        textDirection: TextDirection.ltr,
                                        textAlign: TextAlign.left,
                                        style:
                                            (mobile
                                                    ? AppTypography
                                                          .settingsDetailNote
                                                    : AppTypography
                                                          .settingsInput)
                                                .copyWith(
                                                  color: palette.mutedStrong,
                                                ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: mobile ? 25 : 28),
                          Text(
                            l.pingVpnAccuracyHint,
                            style: AppTypography.settingsDetailNote.copyWith(
                              color: palette.mutedForeground,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l.prototypeSpeedTestSavedNotice,
                            style: AppTypography.settingsDetailNote.copyWith(
                              color: palette.mutedForeground,
                            ),
                          ),
                          if (state.error != null)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                top: 10,
                              ),
                              child: Text(
                                state.error!,
                                style: AppTypography.settingsDetailNote
                                    .copyWith(color: palette.destructive),
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
}
