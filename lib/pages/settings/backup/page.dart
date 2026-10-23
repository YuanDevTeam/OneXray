import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/backup/controller.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/menu_picker.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/settings/backup/service.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSwitch;
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
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        final date = DateFormat.yMd(Localizations.localeOf(context).toString())
            .add_Hm();
        final busy = state.busy;
        return Scaffold(
          appBar: PageAppBar(
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
                    OutlinedButton(
                      onPressed: busy || target == null
                          ? null
                          : () => controller.restore(context),
                      child: ButtonProgress(
                        busy: state.action == BackupPageAction.restoring,
                        child: Text(l.backupRestore),
                      ),
                    ),
                    FilledButton(
                      onPressed: busy || target == null
                          ? null
                          : () => controller.backup(context),
                      child: ButtonProgress(
                        busy:
                            state.action == BackupPageAction.writing ||
                            backup.operation == BackupOperation.writing,
                        child: Text(l.backupNow),
                      ),
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
                      padding: EdgeInsets.all(
                        mobile ? AppSpacing.mobilePage : AppSpacing.page,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 24,
                        children: [
                          SettingSection(
                            title: l.backupLocation,
                            icon: LucideIcons.cloud,
                            padding: EdgeInsets.zero,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: 12,
                                  children: [
                                    if (target != null)
                                      SelectableText(
                                        target.label,
                                        textDirection: TextDirection.ltr,
                                        style: AppTypography.code,
                                      )
                                    else
                                      Text(l.backupNotConfigured),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (target == null) ...[
                                          if (apple)
                                            FilledButton(
                                              onPressed: busy
                                                  ? null
                                                  : () => controller.select(
                                                      context,
                                                      create: false,
                                                    ),
                                              child: Text(l.backupUseICloud),
                                            ),
                                          OutlinedButton(
                                            onPressed: busy
                                                ? null
                                                : () => controller.select(
                                                    context,
                                                    create: false,
                                                    local: apple,
                                                  ),
                                            child: ButtonProgress(
                                              busy:
                                                  state.action ==
                                                  BackupPageAction.selecting,
                                              child: Text(
                                                android || apple
                                                    ? l.backupChooseExisting
                                                    : l.backupChooseFolder,
                                              ),
                                            ),
                                          ),
                                          if (android || apple)
                                            OutlinedButton(
                                              onPressed: busy
                                                  ? null
                                                  : () => controller.select(
                                                      context,
                                                      create: true,
                                                      local: apple,
                                                    ),
                                              child: ButtonProgress(
                                                busy:
                                                    state.action ==
                                                    BackupPageAction.creating,
                                                child: Text(l.backupCreateFile),
                                              ),
                                            ),
                                        ] else ...[
                                          TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => controller.unbind(
                                                    context,
                                                  ),
                                            child: ButtonProgress(
                                              busy:
                                                  state.action ==
                                                  BackupPageAction.unbinding,
                                              child: Text(l.backupUnbind),
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
                                              triggerBuilder: (open) => OutlinedButton(
                                                onPressed: busy ? null : open,
                                                child: ButtonProgress(
                                                  busy:
                                                      state.action ==
                                                          BackupPageAction
                                                              .selecting ||
                                                      state.action ==
                                                          BackupPageAction
                                                              .creating,
                                                  child: Text(
                                                    apple
                                                        ? l.backupSwitchToLocal
                                                        : l.backupChangeLocation,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else
                                            OutlinedButton(
                                              onPressed: busy
                                                  ? null
                                                  : () => controller.select(
                                                      context,
                                                      create: false,
                                                    ),
                                              child: ButtonProgress(
                                                busy:
                                                    state.action ==
                                                    BackupPageAction.selecting,
                                                child: Text(
                                                  apple
                                                      ? l.backupSwitchToCloud
                                                      : l.backupChangeLocation,
                                                ),
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
                                  enabled:
                                      !backup.changingAutomatic &&
                                      state.action !=
                                          BackupPageAction.restoring,
                                  child: ShadSwitch(
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
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: palette.warningSurface,
                              borderRadius: BorderRadius.circular(
                                AppRadii.compact,
                              ),
                            ),
                            child: Text(
                              l.backupSensitiveWarning,
                              style: AppTypography.settingsDetailNote,
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
                            style: AppTypography.settingsDetailNote,
                          ),
                          if (backup.error != null)
                            SelectableText(
                              appFailureMessage(
                                l,
                                backup.error,
                                operation: l.backupFailed,
                              ),
                              style: AppTypography.settingsDetailNote.copyWith(
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
