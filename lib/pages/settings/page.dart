import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/settings/controller.dart';
import 'package:onexray/pages/settings/widgets.dart';
import 'package:onexray/pages/settings/app_icon/page.dart';
import 'package:onexray/pages/settings/language/page.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/settings/backup/service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SettingsController(),
    child: BlocBuilder<SettingsController, SettingsPageState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        final controller = context.read<SettingsController>();
        return Scaffold(
          appBar: PageAppBar(title: Text(l10n.prototypeSettings)),
          body: SafeArea(
            child: BlocBuilder<AppEventBus, AppEventBusState>(
              builder: (context, preferences) {
                final mobile =
                    MediaQuery.sizeOf(context).width <=
                    AppLayout.mobileBreakpoint;
                final palette = ColorManager.palette(context);
                final rowHeight = mobile ? 56.0 : 48.0;
                const sectionGap = 20.0;
                const rowPadding = EdgeInsets.all(12);
                final appearance = SettingSection(
                  title: l10n.settingsAppearanceAndLanguage,
                  icon: LucideIcons.sun,
                  padding: EdgeInsets.zero,
                  dividerIndent: 0,
                  children: [
                    _ThemeOptions(
                      selected: preferences.themeCode,
                      onSelected: (theme) =>
                          controller.setTheme(context, theme),
                    ),
                    const SizedBox(height: 12),
                    SettingRow(
                      title: l10n.prototypeLanguage,
                      value: languageNativeLabel(
                        l10n,
                        preferences.languageCode,
                      ),
                      minHeight: rowHeight,
                      contentPadding: rowPadding,
                      showChevron: true,
                      onTap: () => controller.openSetting(
                        context,
                        AppPageDestination.language,
                      ),
                    ),
                    if (controller.showAppIcon)
                      SettingRow(
                        title: l10n.prototypeAppIcon,
                        subtitle: appIconLabel(l10n, state.appIcon),
                        minHeight: rowHeight,
                        contentPadding: rowPadding,
                        showChevron: true,
                        onTap: () => controller.openSetting(
                          context,
                          AppPageDestination.appIcon,
                        ),
                      ),
                  ],
                );
                final startup = SettingSection(
                  title: l10n.settingsStartupAndSystem,
                  icon: LucideIcons.power,
                  padding: EdgeInsets.zero,
                  dividerIndent: 0,
                  children: [
                    SettingRow(
                      title: l10n.prototypeStartup,
                      subtitle: state.connectOnLaunch
                          ? l10n.prototypeConnectAfterAppLaunch
                          : l10n.settingsManualConnection,
                      showChevron: true,
                      onTap: () => controller.openSetting(
                        context,
                        AppPageDestination.desktopSettings,
                      ),
                    ),
                    if (AppPlatform.isAndroid)
                      SettingRow(
                        title: l10n.trafficWidgetAdd,
                        trailing: state.addingWidget
                            ? const ButtonProgressIndicator(size: 20)
                            : null,
                        showChevron: true,
                        onTap: state.addingWidget
                            ? null
                            : () => controller.addTrafficWidget(context),
                      ),
                  ],
                );
                final data = SettingSection(
                  title: l10n.prototypeData,
                  icon: LucideIcons.database,
                  padding: EdgeInsets.zero,
                  dividerIndent: 0,
                  children: [
                    if (BackupService.supported)
                      SettingsBackupSummaryRow(
                        minHeight: rowHeight,
                        contentPadding: rowPadding,
                        onTap: () => controller.openSetting(
                          context,
                          AppPageDestination.backup,
                        ),
                      ),
                    SettingRow(
                      title: l10n.clearConnectionResources,
                      enabled: !state.clearingData,
                      trailing:
                          state.clearingData &&
                              state.cleanupScope == 'resources'
                          ? const ButtonProgressIndicator(size: 20)
                          : null,
                      minHeight: rowHeight,
                      contentPadding: rowPadding,
                      titleStyle: AppTypography.rowTitle,
                      onTap: state.clearingData
                          ? null
                          : () => controller.clearData(
                              context,
                              resourcesOnly: true,
                            ),
                    ),
                    SettingRow(
                      title: l10n.clearAllAppData,
                      enabled: !state.clearingData,
                      minHeight: rowHeight,
                      contentPadding: rowPadding,
                      titleStyle: AppTypography.rowTitle,
                      trailing:
                          state.clearingData &&
                              state.cleanupScope != 'resources'
                          ? const ButtonProgressIndicator(size: 20)
                          : null,
                      onTap: state.clearingData
                          ? null
                          : () => controller.clearData(context),
                    ),
                  ],
                );
                final about = SettingSection(
                  title: l10n.prototypeAbout,
                  padding: EdgeInsets.zero,
                  dividerIndent: 0,
                  children: [
                    Semantics(
                      label: preferences.appUpdateInfo == null
                          ? null
                          : l10n.prototypeAboutUpdateAvailable,
                      child: SettingRow(
                        minHeight: rowHeight,
                        contentPadding: rowPadding,
                        title: l10n.prototypeAboutOneXray,
                        titleStyle: AppTypography.rowTitle,
                        titleTrailing: preferences.appUpdateInfo == null
                            ? null
                            : const SettingsUpdateDot(),
                        showChevron: true,
                        onTap: () => controller.openSetting(
                          context,
                          AppPageDestination.aboutOneXray,
                        ),
                      ),
                    ),
                  ],
                );
                return SettingsPageScroll(
                  desktopMaxWidth: AppLayout.settingsMaxWidth,
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      mobile ? AppSpacing.mobilePage : AppSpacing.page,
                      20,
                      mobile ? AppSpacing.mobilePage : AppSpacing.page,
                      36,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.failure case final failure?)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: SelectableText(
                                appFailureMessage(l10n, failure),
                                style: AppTypography.supporting.copyWith(
                                  color: palette.destructive,
                                ),
                              ),
                            ),
                          ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            appearance,
                            SizedBox(height: sectionGap),
                            startup,
                            SizedBox(height: sectionGap),
                            data,
                            SizedBox(height: sectionGap),
                            about,
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    ),
  );
}

/// Observes the existing device-local binding; opening Settings does not load it.
class SettingsBackupSummaryRow extends StatelessWidget {
  const SettingsBackupSummaryRow({
    super.key,
    required this.onTap,
    this.service,
    this.minHeight,
    this.contentPadding = const EdgeInsets.all(12),
  });

  final VoidCallback onTap;
  final BackupService? service;
  final double? minHeight;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) => BlocBuilder<BackupService, BackupState>(
    bloc: service ?? BackupService(),
    builder: (context, backup) {
      final l = AppLocalizations.of(context)!;
      return SettingRow(
        title: l.backupTitle,
        subtitle: backup.settings.target?.label ?? l.backupNotConfigured,
        minHeight: minHeight,
        contentPadding: contentPadding,
        titleStyle: AppTypography.rowTitle,
        showChevron: true,
        onTap: onTap,
      );
    },
  );
}

class _ThemeOptions extends StatelessWidget {
  final ThemeCode selected;
  final ValueChanged<ThemeCode> onSelected;

  const _ThemeOptions({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) =>
      SettingsThemeOptions(selected: selected, onSelected: onSelected);
}
