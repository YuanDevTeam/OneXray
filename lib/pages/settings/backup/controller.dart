import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/backup/existing_file_dialog.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';
import 'package:onexray/service/settings/backup/service.dart';
import 'package:onexray/service/shared/failure.dart';

enum BackupPageAction {
  selecting,
  creating,
  savingInterval,
  writing,
  restoring,
  unbinding,
}

class BackupPageState {
  const BackupPageState({
    this.backup = const BackupState(),
    this.loading = true,
    this.action,
  });
  final BackupState backup;
  final bool loading;
  final BackupPageAction? action;
  bool get busy => loading || action != null || backup.operation != null;
}

class BackupController extends PageCubit<BackupPageState> {
  BackupController({BackupService? service})
    : service = service ?? BackupService(),
      super(const BackupPageState()) {
    _subscription = this.service.stream.listen(
      (value) => emit(
        BackupPageState(
          backup: value,
          loading: state.loading,
          action: state.action,
        ),
      ),
    );
    unawaited(load());
  }
  final BackupService service;
  StreamSubscription<BackupState>? _subscription;

  Future<void> load() async {
    await service.load();
    emit(
      BackupPageState(
        backup: service.state,
        loading: false,
        action: state.action,
      ),
    );
  }

  Future<void> select(
    BuildContext context, {
    required bool create,
    bool local = false,
  }) => _perform(
    context,
    create ? BackupPageAction.creating : BackupPageAction.selecting,
    () async {
      await service.select(
        create: create,
        local: local,
        onExisting: (target, preview) async {
          if (!isPageActive || !context.mounted) return null;
          final action = await showAppDialog<BackupExistingAction>(
            context,
            (_) => ExistingBackupDialog(location: target.label),
          );
          if (!isPageActive || !context.mounted) return null;
          if (action == BackupExistingAction.restore) {
            final details = await preview();
            if (!isPageActive || !context.mounted) return null;
            if (!await _confirmRestore(context, details)) return null;
          }
          return isPageActive && context.mounted ? action : null;
        },
      );
    },
  );

  Future<void> backup(BuildContext context) =>
      _perform(context, BackupPageAction.writing, () async {
        final l = AppLocalizations.of(context)!;
        if (service.state.settings.target == null) return;
        if (!isPageActive || !context.mounted) return;
        if (await service.backupNow() && isPageActive && context.mounted) {
          ContextAlert.showToast(context, l.backupWritten);
        }
      });

  Future<void> restore(BuildContext context) =>
      _perform(context, BackupPageAction.restoring, () async {
        final l = AppLocalizations.of(context)!;
        final preview = await service.preview();
        if (!isPageActive || !context.mounted) return;
        final confirmed = await _confirmRestore(context, preview);
        if (!confirmed || !isPageActive || !context.mounted) return;
        final pending = await service.restore(preview);
        if (isPageActive && context.mounted) {
          ContextAlert.showToast(context, l.backupRestored(pending));
        }
      });

  Future<bool> _confirmRestore(BuildContext context, BackupPreview preview) {
    final l = AppLocalizations.of(context)!;
    final date = DateFormat.yMd(Localizations.localeOf(context).toString())
        .add_Hm();
    return AppConfirmationDialog(
      title: l.backupRestoreTitle,
      content: [
        l.backupCreatedAt(date.format(preview.createdAt.toLocal())),
        l.backupSummary(
          preview.nodes,
          preview.raw,
          preview.subscriptions,
          preview.routes,
        ),
        if (preview.pending > 0) l.backupPendingCount(preview.pending),
        if (preview.conflicts.isNotEmpty)
          l.backupConflicts(preview.conflicts.join(', ')),
        if (preview.empty) l.backupEmptyWarning,
        l.backupRestoreWarning,
      ].join('\n\n'),
      cancelLabel: l.prototypeCancel,
      confirmLabel: l.backupRestore,
      destructive: true,
    ).show(context);
  }

  Future<void> setAutomatic(BuildContext context, bool value) async {
    if (state.backup.changingAutomatic) return;
    try {
      await service.setAutomatic(value);
    } catch (error) {
      if (isPageActive && context.mounted) {
        final l = AppLocalizations.of(context)!;
        ContextAlert.showToast(
          context,
          appFailureMessage(l, error, operation: l.backupFailed),
        );
      }
    }
  }

  Future<void> setInterval(
    BuildContext context,
    AutoUpdateInterval? value,
  ) async {
    if (value == null || value == state.backup.interval) return;
    await _perform(context, BackupPageAction.savingInterval, () async {
      await service.setInterval(value);
      if (isPageActive && context.mounted) {
        ContextAlert.settingsSaved(context);
      }
    });
  }

  Future<void> unbind(BuildContext context) => _perform(
    context,
    BackupPageAction.unbinding,
    () async {
      final l = AppLocalizations.of(context)!;
      final confirmed = await AppConfirmationDialog(
        title: l.backupUnbind,
        content: l.backupUnbindWarning,
        cancelLabel: l.prototypeCancel,
        confirmLabel: l.backupUnbind,
      ).show(context);
      if (confirmed && isPageActive && context.mounted) await service.unbind();
    },
  );

  Future<void> _perform(
    BuildContext context,
    BackupPageAction action,
    Future<void> Function() operation,
  ) async {
    if (state.busy) return;
    emit(
      BackupPageState(backup: service.state, loading: false, action: action),
    );
    try {
      await operation();
    } catch (error) {
      if (isPageActive && context.mounted) {
        final l = AppLocalizations.of(context)!;
        ContextAlert.showToast(
          context,
          appFailureMessage(l, error, operation: l.backupFailed),
        );
      }
    } finally {
      emit(BackupPageState(backup: service.state, loading: false));
    }
  }

  @override
  Future<void> disposePageResources() async {
    await _subscription?.cancel();
  }
}
