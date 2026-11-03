import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/backup/controller.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/menu_picker.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/settings/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/service/settings/backup/service.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';
import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:onexray/service/shared/failure.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key, this.service});
  final BackupService? service;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => BackupController(service: service),
    child: BlocBuilder<BackupController, BackupPageState>(
      builder: (context, state) {
        final controller = context.read<BackupController>();
        final l = AppLocalizations.of(context)!;
        final backup = state.backup;
        final target = backup.settings.target;
        final palette = ColorManager.palette(context);
        final platform = defaultTargetPlatform;
        final android = platform == TargetPlatform.android;
        final windows = platform == TargetPlatform.windows;
        final apple =
            platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
        final supported = {
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
          TargetPlatform.windows,
        }.contains(platform);
        final date = DateFormat.yMd(Localizations.localeOf(context).toString())
            .add_Hm();
        final busy = state.busy;
        return Scaffold(
          appBar: PageAppBar.forPage(
            context,
            description: l.backupPageDescription,
            title: Text(l.backupTitle),
            actions: [
              PageHelpButton(
                title: l.backupTitle,
                messages: [
                  l.backupScope,
                  android
                      ? l.backupAndroidHint
                      : windows
                      ? l.backupWindowsHint
                      : l.backupAppleHint,
                  l.backupScheduleNotice,
                  l.backupSyncNotice,
                ],
              ),
            ],
          ),
          bottomNavigationBar: supported
              ? PageActionBar(
                  children: [
                    SettingsActionButton(
                      label: l.backupRestore,
                      variant: ShadButtonVariant.outline,
                      enabled: !busy && target != null,
                      busy: state.action == BackupPageAction.restoring,
                      onPressed: busy || target == null
                          ? null
                          : () => controller.restore(context),
                    ),
                    SettingsActionButton(
                      label: l.backupNow,
                      enabled: !busy && target != null,
                      busy:
                          state.action == BackupPageAction.writing ||
                          backup.operation == BackupOperation.writing,
                      onPressed: busy || target == null
                          ? null
                          : () => controller.backup(context),
                    ),
                  ],
                )
              : null,
          body: SafeArea(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : !supported
                ? Center(child: Text(l.prototypeTemporarilyUnavailable))
                : SettingsPageScroll(
                    child: Padding(
                      padding: settingsContentPadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 20,
                        children: [
                          SettingSection(
                            title: l.backupLocation,
                            icon: LucideIcons.cloud,
                            padding: EdgeInsets.zero,
                            children: [
                              Padding(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: 12,
                                  children: [
                                    if (target != null)
                                      SelectableText(
                                        target.label,
                                        textDirection: TextDirection.ltr,
                                        style: AppTypography.supporting,
                                      )
                                    else
                                      Text(l.backupNotConfigured),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (target == null) ...[
                                          if (apple)
                                            SettingsActionButton(
                                              label: l.backupUseICloud,
                                              enabled: !busy,
                                              onPressed: busy
                                                  ? null
                                                  : () => controller.select(
                                                      context,
                                                      create: false,
                                                    ),
                                            ),
                                          SettingsActionButton(
                                            label: android || apple
                                                ? l.backupChooseExisting
                                                : l.backupChooseFolder,
                                            variant: ShadButtonVariant.outline,
                                            enabled: !busy,
                                            busy:
                                                state.action ==
                                                BackupPageAction.selecting,
                                            onPressed: busy
                                                ? null
                                                : () => controller.select(
                                                    context,
                                                    create: false,
                                                    local: apple,
                                                  ),
                                          ),
                                          if (android || apple)
                                            SettingsActionButton(
                                              label: l.backupCreateFile,
                                              variant:
                                                  ShadButtonVariant.outline,
                                              enabled: !busy,
                                              busy:
                                                  state.action ==
                                                  BackupPageAction.creating,
                                              onPressed: busy
                                                  ? null
                                                  : () => controller.select(
                                                      context,
                                                      create: true,
                                                      local: apple,
                                                    ),
                                            ),
                                        ] else ...[
                                          SettingsActionButton(
                                            label: l.backupUnbind,
                                            variant: ShadButtonVariant.ghost,
                                            enabled: !busy,
                                            busy:
                                                state.action ==
                                                BackupPageAction.unbinding,
                                            onPressed: busy
                                                ? null
                                                : () => controller.unbind(
                                                    context,
                                                  ),
                                          ),
                                          if (android ||
                                              (apple &&
                                                  backup.settings.usesICloud))
                                            AppMenuButton<bool>(
                                              entries: [
                                                AppMenuEntry.item(
                                                  value: false,
                                                  title: l.backupChooseExisting,
                                                ),
                                                AppMenuEntry.item(
                                                  value: true,
                                                  title: l.backupCreateFile,
                                                ),
                                              ],
                                              onSelected: (create) =>
                                                  controller.select(
                                                    context,
                                                    create: create,
                                                    local: apple,
                                                  ),
                                              triggerBuilder: (open) =>
                                                  SettingsActionButton(
                                                    label: apple
                                                        ? l.backupSwitchToLocal
                                                        : l.backupChangeLocation,
                                                    variant: ShadButtonVariant
                                                        .outline,
                                                    enabled: !busy,
                                                    busy:
                                                        state.action ==
                                                            BackupPageAction
                                                                .selecting ||
                                                        state.action ==
                                                            BackupPageAction
                                                                .creating,
                                                    onPressed: busy
                                                        ? null
                                                        : open,
                                                  ),
                                            )
                                          else
                                            SettingsActionButton(
                                              label: apple
                                                  ? l.backupSwitchToCloud
                                                  : l.backupChangeLocation,
                                              variant:
                                                  ShadButtonVariant.outline,
                                              enabled: !busy,
                                              busy:
                                                  state.action ==
                                                  BackupPageAction.selecting,
                                              onPressed: busy
                                                  ? null
                                                  : () => controller.select(
                                                      context,
                                                      create: false,
                                                    ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SettingSection(
                            title: l.backupAutomatic,
                            icon: LucideIcons.refreshCw,
                            padding: EdgeInsets.zero,
                            dividerIndent: 0,
                            action: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (backup.changingAutomatic)
                                  const Padding(
                                    padding: EdgeInsetsDirectional.only(end: 8),
                                    child: ButtonProgressIndicator(),
                                  ),
                                Semantics(
                                  label: l.backupAutomatic,
                                  child: AppSwitch(
                                    value: backup.automatic,
                                    enabled:
                                        !backup.changingAutomatic &&
                                        state.action !=
                                            BackupPageAction.restoring,
                                    onChanged: (value) =>
                                        controller.setAutomatic(context, value),
                                  ),
                                ),
                              ],
                            ),
                            children: [
                              SettingRow(
                                title: l.backupInterval,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (state.action ==
                                        BackupPageAction.savingInterval)
                                      const Padding(
                                        padding: EdgeInsetsDirectional.only(
                                          end: 8,
                                        ),
                                        child: ButtonProgressIndicator(),
                                      ),
                                    SettingSelect<AutoUpdateInterval>(
                                      value: backup.interval,
                                      entries: {
                                        AutoUpdateInterval.oneDay:
                                            l.prototypeEveryDay,
                                        AutoUpdateInterval.threeDays:
                                            l.prototypeEveryThreeDays,
                                        AutoUpdateInterval.oneWeek:
                                            l.prototypeEveryWeek,
                                      },
                                      onChanged: busy
                                          ? null
                                          : (value) => controller.setInterval(
                                              context,
                                              value,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          ShadAlert(
                            icon: const Icon(LucideIcons.circleHelp, size: 18),
                            description: Text(l.backupSensitiveWarning),
                            descriptionStyle: AppTypography.supporting.copyWith(
                              color: palette.mutedStrong,
                            ),
                          ),
                          Text(
                            backup.settings.lastSuccess == null
                                ? l.backupNeverWritten
                                : l.backupLastSuccess(
                                    date.format(
                                      backup.settings.lastSuccess!.toLocal(),
                                    ),
                                  ),
                            style: AppTypography.supporting,
                          ),
                          if (backup.error != null)
                            SelectableText(
                              appFailureMessage(
                                l,
                                backup.error,
                                operation: l.backupFailed,
                              ),
                              style: AppTypography.supporting.copyWith(
                                color: palette.destructive,
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
}
