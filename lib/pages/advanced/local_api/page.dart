import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/local_api/controller.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class LocalApiPage extends StatelessWidget {
  const LocalApiPage({super.key, this.createController});

  final LocalApiController Function()? createController;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => createController?.call() ?? LocalApiController(),
    child: BlocBuilder<LocalApiController, LocalApiPageState>(
      builder: (context, state) {
        final controller = context.read<LocalApiController>();
        final l = AppLocalizations.of(context)!;
        final palette = ColorManager.palette(context);
        final width = MediaQuery.sizeOf(context).width;
        final compact = width <= AppLayout.mobileBreakpoint;
        final gutter = compact
            ? AppSpacing.mobilePage
            : AppSpacing.advancedDesktopGutter(width);
        return Scaffold(
          appBar: PageAppBar.forPage(
            context,
            title: Text(l.localApiTitle),
            description: l.localApiSummary,
          ),
          bottomNavigationBar: PageActionBar(
            maxWidth: AppLayout.advancedMaxWidth,
            expandDesktop: false,
            horizontalPadding: compact ? null : gutter,
            children: [
              OutlinedButton(
                onPressed: () => context.pop(),
                child: Text(l.prototypeCancel),
              ),
              FilledButton(
                key: const ValueKey('local-api-save'),
                onPressed: !state.loaded || state.busy
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
                : SettingsPageScroll(
                    desktopMaxWidth: AppLayout.advancedMaxWidth,
                    padding: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (state.loaded) ...[
                            SettingSection(
                              title: l.localApiTitle,
                              icon: LucideIcons.terminal,
                              padding: EdgeInsets.zero,
                              children: [
                                SettingRow(
                                  title: l.localApiEnable,
                                  titleMaxLines: 4,
                                  trailing: AppSwitch(
                                    key: const ValueKey('local-api-enabled'),
                                    value: state.enabled,
                                    enabled: !state.busy,
                                    onChanged: state.busy
                                        ? null
                                        : controller.setEnabled,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        l.localApiPort,
                                        style: AppTypography.fieldLabel
                                            .copyWith(
                                              color: palette.foreground,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Semantics(
                                        label: l.localApiPort,
                                        child: TextField(
                                          key: const ValueKey('local-api-port'),
                                          controller: controller.portController,
                                          enabled: !state.busy,
                                          keyboardType: TextInputType.number,
                                          textDirection: TextDirection.ltr,
                                          textAlign: TextAlign.left,
                                          autocorrect: false,
                                          style: AppTypography.rowValue,
                                          decoration: const InputDecoration(
                                            hintText: '18587',
                                            hintTextDirection:
                                                TextDirection.ltr,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SettingRow(
                                  title: l.prototypeRuntimeStatus,
                                  subtitleWidget: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        state.listening
                                            ? l.localApiListening
                                            : l.localApiStopped,
                                      ),
                                      if (state.runtimeError != null)
                                        Text(
                                          state.runtimeError!,
                                          style: AppTypography
                                              .settingsDetailNote
                                              .copyWith(
                                                color: palette.destructive,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        l.localApiEndpoint,
                                        style: AppTypography.rowTitle,
                                      ),
                                      const SizedBox(height: 8),
                                      SelectableText(
                                        state.saved!.endpoint,
                                        key: const ValueKey(
                                          'local-api-endpoint',
                                        ),
                                        textDirection: TextDirection.ltr,
                                        textAlign: TextAlign.left,
                                        style: AppTypography.settingsInput,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            SettingSection(
                              title: l.localApiToken,
                              icon: LucideIcons.keyRound,
                              action: PageHelpButton(
                                title: l.localApiToken,
                                messages: [l.localApiTokenHint],
                              ),
                              descriptionBelow: true,
                              padding: EdgeInsets.zero,
                              children: [
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 10,
                                    children: [
                                      OutlinedButton(
                                        key: const ValueKey(
                                          'local-api-copy-token',
                                        ),
                                        onPressed:
                                            state.busy ||
                                                state.saved!.token.isEmpty
                                            ? null
                                            : () =>
                                                  controller.copyToken(context),
                                        child: ButtonProgress(
                                          busy: state.copying,
                                          child: Text(l.localApiCopyToken),
                                        ),
                                      ),
                                      OutlinedButton(
                                        key: const ValueKey(
                                          'local-api-reset-token',
                                        ),
                                        onPressed: state.busy
                                            ? null
                                            : () => controller.resetToken(
                                                context,
                                              ),
                                        child: ButtonProgress(
                                          busy: state.resetting,
                                          child: Text(l.localApiResetToken),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              l.localApiAppRequired,
                              style: AppTypography.supporting.copyWith(
                                color: palette.mutedForeground,
                              ),
                            ),
                          ],
                          if (state.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                state.error!,
                                key: const ValueKey('local-api-error'),
                                style: AppTypography.supporting.copyWith(
                                  color: palette.destructive,
                                ),
                              ),
                            ),
                          if (!state.loaded)
                            TextButton(
                              onPressed: controller.load,
                              child: Text(l.prototypeRetry),
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
