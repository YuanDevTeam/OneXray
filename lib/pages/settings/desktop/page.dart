import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/desktop_startup/model.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/controller.dart';
import 'package:onexray/pages/settings/desktop/controller.dart';
import 'package:onexray/pages/settings/widgets.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DesktopSettingsPage extends StatelessWidget {
  const DesktopSettingsPage({super.key, this.showDesktopOptions});

  final bool? showDesktopOptions;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SettingsController(),
    child: BlocBuilder<SettingsController, SettingsPageState>(
      builder: (context, settings) {
        final l = AppLocalizations.of(context)!;
        final connect = _StartupToggle(
          title: l.prototypeConnectAfterAppLaunch,
          value: settings.connectOnLaunch,
          onChanged: settings.loading || settings.saving
              ? null
              : (value) => context
                    .read<SettingsController>()
                    .setConnectOnLaunch(context, value),
        );
        if (!(showDesktopOptions ?? AppPlatform.isDesktop)) {
          return SettingsPageScaffold(
            title: l.prototypeStartup,
            body: SettingsPageScroll(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: settingsContentPadding(context),
                child: SettingSection(
                  title: l.desktopSettingsPageSectionStartup,
                  padding: EdgeInsets.zero,
                  children: [connect],
                ),
              ),
            ),
          );
        }
        return BlocProvider(
          create: (_) => DesktopSettingsController(),
          child:
              BlocBuilder<DesktopSettingsController, DesktopSettingsPageState>(
                builder: (context, state) {
                  final controller = context.read<DesktopSettingsController>();
                  return SettingsPageScaffold(
                    title: l.prototypeStartup,
                    body: DesktopSettingsView(
                      state: state,
                      connectOnLaunch: connect,
                      showMacOSOptions: AppPlatform.isMacOS,
                      onLaunchAtLoginChanged: (value) =>
                          controller.updateLaunchAtLogin(context, value),
                      onStartHiddenChanged: (value) =>
                          controller.updateStartHidden(value, context: context),
                      onHideDockIconChanged: (value) => controller
                          .updateHideDockIcon(value, context: context),
                      onOpenSystemSettings: () =>
                          controller.openSystemSettings(context),
                    ),
                  );
                },
              ),
        );
      },
    ),
  );
}

class DesktopSettingsView extends StatelessWidget {
  final DesktopSettingsPageState state;
  final bool showMacOSOptions;
  final Widget? connectOnLaunch;
  final ValueChanged<bool> onLaunchAtLoginChanged;
  final ValueChanged<bool> onStartHiddenChanged;
  final ValueChanged<bool> onHideDockIconChanged;
  final VoidCallback onOpenSystemSettings;

  const DesktopSettingsView({
    super.key,
    required this.state,
    required this.showMacOSOptions,
    this.connectOnLaunch,
    required this.onLaunchAtLoginChanged,
    required this.onStartHiddenChanged,
    required this.onHideDockIconChanged,
    required this.onOpenSystemSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final launchStatus = state.launchAtLogin;
    return SettingsPageScroll(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: settingsContentPadding(context),
        child: SettingSection(
          title: l.desktopSettingsPageSectionStartup,
          padding: EdgeInsets.zero,
          children: [
            ?connectOnLaunch,
            _StartupToggle(
              title: l.settingsPageLaunchAtLogin,
              subtitle: launchStatus.state == LaunchAtLoginState.unavailable
                  ? l.settingsPageLaunchAtLoginUnavailable
                  : null,
              value: launchStatus.enabled,
              onChanged: state.launchToggleEnabled && !state.requiresApproval
                  ? onLaunchAtLoginChanged
                  : null,
            ),
            if (state.requiresApproval) ...[
              SettingRow(
                title: l.settingsPageLaunchAtLoginRequiresApproval,
                subtitle: l.settingsPageLaunchAtLoginApprovalDescription,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ShadButton.outline(
                    enabled: !state.changingLaunchAtLogin,
                    onPressed: state.changingLaunchAtLogin
                        ? null
                        : () => onLaunchAtLoginChanged(false),
                    child: ButtonProgress(
                      busy: state.changingLaunchAtLogin,
                      child: Text(l.prototypeCancelRequest),
                    ),
                  ),
                  ShadButton.outline(
                    enabled: !state.openingSystemSettings,
                    onPressed: state.openingSystemSettings
                        ? null
                        : onOpenSystemSettings,
                    child: ButtonProgress(
                      busy: state.openingSystemSettings,
                      child: Text(l.prototypeOpenSystemSettings),
                    ),
                  ),
                ],
              ),
            ],
            _StartupToggle(
              title: l.settingsPageStartHidden,
              value: state.startHidden,
              onChanged: state.behaviorSettingsEnabled
                  ? onStartHiddenChanged
                  : null,
            ),
            if (showMacOSOptions)
              _StartupToggle(
                title: l.desktopSettingsPageHideDockIcon,
                value: state.hideDockIcon,
                onChanged: state.behaviorSettingsEnabled
                    ? onHideDockIconChanged
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _StartupToggle extends StatelessWidget {
  const _StartupToggle({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
    title: title,
    subtitle: subtitle,
    enabled: onChanged != null,
    contentPadding: const EdgeInsets.symmetric(vertical: 10),
    leading: AppSwitch(
      value: value,
      enabled: onChanged != null,
      onChanged: onChanged,
    ),
    onTap: onChanged == null ? null : () => onChanged!(!value),
  );
}
