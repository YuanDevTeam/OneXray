import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/page_visibility.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/advanced/xray/controller.dart';
import 'package:onexray/pages/advanced/xray/config/params.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// The Xray destination groups runtime facts and independent tool pages.
class XrayRuntimePage extends StatelessWidget {
  const XrayRuntimePage({
    super.key,
    required this.onGeodata,
    required this.onUpdates,
    required this.onSpeedTest,
    required this.onConfig,
    this.onDiagnostics,
    this.onLogSettings,
    this.onLocalApi,
    this.onLanProxy,
    this.onServerDialing,
    this.createController,
  });
  final void Function(BuildContext) onGeodata;
  final void Function(BuildContext) onUpdates;
  final void Function(BuildContext) onSpeedTest;
  final void Function(BuildContext, ConfigFileViewerParams) onConfig;
  final void Function(BuildContext)? onDiagnostics;
  final Future<bool?> Function(BuildContext)? onLogSettings;
  final void Function(BuildContext)? onLocalApi;
  final Future<void> Function(BuildContext)? onLanProxy;
  final void Function(BuildContext)? onServerDialing;
  final XrayRuntimeController Function()? createController;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => createController?.call() ?? XrayRuntimeController(),
    child: BlocBuilder<XrayRuntimeController, XrayRuntimePageState>(
      builder: (context, state) {
        final controller = context.read<XrayRuntimeController>();
        final l = AppLocalizations.of(context)!;
        final disabled = controller.busy;
        final width = MediaQuery.sizeOf(context).width;
        final mobile = width <= AppLayout.mobileBreakpoint;
        final gutter = mobile
            ? AppSpacing.mobilePage
            : AppSpacing.advancedDesktopGutter(width);
        return PageVisibility(
          onChanged: controller.reader.setVisible,
          child: Scaffold(
            body: controller.loading
                ? const Center(child: CircularProgressIndicator())
                : controller.base == null
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
                      padding: EdgeInsetsDirectional.fromSTEB(
                        gutter,
                        20,
                        gutter,
                        mobile ? 24 : 28,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 20,
                        children: [
                          _section(
                            icon: LucideIcons.activity,
                            title: l.prototypeRuntimeStatus,
                            children: [_runtimeCard(context, controller, l)],
                          ),
                          _section(
                            title: l.xrayChecksAndDiagnostics,
                            children: [
                              if (onDiagnostics != null)
                                _pushRow(
                                  context,
                                  mobile: mobile,
                                  title: l.xrayDiagnostics,
                                  subtitle: state.connection.failed
                                      ? l.prototypeConnectionFailed
                                      : l.xrayDiagnosticsHint,
                                  enabled: true,
                                  onTap: () => onDiagnostics!(context),
                                ),
                              if (!state.systemExtension)
                                _pushRow(
                                  context,
                                  mobile: mobile,
                                  title: l.prototypeLogs,
                                  subtitle: controller.logsEnabled
                                      ? l.xrayLogsEnabled
                                      : l.xrayLogsDisabled,
                                  enabled: !disabled && onLogSettings != null,
                                  onTap: () async {
                                    final saved = await onLogSettings?.call(
                                      context,
                                    );
                                    if (saved == true &&
                                        controller.isPageActive) {
                                      await controller.load(showLoading: false);
                                    }
                                  },
                                ),
                              _pushRow(
                                context,
                                mobile: mobile,
                                title: l.prototypeRecentXrayConfiguration,
                                subtitle: controller.runtime == null
                                    ? l.xrayNoRuntimeConfiguration
                                    : l.prototypeReadOnlyRuntimeConfiguration,
                                enabled: controller.runtime != null,
                                onTap: () =>
                                    controller.openConfig(context, onConfig),
                              ),
                            ],
                          ),
                          _section(
                            title: l.xrayConnectionResources,
                            children: [
                              _pushRow(
                                context,
                                mobile: mobile,
                                title: l.prototypeRoutingData,
                                trailing: AppActivityBuilder(
                                  builder: (context, activity) =>
                                      activity.downloading
                                      ? const ButtonProgressIndicator()
                                      : _chevron(context),
                                ),
                                enabled: true,
                                onTap: () => onGeodata(context),
                              ),
                              _pushRow(
                                context,
                                mobile: mobile,
                                title: l.prototypeDataUpdates,
                                trailing: AppActivityBuilder(
                                  builder: (context, activity) =>
                                      activity.downloading
                                      ? const ButtonProgressIndicator()
                                      : _chevron(context),
                                ),
                                enabled: true,
                                onTap: () => onUpdates(context),
                              ),
                              _pushRow(
                                context,
                                mobile: mobile,
                                title: l.prototypeSpeedTest,
                                subtitle: controller.speedSummary(l),
                                trailing: AppActivityBuilder(
                                  builder: (context, activity) =>
                                      activity.pinging
                                      ? const ButtonProgressIndicator()
                                      : _chevron(context),
                                ),
                                enabled: true,
                                onTap: () => onSpeedTest(context),
                              ),
                              if (onServerDialing != null)
                                _pushRow(
                                  context,
                                  mobile: mobile,
                                  title: l.serverDialingTitle,
                                  enabled: !disabled,
                                  onTap: () => onServerDialing!(context),
                                ),
                            ],
                          ),
                          _section(
                            title: l.xraySharingInterfaces,
                            action: PageHelpButton(
                              title: l.lanProxyTitle,
                              messages: [
                                l.lanProxySecurityHint,
                                l.lanProxyNextStartNotice,
                                l.lanProxyProtocolHint,
                                l.lanProxyRawJsonNotice,
                              ],
                            ),
                            children: [
                              SettingRow(
                                title: l.lanProxyTitle,
                                titleMaxLines: 4,
                                titleStyle: AppTypography.rowTitle,
                                contentPadding: const EdgeInsets.all(12),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (state.lanProxySaving)
                                      const ButtonProgressIndicator()
                                    else
                                      AppSwitch(
                                        key: const ValueKey('lan-proxy-switch'),
                                        value: controller.lanProxyEnabled,
                                        enabled:
                                            !disabled &&
                                            !controller.runtimeBusy,
                                        onChanged: (value) => controller
                                            .setLanProxyEnabled(context, value),
                                      ),
                                    if (onLanProxy != null) ...[
                                      const SizedBox(width: 8),
                                      _chevron(context),
                                    ],
                                  ],
                                ),
                                onTap: onLanProxy == null || disabled
                                    ? null
                                    : () async {
                                        await onLanProxy!(context);
                                        if (controller.isPageActive) {
                                          await controller.refreshLanProxy();
                                        }
                                      },
                              ),
                              if (AppPlatform.isDesktop && onLocalApi != null)
                                _pushRow(
                                  context,
                                  mobile: mobile,
                                  title: l.localApiTitle,
                                  subtitle: l.localApiSummary,
                                  enabled: true,
                                  onTap: () => onLocalApi!(context),
                                ),
                            ],
                          ),
                          if (controller.failed)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                appFailureMessage(l, state.failure),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
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

  Widget _section({
    IconData? icon,
    required String title,
    String? description,
    Widget? action,
    required List<Widget> children,
  }) => SettingSection(
    icon: icon,
    title: title,
    description: description,
    action: action,
    descriptionBelow: true,
    padding: EdgeInsets.zero,
    dividerIndent: 0,
    children: children,
  );

  Widget _runtimeCard(
    BuildContext context,
    XrayRuntimeController controller,
    AppLocalizations l,
  ) {
    final palette = ColorManager.palette(context);
    final runtime = controller.connected || controller.runtimeBusy
        ? controller.state.connection.runtime
        : null;
    final entries =
        runtime?.entries.map((entry) => entry.name).join(' + ') ?? '';
    final identity = runtime == null
        ? (controller.connected || controller.runtimeBusy
              ? '—'
              : l.xrayNotRunning)
        : runtime.profile?.name ??
              runtime.rawName ??
              (entries.isEmpty
                  ? l.prototypeCompleteXrayConfiguration
                  : '$entries${runtime.finalExit == null ? '' : ' → ${runtime.finalExit!.name}'}');
    final statusColor = controller.connected
        ? palette.runningText
        : controller.state.connection.failed
        ? palette.destructive
        : controller.runtimeBusy
        ? palette.restartingText
        : palette.foreground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingRow(
          key: const ValueKey('xray-core-runtime'),
          title: 'Xray-core',
          subtitle: controller.xrayVersion,
          subtitleStyle: AppTypography.supporting,
          trailing: ShadBadge.secondary(
            backgroundColor: controller.connected
                ? palette.runningSurface
                : controller.state.connection.failed
                ? palette.destructiveSurface
                : palette.muted,
            foregroundColor: statusColor,
            child: Text(
              controller.statusLabel(l),
              style: AppTypography.badge.copyWith(color: statusColor),
            ),
          ),
        ),
        SettingRow(
          key: const ValueKey('xray-current-connection'),
          title: l.xrayCurrentConnection,
          subtitle: identity,
          subtitleStyle: AppTypography.supporting,
        ),
        if (controller.connected &&
            controller.uptime.isNotEmpty &&
            controller.uptime != '—')
          PolicyValueRow(title: l.prototypeUptime, value: controller.uptime),
      ],
    );
  }

  Widget _pushRow(
    BuildContext context, {
    required bool mobile,
    required String title,
    String? subtitle,
    Widget? trailing,
    required bool enabled,
    required VoidCallback onTap,
  }) => SettingRow(
    title: title,
    subtitle: subtitle,
    titleStyle: AppTypography.rowTitle,
    subtitleStyle: AppTypography.supporting,
    contentPadding: const EdgeInsets.all(12),
    minHeight: mobile ? 56 : 48,
    decorateLeading: false,
    trailing: trailing ?? _chevron(context),
    enabled: enabled,
    onTap: onTap,
  );

  Widget _chevron(BuildContext context) => Icon(
    LucideIcons.chevronRightDir,
    size: 18,
    color: ColorManager.palette(context).mutedStrong,
  );
}
