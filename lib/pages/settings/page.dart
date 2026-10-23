import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/settings/controller.dart';
import 'package:onexray/pages/settings/widgets.dart';
import 'package:onexray/pages/settings/app_icon/page.dart';
import 'package:onexray/pages/settings/desktop/controller.dart';
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
import 'package:shadcn_ui/shadcn_ui.dart';

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
                final rowHeight = mobile ? 43.0 : 56.0;
                final sectionGap = mobile ? 25.0 : 28.0;
                final rowPadding = EdgeInsets.symmetric(
                  horizontal: mobile ? 13 : 14,
                  vertical: 10,
                );
                final appearance = SettingSection(
                  title: l10n.prototypeAppearance,
                  icon: LucideIcons.palette,
                  padding: EdgeInsets.zero,
                  dividerIndent: 0,
                  children: [
                    _ThemeOptions(
                      selected: preferences.themeCode,
                      onSelected: (theme) =>
                          controller.setTheme(context, theme),
                    ),
                    if (AppPlatform.isAndroid)
                      SettingRow(
                        title: l10n.trafficWidgetAdd,
                        minHeight: rowHeight,
                        contentPadding: rowPadding,
                        titleStyle: AppTypography.settingsRow,
                        trailing: state.addingWidget
                            ? const ButtonProgressIndicator(size: 20)
                            : null,
                        showChevron: true,
                        onTap: state.addingWidget
                            ? null
                            : () => controller.addTrafficWidget(context),
                      ),
                    if (controller.showAppIcon)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final label = appIconLabel(l10n, state.appIcon);
                          final valueStyle =
                              (mobile
                                      ? AppTypography.settingsVersion
                                      : AppTypography.desktopSettingsRowValue)
                                  .copyWith(color: palette.mutedStrong);
                          final available =
                              constraints.maxWidth -
                              rowPadding.horizontal -
                              (26 + 11) -
                              (20 + 7) -
                              11;
                          final stacked =
                              _settingsTextWidth(
                                    context,
                                    l10n.prototypeAppIcon,
                                    AppTypography.settingsRow,
                                  ) >
                                  available * 5 / 9 ||
                              _settingsTextWidth(
                                    context,
                                    label,
                                    AppTypography.code.merge(valueStyle),
                                  ) >
                                  available * 4 / 9;
                          return SettingRow(
                            title: l10n.prototypeAppIcon,
                            titleMaxLines: stacked ? 4 : 2,
                            value: stacked ? null : label,
                            subtitleWidget: stacked
                                ? Text(
                                    label,
                                    style: AppTypography.code.merge(valueStyle),
                                  )
                                : null,
                            minHeight: mobile ? 52 : 56,
                            titleStyle: AppTypography.settingsRow,
                            valueStyle: valueStyle,
                            contentPadding: rowPadding,
                            decorateLeading: false,
                            showChevron: true,
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppRadii.compact,
                              ),
                              child:
                                  (AppPlatform.isMacOS
                                          ? state.appIcon.dockAssetImage
                                          : state.appIcon.assetImage)
                                      .image(width: 26, height: 26),
                            ),
                            onTap: () => controller.openSetting(
                              context,
                              AppPageDestination.appIcon,
                            ),
                          );
                        },
                      ),
                  ],
                );
                final language = SettingSection(
                  title: l10n.prototypeLanguage,
                  icon: LucideIcons.languages,
                  padding: EdgeInsets.zero,
                  children: [
                    SettingRow(
                      title: languageNativeLabel(
                        l10n,
                        preferences.languageCode,
                      ),
                      minHeight: rowHeight,
                      contentPadding: rowPadding,
                      titleStyle: AppTypography.settingsRow,
                      showChevron: true,
                      onTap: () => controller.openSetting(
                        context,
                        AppPageDestination.language,
                      ),
                    ),
                  ],
                );
                final startup = SettingSection(
                  title: l10n.prototypeStartup,
                  icon: LucideIcons.power,
                  padding: EdgeInsets.zero,
                  dividerIndent: 0,
                  children: [
                    _StartupSettingRow(
                      title: l10n.prototypeConnectAfterAppLaunch,
                      value: state.connectOnLaunch,
                      onChanged: state.loading || state.saving
                          ? null
                          : (value) =>
                                controller.setConnectOnLaunch(context, value),
                    ),
                    if (AppPlatform.isDesktop)
                      BlocProvider(
                        create: (_) => DesktopSettingsController(),
                        child: const _DesktopStartupRows(),
                      ),
                  ],
                );
                final data = SettingSection(
                  title: l10n.prototypeData,
                  icon: LucideIcons.hardDrive,
                  padding: EdgeInsets.zero,
                  dividerIndent: 0,
                  children: [
                    if (BackupService.supported)
                      SettingRow(
                        title: l10n.backupTitle,
                        minHeight: rowHeight,
                        contentPadding: rowPadding,
                        titleStyle: AppTypography.settingsRow,
                        showChevron: true,
                        onTap: () => controller.openSetting(
                          context,
                          AppPageDestination.backup,
                        ),
                      ),
                    SettingRow(
                      title: l10n.prototypeClearData,
                      minHeight: rowHeight,
                      contentPadding: rowPadding,
                      titleStyle:
                          (mobile
                                  ? AppTypography.settingsDanger
                                  : AppTypography.desktopSettingsDanger)
                              .copyWith(color: palette.destructive),
                      trailing: state.clearingData
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
                  icon: LucideIcons.info,
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
                        titleStyle: AppTypography.settingsRow,
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
                    Column(
                      children: [
                        SettingsVersionRow(
                          label: l10n.prototypeAppVersion,
                          value: state.appVersion,
                          compact: true,
                          style: mobile
                              ? null
                              : AppTypography.desktopSettingsVersion,
                        ),
                        SettingsVersionRow(
                          label: 'Xray-core',
                          value: state.xrayVersion,
                          compact: true,
                          style: mobile
                              ? null
                              : AppTypography.desktopSettingsVersion,
                        ),
                      ],
                    ),
                  ],
                );
                return SettingsPageScroll(
                  desktopMaxWidth: AppLayout.settingsMaxWidth,
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      mobile ? 12 : AppSpacing.page,
                      mobile ? 27 : 43,
                      mobile ? 12 : AppSpacing.page,
                      mobile ? 20 : 42,
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
                        Builder(
                          builder: (context) =>
                              MediaQuery.sizeOf(context).width >
                                  AppLayout.compactDesktopBreakpoint
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        children: [
                                          appearance,
                                          SizedBox(height: sectionGap),
                                          language,
                                          SizedBox(height: sectionGap),
                                          startup,
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 56),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          data,
                                          SizedBox(height: sectionGap),
                                          about,
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    appearance,
                                    SizedBox(height: sectionGap),
                                    language,
                                    SizedBox(height: sectionGap),
                                    startup,
                                    SizedBox(height: sectionGap),
                                    data,
                                    SizedBox(height: sectionGap),
                                    about,
                                  ],
                                ),
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

double _settingsTextWidth(BuildContext context, String label, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.localeOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

class _ThemeOptions extends StatelessWidget {
  final ThemeCode selected;
  final ValueChanged<ThemeCode> onSelected;

  const _ThemeOptions({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final style = mobile
        ? AppTypography.settingsThemeOptionMobile
        : AppTypography.settingsThemeOption;
    final iconSize = mobile ? 16.0 : 18.0;
    final gap = mobile ? 6.0 : 8.0;
    final horizontalPadding = mobile ? 5.0 : 8.0;
    final labels = {
      ThemeCode.system: l10n.prototypeSystem,
      ThemeCode.light: l10n.prototypeLight,
      ThemeCode.dark: l10n.prototypeDark,
    };
    var widestLabel = 0.0;
    for (final label in labels.values) {
      final width = _settingsTextWidth(context, label, style);
      if (width > widestLabel) widestLabel = width;
    }
    final horizontalWidth =
        (widestLabel + iconSize + gap + horizontalPadding * 2) * labels.length;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final vertical = horizontalWidth > constraints.maxWidth;
          Widget option(ThemeCode theme) => Semantics(
            button: true,
            selected: selected == theme,
            child: Material(
              color: selected == theme
                  ? palette.selectedSurface
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.compact),
                side: BorderSide(
                  color: selected == theme
                      ? palette.primary
                      : Colors.transparent,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelected(theme),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: AppLayout.touchExtent(
                      mobile ? 45 : 47,
                      platform: Theme.of(context).platform,
                    ),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: selected == theme || theme == ThemeCode.dark
                        ? null
                        : vertical
                        ? Border(bottom: BorderSide(color: palette.border))
                        : BorderDirectional(
                            end: BorderSide(color: palette.border),
                          ),
                  ),
                  child: Row(
                    mainAxisAlignment: vertical
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      Icon(
                        switch (theme) {
                          ThemeCode.system => LucideIcons.monitor,
                          ThemeCode.light => LucideIcons.sun,
                          ThemeCode.dark => LucideIcons.moon,
                        },
                        size: iconSize,
                        color: selected == theme
                            ? palette.primary
                            : palette.foreground,
                      ),
                      SizedBox(width: gap),
                      Flexible(
                        child: Text(
                          labels[theme]!,
                          textAlign: vertical
                              ? TextAlign.start
                              : TextAlign.center,
                          style: style.copyWith(
                            color: selected == theme
                                ? palette.primary
                                : palette.foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          if (vertical) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final theme in ThemeCode.values) option(theme)],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final theme in ThemeCode.values)
                  Expanded(child: option(theme)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StartupSettingRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _StartupSettingRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return SettingRow(
      title: title,
      minHeight: mobile ? 48 : 56,
      contentPadding: EdgeInsetsDirectional.symmetric(
        horizontal: mobile ? 13 : 14,
        vertical: mobile ? 7 : 9,
      ),
      titleStyle: mobile
          ? AppTypography.settingsFieldTitle
          : AppTypography.settingsRow,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: ShadSwitch(
        value: value,
        width: mobile ? 40 : 46,
        height: mobile ? 23 : 27,
        enabled: onChanged != null,
        onChanged: onChanged,
      ),
    );
  }
}

class _DesktopStartupRows extends StatelessWidget {
  const _DesktopStartupRows();
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DesktopSettingsController, DesktopSettingsPageState>(
        builder: (context, state) {
          final controller = context.read<DesktopSettingsController>();
          final l10n = AppLocalizations.of(context)!;
          return Column(
            children: [
              _StartupSettingRow(
                title: l10n.prototypeLaunchAtLogin,
                value: state.launchAtLogin.enabled,
                onChanged: state.launchToggleEnabled && !state.requiresApproval
                    ? (value) => controller.updateLaunchAtLogin(context, value)
                    : null,
              ),
              const Divider(height: 1),
              _StartupSettingRow(
                title: l10n.prototypeStartHidden,
                value: state.startHidden,
                onChanged: state.behaviorSettingsEnabled
                    ? (value) =>
                          controller.updateStartHidden(value, context: context)
                    : null,
              ),
              if (AppPlatform.isMacOS) ...[
                const Divider(height: 1),
                _StartupSettingRow(
                  title: l10n.prototypeHideDockIcon,
                  value: state.hideDockIcon,
                  onChanged: state.behaviorSettingsEnabled
                      ? (value) => controller.updateHideDockIcon(
                          value,
                          context: context,
                        )
                      : null,
                ),
              ],
              if (state.requiresApproval) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.prototypeSystemApprovalRequired),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: state.changingLaunchAtLogin
                                ? null
                                : () => controller.updateLaunchAtLogin(
                                    context,
                                    false,
                                  ),
                            child: ButtonProgress(
                              busy: state.changingLaunchAtLogin,
                              child: Text(l10n.prototypeCancelRequest),
                            ),
                          ),
                          TextButton(
                            onPressed: state.openingSystemSettings
                                ? null
                                : () => controller.openSystemSettings(context),
                            child: ButtonProgress(
                              busy: state.openingSystemSettings,
                              child: Text(l10n.prototypeOpenSystemSettings),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      );
}
