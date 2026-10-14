import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tab_visibility.dart';
import 'package:onexray/pages/advanced/xray/controller.dart';
import 'package:onexray/pages/advanced/xray/config/params.dart';
import 'package:onexray/pages/advanced/xray/log/params.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Embedded in the root Advanced tab. Child details use the root router.
class XrayRuntimePage extends StatelessWidget {
  const XrayRuntimePage({
    super.key,
    required this.onGeodata,
    required this.onUpdates,
    required this.onSpeedTest,
    required this.onLog,
    required this.onConfig,
    this.onLocalApi,
    this.onLanProxy,
    this.createController,
  });
  final void Function(BuildContext) onGeodata;
  final void Function(BuildContext) onUpdates;
  final void Function(BuildContext) onSpeedTest;
  final void Function(BuildContext, LogFileViewerParams) onLog;
  final void Function(BuildContext, ConfigFileViewerParams) onConfig;
  final void Function(BuildContext)? onLocalApi;
  final Future<void> Function(BuildContext)? onLanProxy;
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
        final gutter = mobile ? 15.0 : AppSpacing.advancedDesktopGutter(width);
        return AdvancedTabVisibility(
          tabIndex: 1,
          onChanged: controller.reader.setVisible,
          child: Scaffold(
            bottomNavigationBar:
                controller.base == null || state.systemExtension
                ? null
                : PageActionBar(
                    maxWidth: AppLayout.advancedMaxWidth,
                    expandDesktop: true,
                    horizontalPadding: gutter,
                    spacing: 13,
                    children: [
                      OutlinedButton.icon(
                        onPressed: disabled
                            ? null
                            : () {
                                controller.restoreDefaults();
                                ContextAlert.showToast(
                                  context,
                                  l.settingsDefaultsRestored,
                                );
                              },
                        icon: const Icon(LucideIcons.rotateCcw, size: 16),
                        label: Text(l.prototypeRestoreDefaults),
                      ),
                      FilledButton(
                        onPressed: disabled || controller.runtimeBusy
                            ? null
                            : () => controller.save(context),
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
                  ),
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
                        mobile ? 22 : 54,
                        gutter,
                        mobile ? 24 : 28,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: mobile ? 25 : 28,
                        children: [
                          _section(
                            icon: LucideIcons.activity,
                            title: l.prototypeRuntimeStatus,
                            children: [
                              _runtimeCard(context, controller, l, mobile),
                            ],
                          ),
                          _section(
                            icon: LucideIcons.hardDrive,
                            title: l.prototypeRoutingData,
                            children: [
                              SettingRow(
                                title: l.prototypeRoutingDataSummary,
                                minHeight: mobile ? 43 : 56,
                                titleStyle: AppTypography.settingsRow,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: mobile ? 13 : 14,
                                ),
                                trailing: AppActivityBuilder(
                                  builder: (context, activity) =>
                                      activity.downloading
                                      ? const ButtonProgressIndicator()
                                      : _chevron(context),
                                ),
                                onTap: () => onGeodata(context),
                              ),
                            ],
                          ),
                          _section(
                            icon: LucideIcons.refreshCw,
                            title: l.prototypeDataUpdates,
                            children: [
                              SettingRow(
                                title: l.prototypeDataUpdateIntervals,
                                minHeight: mobile ? 43 : 56,
                                titleStyle: AppTypography.settingsRow,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: mobile ? 13 : 14,
                                ),
                                trailing: AppActivityBuilder(
                                  builder: (context, activity) =>
                                      activity.downloading
                                      ? const ButtonProgressIndicator()
                                      : _chevron(context),
                                ),
                                onTap: () => onUpdates(context),
                              ),
                            ],
                          ),
                          _section(
                            icon: LucideIcons.zap,
                            title: l.prototypeSpeedTest,
                            children: [
                              SettingRow(
                                title: l.prototypeSpeedTestSummary,
                                minHeight: 64,
                                titleStyle: AppTypography.settingsRow,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: mobile ? 13 : 14,
                                  vertical: 12,
                                ),
                                subtitleWidget: Text(
                                  controller.speedSummary(l),
                                  style: AppTypography.runtimeNavigationHint
                                      .copyWith(
                                        color: ColorManager.secondaryText(
                                          context,
                                        ),
                                      ),
                                ),
                                trailing: AppActivityBuilder(
                                  builder: (context, activity) =>
                                      activity.pinging
                                      ? const ButtonProgressIndicator()
                                      : _chevron(context),
                                ),
                                onTap: () => onSpeedTest(context),
                              ),
                            ],
                          ),
                          if (!state.systemExtension)
                            _section(
                              icon: LucideIcons.fileText,
                              title: l.prototypeLogs,
                              action: PageHelpButton(
                                title: l.prototypeLogs,
                                messages: [l.prototypeManagedLogNotice],
                              ),
                              children: [
                                _logToggle(
                                  controller: controller,
                                  title: l.prototypeRecordXrayLogs,
                                  field: 'enabled',
                                  value: controller.logsEnabled,
                                  mobile: mobile,
                                ),
                                if (controller.logsEnabled) ...[
                                  SettingRow(
                                    title: l.prototypeErrorLogLevel,
                                    titleStyle: mobile
                                        ? AppTypography.settingsFieldTitle
                                        : AppTypography.settingsRow,
                                    minHeight: mobile ? 52 : 56,
                                    trailing: SizedBox(
                                      width: mobile
                                          ? (MediaQuery.sizeOf(context).width *
                                                    .48)
                                                .clamp(0.0, 190.0)
                                                .toDouble()
                                          : 190,
                                      child: SettingSelect<String>(
                                        value: controller.level,
                                        minHeight: mobile ? 36 : 38,
                                        textStyle: mobile
                                            ? AppTypography.runtimeSelector
                                            : AppTypography
                                                  .runtimeDesktopSelector,
                                        entries: {
                                          'error': l.prototypeErrorsOnly,
                                          'warning': l.prototypeWarning,
                                          'info': 'Info',
                                          'debug': 'Debug',
                                        },
                                        onChanged: disabled
                                            ? null
                                            : controller.setLevel,
                                      ),
                                    ),
                                  ),
                                  _logToggle(
                                    controller: controller,
                                    title: l.prototypeRecordDnsQueries,
                                    field: 'recordDns',
                                    value: controller.recordDns,
                                    mobile: mobile,
                                  ),
                                  _logToggle(
                                    controller: controller,
                                    title: l.prototypeHideLogIpAddresses,
                                    field: 'maskIp',
                                    value: controller.maskIp,
                                    mobile: mobile,
                                  ),
                                ],
                                _pushRow(
                                  context,
                                  mobile: mobile,
                                  title: l.prototypeAccessLog,
                                  icon: LucideIcons.fileText,
                                  enabled: controller.logPath(true) != null,
                                  onTap: () =>
                                      controller.openLog(context, true, onLog),
                                ),
                                _pushRow(
                                  context,
                                  mobile: mobile,
                                  title: l.prototypeErrorLog,
                                  icon: LucideIcons.terminal,
                                  enabled: controller.logPath(false) != null,
                                  onTap: () =>
                                      controller.openLog(context, false, onLog),
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
                                titleStyle: AppTypography.settingsRow,
                                minHeight: 64,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: mobile ? 13 : 14,
                                  vertical: 12,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (state.lanProxySaving)
                                      const ButtonProgressIndicator()
                                    else
                                      ShadSwitch(
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
    bool mobile,
  ) {
    Widget metric(
      String label,
      String value, {
      bool first = false,
      bool last = false,
    }) {
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Text(
            label,
            style:
                (mobile
                        ? AppTypography.runtimeLabel
                        : AppTypography.runtimeDesktopLabel)
                    .copyWith(color: ColorManager.secondaryText(context)),
          ),
          Text(
            value,
            style:
                (mobile
                        ? AppTypography.runtimeValue
                        : AppTypography.runtimeDesktopValue)
                    .copyWith(color: ColorManager.primaryText(context)),
            maxLines: first ? null : 1,
            overflow: first ? null : TextOverflow.ellipsis,
            textDirection: first ? null : TextDirection.ltr,
          ),
        ],
      );
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: mobile ? 10 : 18,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          border: last
              ? null
              : BorderDirectional(
                  end: BorderSide(color: ColorManager.border(context)),
                ),
        ),
        child: first
            ? Row(
                children: [
                  Icon(
                    LucideIcons.activity,
                    size: 20,
                    color: ColorManager.palette(context).primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(child: text),
                ],
              )
            : text,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: mobile ? 70 : 76),
      child: Row(
        children: [
          Expanded(
            flex: mobile ? 125 : 145,
            child: metric(
              l.prototypeXrayCore,
              controller.connected
                  ? l.prototypeRunningNormally
                  : controller.statusLabel(l),
              first: true,
            ),
          ),
          Expanded(
            flex: mobile ? 72 : 80,
            child: metric(l.prototypeVersion, controller.xrayVersion),
          ),
          Expanded(
            flex: mobile ? 85 : 90,
            child: metric(l.prototypeUptime, controller.uptime, last: true),
          ),
        ],
      ),
    );
  }

  Widget _logToggle({
    required XrayRuntimeController controller,
    required String title,
    required String field,
    required bool value,
    required bool mobile,
  }) => SettingRow(
    title: title,
    titleMaxLines: 4,
    titleStyle: mobile
        ? AppTypography.settingsFieldTitle
        : AppTypography.settingsRow,
    minHeight: mobile ? 52 : 56,
    trailing: ShadSwitch(
      value: value,
      enabled: !controller.busy,
      onChanged: controller.busy
          ? null
          : (value) => controller.setLog(field, value),
    ),
  );

  Widget _pushRow(
    BuildContext context, {
    required bool mobile,
    required String title,
    String? subtitle,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) => SettingRow(
    title: title,
    subtitle: subtitle,
    titleStyle: mobile
        ? AppTypography.settingsFieldTitle
        : AppTypography.settingsRow,
    subtitleStyle: mobile
        ? AppTypography.runtimePushHint
        : AppTypography.runtimeDesktopPushHint,
    contentPadding: EdgeInsets.symmetric(
      horizontal: mobile ? 10 : 16,
      vertical: 10,
    ),
    minHeight: 64,
    decorateLeading: false,
    leading: Icon(icon, size: 19, color: ColorManager.palette(context).primary),
    trailing: _chevron(context),
    enabled: enabled,
    onTap: onTap,
  );

  Widget _chevron(BuildContext context) => Icon(
    LucideIcons.chevronRightDir,
    size: 18,
    color: ColorManager.palette(context).mutedStrong,
  );
}
