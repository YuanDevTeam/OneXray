import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tab_visibility.dart';
import 'package:onexray/pages/advanced/xray/config/params.dart';
import 'package:onexray/pages/advanced/xray/controller.dart';
import 'package:onexray/pages/advanced/xray/log/params.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Reads coordinator and saved runtime facts without changing the connection.
class XrayDiagnosticsPage extends StatelessWidget {
  final void Function(BuildContext, LogFileViewerParams) onLog;
  final void Function(BuildContext, ConfigFileViewerParams) onConfig;
  final XrayRuntimeController Function()? createController;

  const XrayDiagnosticsPage({
    super.key,
    required this.onLog,
    required this.onConfig,
    this.createController,
  });

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => createController?.call() ?? XrayRuntimeController(),
    child: BlocBuilder<XrayRuntimeController, XrayRuntimePageState>(
      builder: (context, state) {
        final controller = context.read<XrayRuntimeController>();
        final l = AppLocalizations.of(context)!;
        final palette = ColorManager.palette(context);
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        final gutter = mobile ? AppSpacing.mobilePage : AppSpacing.page;
        return AdvancedTabVisibility(
          tabIndex: 1,
          onChanged: controller.reader.setVisible,
          child: Scaffold(
            appBar: PageAppBar.forPage(
              context,
              title: Text(l.xrayDiagnostics),
              description: l.xrayDiagnosticsHint,
              actions: [
                IconButton(
                  tooltip: l.xrayRefreshStatus,
                  onPressed: state.loading ? null : () => controller.load(),
                  icon: state.loading
                      ? const ButtonProgressIndicator()
                      : const Icon(LucideIcons.refreshCw, size: 19),
                ),
              ],
            ),
            body: SafeArea(
              child: SettingsPageScroll(
                padding: EdgeInsetsDirectional.fromSTEB(gutter, 20, gutter, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 20,
                  children: [
                    SettingSection(
                      title: l.prototypeRuntimeStatus,
                      padding: EdgeInsets.zero,
                      children: [
                        SettingRow(
                          title: l.prototypeXrayCore,
                          value: controller.statusLabel(l),
                          valueStyle: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: state.connection.failed
                                    ? palette.destructive
                                    : palette.foreground,
                              ),
                        ),
                        SettingRow(
                          title: l.prototypeVersion,
                          value: controller.xrayVersion,
                          valueTextDirection: TextDirection.ltr,
                        ),
                        SettingRow(
                          title: l.prototypeUptime,
                          value: controller.uptime,
                          valueTextDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                    if (state.connection.failed)
                      ShadAlert.destructive(
                        icon: const Icon(LucideIcons.circleAlert, size: 19),
                        title: Text(l.prototypeConnectionFailed),
                        description: SelectableText(
                          state.connection.error == null
                              ? nativeOperationFailureTitle(
                                      l,
                                      state.connection.issue,
                                    ) ??
                                    l.prototypeConnectionFailed
                              : appFailureMessage(l, state.connection.error),
                        ),
                      )
                    else if (!state.loading && !state.failed)
                      ShadAlert(
                        icon: const Icon(LucideIcons.info, size: 19),
                        description: Text(l.xrayNoConnectionError),
                      ),
                    if (state.failed)
                      ShadAlert.destructive(
                        description: SelectableText(
                          appFailureMessage(l, state.failure),
                        ),
                      ),
                    SettingSection(
                      title: l.prototypeRuntimeConfiguration,
                      padding: EdgeInsets.zero,
                      children: [
                        if (controller.runtime == null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              l.xrayNoRuntimeConfiguration,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.mutedForeground),
                            ),
                          )
                        else
                          SettingRow(
                            title: l.prototypeRecentXrayConfiguration,
                            subtitle: l.prototypeReadOnlyRuntimeConfiguration,
                            leading: const Icon(LucideIcons.fileJson, size: 19),
                            decorateLeading: false,
                            showChevron: true,
                            onTap: () =>
                                controller.openConfig(context, onConfig),
                          ),
                      ],
                    ),
                    if (!state.systemExtension && !state.loading)
                      SettingSection(
                        title: l.prototypeLogs,
                        padding: EdgeInsets.zero,
                        children: [
                          SettingRow(
                            title: l.prototypeErrorLog,
                            subtitle: l.prototypeErrorLogHint,
                            leading: const Icon(LucideIcons.terminal, size: 19),
                            decorateLeading: false,
                            showChevron: true,
                            enabled: controller.logPath(false) != null,
                            onTap: () =>
                                controller.openLog(context, false, onLog),
                          ),
                          SettingRow(
                            title: l.prototypeAccessLog,
                            subtitle: l.prototypeAccessLogHint,
                            leading: const Icon(LucideIcons.fileText, size: 19),
                            decorateLeading: false,
                            showChevron: true,
                            enabled: controller.logPath(true) != null,
                            onTap: () =>
                                controller.openLog(context, true, onLog),
                          ),
                        ],
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ShadButton.outline(
                          onPressed: () => context.goPrimaryRoot(
                            AppPrimaryDestination.servers,
                          ),
                          leading: const Icon(LucideIcons.server, size: 17),
                          child: Text(l.prototypeServers),
                        ),
                        ShadButton(
                          onPressed: () => context.goPrimaryRoot(
                            AppPrimaryDestination.connect,
                          ),
                          leading: const Icon(LucideIcons.arrowLeft, size: 17),
                          child: Text(l.prototypeConnect),
                        ),
                      ],
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
