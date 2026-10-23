import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:re_editor/re_editor.dart';

@immutable
class ServerEditorPageState {
  const ServerEditorPageState({
    this.draft,
    this.jsonText = '',
    this.busy = false,
    this.loading = true,
    this.confirmingClose = false,
    this.closeAllowed = false,
    this.error,
    this.diagnostic,
  });

  final ServerEditDraft? draft;
  final String jsonText;
  final bool busy;
  final bool loading;
  final bool confirmingClose;
  final bool closeAllowed;
  final String? error;
  final JsonDiagnostic? diagnostic;

  bool get loaded => draft != null;
  bool get dirty => jsonText != (draft?.text ?? '');
  bool get canPop => closeAllowed || (!busy && !confirmingClose && !dirty);
  String? get name => draft?.original.name;
  bool get fromSubscription => draft != null && draft!.original.subId != 0;
  ServerEditorPageState copyWith({
    ServerEditDraft? draft,
    String? jsonText,
    bool? busy,
    bool? loading,
    bool? confirmingClose,
    bool? closeAllowed,
    String? error,
    JsonDiagnostic? diagnostic,
    bool clearError = false,
  }) => ServerEditorPageState(
    draft: draft ?? this.draft,
    jsonText: jsonText ?? this.jsonText,
    busy: busy ?? this.busy,
    loading: loading ?? this.loading,
    confirmingClose: confirmingClose ?? this.confirmingClose,
    closeAllowed: closeAllowed ?? this.closeAllowed,
    error: clearError ? null : error ?? this.error,
    diagnostic: clearError ? null : diagnostic ?? this.diagnostic,
  );
}

class ServerEditorController extends PageCubit<ServerEditorPageState> {
  ServerEditorController(this.serverId, {ServerAssetService? service})
    : service = service ?? ServerAssetService(),
      super(const ServerEditorPageState()) {
    text.addListener(_textChanged);
  }

  final int serverId;
  final ServerAssetService service;
  final text = CodeLineEditingController();
  int _revision = 0;

  void _textChanged() {
    if (!isPageActive || text.text == state.jsonText) return;
    _revision++;
    emit(state.copyWith(jsonText: text.text, clearError: true));
  }

  Future<void> closePage(BuildContext context) async {
    if (!isPageActive ||
        !context.mounted ||
        state.busy ||
        state.confirmingClose ||
        state.closeAllowed ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (state.dirty) {
      final l = AppLocalizations.of(context)!;
      emit(state.copyWith(confirmingClose: true));
      var discard = false;
      try {
        discard = await AppConfirmationDialog(
          title: l.jsonEditorDiscardTitle,
          content: l.jsonEditorDiscardMessage,
          cancelLabel: l.jsonEditorKeepEditing,
          confirmLabel: l.jsonEditorDiscardChanges,
          destructive: true,
        ).show(context);
      } finally {
        emit(state.copyWith(confirmingClose: false));
      }
      if (!discard || !isPageActive || state.busy || !context.mounted) return;
    }
    _finishClose(context);
  }

  void _finishClose(BuildContext context, {int? result}) {
    if (!isPageActive || !context.mounted || state.closeAllowed) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true) return;
    emit(state.copyWith(closeAllowed: true));
    // Let this page's PopScope accept the confirmed exit before popping it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isPageActive || !context.mounted) return;
      if (route?.isCurrent != true) {
        emit(state.copyWith(closeAllowed: false));
        return;
      }
      Navigator.of(context).pop(result);
    });
  }

  Future<void> load(BuildContext context) async {
    final initialText = text.text;
    final initialRevision = _revision;
    try {
      final draft = await service.load(serverId);
      if (!isPageActive) return;
      emit(state.copyWith(draft: draft));
      if (_revision == initialRevision && text.text == initialText) {
        text.text = draft.text;
      }
    } catch (error) {
      if (context.mounted) {
        emit(
          state.copyWith(
            error: appFailureMessage(AppLocalizations.of(context)!, error),
          ),
        );
      }
    } finally {
      emit(state.copyWith(loading: false));
    }
  }

  Future<void> save(BuildContext context) async {
    if (state.busy ||
        state.loading ||
        state.confirmingClose ||
        state.closeAllowed ||
        !state.loaded) {
      return;
    }
    final revision = _revision;
    final submitted = ServerEditDraft(state.draft!.original, state.jsonText);
    final l = AppLocalizations.of(context)!;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      final saved = await service.save(
        submitted,
        confirmReconnect: () => isPageActive && context.mounted
            ? ContextAlert.showConfirmDialog(
                context,
                title: l.prototypeApplyChange,
                content: l.prototypeReconnectNotice,
                confirmLabel: l.prototypeApplyAndReconnect,
              )
            : Future.value(false),
      );
      if (saved && isPageActive) {
        // Keep the exact submitted text as the baseline, even if a later read
        // formats the persisted JSON differently.
        emit(state.copyWith(draft: submitted));
        if (context.mounted && revision == _revision) {
          ContextAlert.showToast(context, l.prototypeSettingsSaved);
          _finishClose(context, result: serverId);
        } else {
          final savedDraft = await service.load(serverId);
          if (!isPageActive) return;
          emit(
            state.copyWith(
              draft: ServerEditDraft(savedDraft.original, submitted.text),
            ),
          );
          if (context.mounted) {
            ContextAlert.showToast(context, l.jsonEditorEarlierDraftSaved);
          }
        }
      }
    } catch (error) {
      if (!isPageActive || revision != _revision) return;
      emit(
        state.copyWith(
          diagnostic: JsonDiagnostic.fromError(error),
          error: appFailureMessage(l, error, operation: l.buttonSaveFailed),
        ),
      );
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  @override
  void disposePageResources() {
    text.removeListener(_textChanged);
    text.dispose();
  }
}
