import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tab_visibility.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/advanced/xray/controller.dart';
import 'package:onexray/pages/advanced/xray/config/params.dart';
import 'package:onexray/pages/advanced/xray/log/params.dart';
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
    required this.onLog,
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
  final void Function(BuildContext, LogFileViewerParams) onLog;
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
        return AdvancedTabVisibility(
          tabIndex: 1,
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
                            children: [
                              _runtimeCard(context, controller, l),
                              if (onDiagnostics != null)
                                _pushRow(
                                  context,
                                  mobile: mobile,
                                  title: l.xrayDiagnostics,
                                  subtitle: state.connection.failed
                                      ? l.prototypeConnectionFailed
                                      : l.xrayDiagnosticsHint,
                                  icon: LucideIcons.stethoscope,
                                  enabled: true,
                                  onTap: () => onDiagnostics!(context),
                                ),
                            ],
                          ),
                          _section(
                            icon: LucideIcons.settings,
                            title: l.prototypeSettings,
                            children: [
                              _pushRow(
                                context,
                                mobile: mobile,
                                title: l.prototypeRoutingData,
                                icon: LucideIcons.hardDrive,
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
                                icon: LucideIcons.refreshCw,
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
                                icon: LucideIcons.zap,
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
                                  icon: LucideIcons.network,
                                  enabled: !disabled,
                                  onTap: () => onServerDialing!(context),
                                ),
                            ],
                          ),
                          if (!state.systemExtension)
                            _section(
                              icon: LucideIcons.fileText,
                              title: l.prototypeLogs,
                              children: [
                                _pushRow(
                                  context,
                                  mobile: mobile,
                                  title: l.prototypeLogs,
                                  icon: LucideIcons.fileText,
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
                              ],
                            ),
                          _section(
                            icon: LucideIcons.slidersHorizontal,
                            title: l.lanProxyConfiguration,
                            description:
                                '${l.lanProxySecurityHint} ${l.lanProxyNextStartNotice}',
                            action: PageHelpButton(
                              title: l.lanProxyTitle,
                              messages: [
                                l.lanProxyProtocolHint,
                                l.lanProxyRawJsonNotice,
                              ],
                            ),
                            children: [
                              SettingRow(
                                title: l.lanProxyTitle,
                                titleMaxLines: 4,
                                titleStyle: AppTypography.rowTitle,
                                minHeight: 64,
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
                            ],
                          ),
                          _section(
                            icon: LucideIcons.fileJson,
                            title: l.prototypeRuntimeConfiguration,
                            children: [
                              _pushRow(
                                context,
                                mobile: mobile,
                                title: l.prototypeRecentXrayConfiguration,
                                subtitle:
                                    l.prototypeReadOnlyRuntimeConfiguration,
                                icon: LucideIcons.fileJson,
                                enabled: controller.runtime != null,
                                onTap: () =>
                                    controller.openConfig(context, onConfig),
                              ),
                            ],
                          ),
                          if (AppPlatform.isDesktop && onLocalApi != null)
                            _section(
                              icon: LucideIcons.terminal,
                              title: l.localApiTitle,
                              children: [
                                _pushRow(
                                  context,
                                  mobile: mobile,
                                  title: l.localApiTitle,
                                  subtitle: l.localApiSummary,
                                  icon: LucideIcons.terminal,
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
    required IconData icon,
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
    return Column(
      children: [
        PolicyValueRow(
          title: l.prototypeXrayCore,
          value: controller.connected
              ? l.prototypeRunningNormally
              : controller.statusLabel(l),
          valueTextDirection: null,
          valueStyle: AppTypography.rowTitle.copyWith(
            color: controller.connected
                ? palette.runningText
                : palette.foreground,
          ),
        ),
        PolicyValueRow(
          title: l.prototypeVersion,
          value: controller.xrayVersion,
        ),
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
    required IconData icon,
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
    leading: Icon(
      icon,
      size: 20,
      color: ColorManager.palette(context).mutedForeground,
    ),
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
