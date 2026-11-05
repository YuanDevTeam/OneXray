import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
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
import 'package:onexray/pages/advanced/xray/fields.dart';
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
        final gutter = mobile
            ? AppSpacing.mobilePage
            : AppSpacing.advancedDesktopGutter(width);
        return Scaffold(
          appBar: PageAppBar(
            title: Text(l.xrayLatencyTitle),
            actions: [
              const AppActivityIndicator(downloading: false),
              PageHelpButton(
                title: l.prototypeSpeedTest,
                messages: [
                  l.prototypeSpeedTestUrlHint,
                  l.prototypeSpeedTestSavedNotice,
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
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l.prototypeTemporarilyUnavailable),
                          if (state.error != null)
                            Semantics(
                              liveRegion: true,
                              child: SelectableText(
                                state.error!,
                                style: AppTypography.supporting.copyWith(
                                  color: palette.destructive,
                                ),
                              ),
                            ),
                          TextButton(
                            onPressed: controller.load,
                            child: Text(l.prototypeRetry),
                          ),
                        ],
                      ),
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
                        children: [
                          SettingSection(
                            title: l.xrayLatencyTitle,
                            padding: EdgeInsets.zero,
                            children: [
                              XrayLabeledField(
                                key: const ValueKey('ping-url-field'),
                                label: l.prototypeSpeedTestUrl,
                                child: SettingSelect<String>(
                                  key: const ValueKey('ping-url-preset'),
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
                              const SizedBox(height: 16),
                              if (value.url == PingUrl.custom)
                                XrayLabeledField(
                                  key: const ValueKey('ping-custom-url-field'),
                                  label: l.prototypeCustomUrl,
                                  child: TextField(
                                    key: const ValueKey('ping-custom-url'),
                                    controller: controller.customUrlController,
                                    focusNode: controller.customUrlFocusNode,
                                    enabled: !state.saving,
                                    textDirection: TextDirection.ltr,
                                    textAlign: TextAlign.left,
                                    keyboardType: TextInputType.url,
                                    autocorrect: false,
                                    style: AppTypography.settingsInput.copyWith(
                                      color: palette.foreground,
                                    ),
                                    decoration: InputDecoration(
                                      errorText: state.invalidUrl
                                          ? l.prototypeEnterHttpUrl
                                          : null,
                                      errorMaxLines: 3,
                                      isDense: true,
                                      hintText:
                                          'https://example.com/generate_204',
                                      hintTextDirection: TextDirection.ltr,
                                      hintStyle: AppTypography.settingsInput
                                          .copyWith(
                                            color: palette.mutedForeground,
                                          ),
                                    ),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  child: SelectableText(
                                    value.realUrl,
                                    textDirection: TextDirection.ltr,
                                    textAlign: TextAlign.left,
                                    style: AppTypography.rowValue.copyWith(
                                      color: palette.mutedStrong,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              XrayLabeledField(
                                key: const ValueKey('ping-timeout-field'),
                                label: l.prototypeTimeout,
                                child: SettingSelect<double>(
                                  key: const ValueKey('ping-timeout'),
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
                              const SizedBox(height: 16),
                              ShadAlert(
                                icon: const Icon(
                                  LucideIcons.circleHelp,
                                  size: 18,
                                ),
                                description: Text(
                                  l.pingVpnAccuracyHint,
                                  style: AppTypography.supporting.copyWith(
                                    color: palette.mutedForeground,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (state.error != null)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                top: 10,
                              ),
                              child: Semantics(
                                liveRegion: true,
                                child: SelectableText(
                                  state.error!,
                                  style: AppTypography.supporting.copyWith(
                                    color: palette.destructive,
                                  ),
                                ),
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
