import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/android/automation/controller.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/advanced/tunnel/android/automation/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AndroidAutomationPage extends StatelessWidget {
  const AndroidAutomationPage({super.key, this.createController});
  final AutomationController Function()? createController;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => createController?.call() ?? AutomationController(),
    child: BlocBuilder<AutomationController, AutomationPageState>(
      builder: (context, state) {
        final controller = context.read<AutomationController>();
        final l = AppLocalizations.of(context)!;
        return Scaffold(
          appBar: PageAppBar(
            title: Text(l.automationTitle),
            actions: [
              PageHelpButton(
                title: l.automationTitle,
                messages: [l.automationSummary, l.automationPermissionHint],
              ),
            ],
          ),
          body: SafeArea(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : SettingsPageScroll(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.mobilePage,
                      16,
                      AppSpacing.mobilePage,
                      24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.saved != null) ...[
                          SettingSection(
                            title: l.automationTitle,
                            headerInset: 0,
                            descriptionBelow: true,
                            padding: EdgeInsets.zero,
                            children: [
                              SettingRow(
                                title: l.automationEnable,
                                titleMaxLines: 5,
                                trailing: ButtonProgress(
                                  busy: state.writing == 'enable',
                                  child: ShadSwitch(
                                    key: const ValueKey('automation-enable'),
                                    value: state.saved!.enabled,
                                    enabled: state.writing == null,
                                    onChanged: state.writing == null
                                        ? (value) => controller.setEnabled(
                                            context,
                                            value,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          if (state.saved!.enabled) ...[
                            SettingSection(
                              title: l.localApiToken,
                              headerInset: 0,
                              padding: EdgeInsets.zero,
                              description: l.automationTokenHint,
                              descriptionBelow: true,
                              separated: false,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Wrap(
                                      spacing: 12,
                                      runSpacing: 10,
                                      children: [
                                        OutlinedButton(
                                          key: const ValueKey(
                                            'automation-copy-token',
                                          ),
                                          onPressed:
                                              state.copying.contains('token') ||
                                                  state.saved!.token == null
                                              ? null
                                              : () => controller.copy(
                                                  context,
                                                  'token',
                                                  state.saved!.token!,
                                                ),
                                          child: ButtonProgress(
                                            busy: state.copying.contains(
                                              'token',
                                            ),
                                            child: Text(l.localApiCopyToken),
                                          ),
                                        ),
                                        OutlinedButton(
                                          key: const ValueKey(
                                            'automation-reset-token',
                                          ),
                                          onPressed: state.writing != null
                                              ? null
                                              : () => controller.resetToken(
                                                  context,
                                                ),
                                          child: ButtonProgress(
                                            busy: state.writing == 'reset',
                                            child: Text(l.localApiResetToken),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                          ],
                        ],
                        SettingSection(
                          title: l.automationParameters,
                          headerInset: 0,
                          padding: EdgeInsets.zero,
                          separated: false,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: SizedBox(
                                width: double.infinity,
                                child: SelectableText(
                                  AndroidAutomationService.parameters,
                                  textDirection: TextDirection.ltr,
                                  textAlign: TextAlign.left,
                                  style: AppTypography.code,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: OutlinedButton(
                                  key: const ValueKey(
                                    'automation-copy-parameters',
                                  ),
                                  onPressed:
                                      state.copying.contains('parameters')
                                      ? null
                                      : () => controller.copy(
                                          context,
                                          'parameters',
                                          AndroidAutomationService.parameters,
                                        ),
                                  child: ButtonProgress(
                                    busy: state.copying.contains('parameters'),
                                    child: Text(l.automationCopyParameters),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          l.automationConfigurationHint,
                          style: AppTypography.settingsDetailNote,
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: state.openingHelp
                                ? null
                                : () => controller.openHelp(context),
                            child: ButtonProgress(
                              busy: state.openingHelp,
                              child: Text(l.automationHelp),
                            ),
                          ),
                        ),
                        if (state.error != null)
                          Text(
                            state.error!,
                            key: const ValueKey('automation-error'),
                            style: AppTypography.settingsDetailNote.copyWith(
                              color: ColorManager.palette(context).destructive,
                            ),
                          ),
                        if (state.saved == null)
                          TextButton(
                            onPressed: controller.load,
                            child: Text(l.prototypeRetry),
                          ),
                      ],
                    ),
                  ),
          ),
        );
      },
    ),
  );
}
