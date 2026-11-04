import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/controller.dart';
import 'package:onexray/pages/advanced/xray/fields.dart';
import 'package:onexray/pages/advanced/xray/log/params.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/shared/failure.dart';

class XrayLogSettingsPage extends StatelessWidget {
  const XrayLogSettingsPage({
    super.key,
    required this.onLog,
    this.createController,
  });

  final void Function(BuildContext, LogFileViewerParams) onLog;
  final XrayRuntimeController Function()? createController;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => createController?.call() ?? XrayRuntimeController(),
    child: BlocBuilder<XrayRuntimeController, XrayRuntimePageState>(
      builder: (context, state) {
        final controller = context.read<XrayRuntimeController>();
        final l = AppLocalizations.of(context)!;
        void cancel() {
          if (!controller.busy) Navigator.of(context).pop();
        }

        final available =
            !controller.loading &&
            controller.base != null &&
            !state.systemExtension;
        Widget toggle(String title, String field, bool value, String hint) =>
            XrayToggleField(
              title: title,
              description: hint,
              value: value,
              onChanged: controller.busy
                  ? null
                  : (value) => controller.setLog(field, value),
            );
        return PopScope(
          canPop: !controller.busy,
          child: Scaffold(
            appBar: PageAppBar(
              title: Text(l.prototypeLogs),
              leading: BackButton(onPressed: cancel),
              actions: [
                PageHelpButton(
                  title: l.prototypeLogs,
                  messages: [l.prototypeManagedLogNotice],
                ),
              ],
            ),
            body: SafeArea(
              child: controller.loading
                  ? const Center(child: CircularProgressIndicator())
                  : state.systemExtension
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l.logsUnavailableSystemExtension),
                      ),
                    )
                  : SettingsPageScroll(
                      desktopMaxWidth: AppLayout.advancedMaxWidth,
                      padding: EdgeInsets.fromLTRB(
                        MediaQuery.sizeOf(context).width <=
                                AppLayout.mobileBreakpoint
                            ? 16
                            : 28,
                        20,
                        MediaQuery.sizeOf(context).width <=
                                AppLayout.mobileBreakpoint
                            ? 16
                            : 28,
                        24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 20,
                        children: [
                          if (available) ...[
                            SettingSection(
                              title: l.xrayLogPreferences,
                              padding: EdgeInsets.zero,
                              children: [
                                toggle(
                                  l.prototypeRecordXrayLogs,
                                  'enabled',
                                  controller.logsEnabled,
                                  l.xrayRecordLogsHint,
                                ),
                                if (controller.logsEnabled) ...[
                                  const SizedBox(height: 12),
                                  XrayLabeledField(
                                    key: const ValueKey('xray-log-level-field'),
                                    label: l.prototypeErrorLogLevel,
                                    child: SettingSelect<String>(
                                      value: controller.level,
                                      textStyle: AppTypography.rowValue,
                                      entries: {
                                        'error': l.prototypeErrorsOnly,
                                        'warning': l.prototypeWarning,
                                        'info': 'Info',
                                        'debug': 'Debug',
                                      },
                                      onChanged: controller.busy
                                          ? null
                                          : controller.setLevel,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  toggle(
                                    l.prototypeRecordDnsQueries,
                                    'recordDns',
                                    controller.recordDns,
                                    l.xrayRecordDnsHint,
                                  ),
                                  toggle(
                                    l.prototypeHideLogIpAddresses,
                                    'maskIp',
                                    controller.maskIp,
                                    l.xrayMaskLogIpHint,
                                  ),
                                ],
                              ],
                            ),
                            SettingSection(
                              title: l.xrayLogFiles,
                              padding: EdgeInsets.zero,
                              children: [
                                for (final access in [true, false])
                                  SettingRow(
                                    title: access
                                        ? l.prototypeAccessLog
                                        : l.prototypeErrorLog,
                                    leading: Icon(
                                      access
                                          ? LucideIcons.fileText
                                          : LucideIcons.terminal,
                                    ),
                                    enabled: controller.logPath(access) != null,
                                    showChevron: true,
                                    onTap: controller.logPath(access) == null
                                        ? null
                                        : () => controller.openLog(
                                            context,
                                            access,
                                            onLog,
                                          ),
                                  ),
                              ],
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton.icon(
                                onPressed: controller.busy
                                    ? null
                                    : () {
                                        controller.restoreDefaults();
                                        ContextAlert.showToast(
                                          context,
                                          l.settingsDefaultsRestored,
                                        );
                                      },
                                icon: const Icon(
                                  LucideIcons.rotateCcw,
                                  size: 16,
                                ),
                                label: Text(l.prototypeRestoreDefaults),
                              ),
                            ),
                          ],
                          if (controller.failed)
                            SelectableText(
                              appFailureMessage(l, state.failure),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          if (controller.base == null)
                            TextButton(
                              onPressed: controller.load,
                              child: Text(l.prototypeRetry),
                            ),
                        ],
                      ),
                    ),
            ),
            bottomNavigationBar: available
                ? PageActionBar(
                    children: [
                      OutlinedButton(
                        onPressed: controller.busy ? null : cancel,
                        child: Text(l.prototypeCancel),
                      ),
                      FilledButton(
                        onPressed: controller.busy || controller.runtimeBusy
                            ? null
                            : () async {
                                await controller.save(context);
                                if (context.mounted &&
                                    controller.isPageActive &&
                                    !controller.dirty &&
                                    !controller.failed) {
                                  Navigator.of(context).pop(true);
                                }
                              },
                        child: ButtonProgress(
                          busy: controller.saving,
                          child: Text(
                            controller.connected
                                ? l.prototypeSaveAndReconnect
                                : l.prototypeSave,
                          ),
                        ),
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    ),
  );
}
