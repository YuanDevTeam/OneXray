import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/desktop_startup/model.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/desktop/controller.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DesktopSettingsPage extends StatelessWidget {
  const DesktopSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DesktopSettingsController(),
      child: BlocBuilder<DesktopSettingsController, DesktopSettingsPageState>(
        builder: (context, state) {
          final controller = context.read<DesktopSettingsController>();
          return SettingsPageScaffold(
            title: AppLocalizations.of(context)!.settingsPageDesktop,
            body: DesktopSettingsView(
              state: state,
              showMacOSOptions: AppPlatform.isMacOS,
              onLaunchAtLoginChanged: (value) =>
                  controller.updateLaunchAtLogin(context, value),
              onStartHiddenChanged: controller.updateStartHidden,
              onHideDockIconChanged: controller.updateHideDockIcon,
              onOpenSystemSettings: () =>
                  controller.openSystemSettings(context),
            ),
          );
        },
      ),
    );
  }
}

class DesktopSettingsView extends StatelessWidget {
  final DesktopSettingsPageState state;
  final bool showMacOSOptions;
  final ValueChanged<bool> onLaunchAtLoginChanged;
  final ValueChanged<bool> onStartHiddenChanged;
  final ValueChanged<bool> onHideDockIconChanged;
  final VoidCallback onOpenSystemSettings;

  const DesktopSettingsView({
    super.key,
    required this.state,
    required this.showMacOSOptions,
    required this.onLaunchAtLoginChanged,
    required this.onStartHiddenChanged,
    required this.onHideDockIconChanged,
    required this.onOpenSystemSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final launchStatus = state.launchAtLogin;

    return SettingsPageScroll(
      desktopMaxWidth: 720,
      child: Column(
        children: [
          SettingSection(
            title: l10n.desktopSettingsPageSectionStartup,
            children: [
              SwitchSettingRow(
                title: l10n.settingsPageLaunchAtLogin,
                subtitle: launchStatus.state == LaunchAtLoginState.unavailable
                    ? l10n.settingsPageLaunchAtLoginUnavailable
                    : null,
                leading: const Icon(LucideIcons.logIn),
                value: launchStatus.enabled,
                onChanged: state.launchToggleEnabled
                    ? onLaunchAtLoginChanged
                    : null,
              ),
              if (state.requiresApproval)
                SettingRow(
                  title: l10n.settingsPageLaunchAtLoginRequiresApproval,
                  subtitle: l10n.settingsPageLaunchAtLoginApprovalDescription,
                  leading: const Icon(LucideIcons.settings2),
                  trailing: state.openingSystemSettings
                      ? const ButtonProgressIndicator()
                      : const Icon(LucideIcons.externalLink),
                  onTap: state.openingSystemSettings
                      ? null
                      : onOpenSystemSettings,
                ),
              SwitchSettingRow(
                title: l10n.settingsPageStartHidden,
                leading: const Icon(LucideIcons.eyeOff),
                value: state.startHidden,
                onChanged: state.behaviorSettingsEnabled
                    ? onStartHiddenChanged
                    : null,
              ),
            ],
          ),
          if (showMacOSOptions)
            SettingSection(
              title: "macOS",
              children: [
                SwitchSettingRow(
                  title: l10n.desktopSettingsPageHideDockIcon,
                  leading: const Icon(LucideIcons.monitorCog),
                  value: state.hideDockIcon,
                  onChanged: state.behaviorSettingsEnabled
                      ? onHideDockIconChanged
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
