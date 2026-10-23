import 'package:onexray/service/shared/failure.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/service/shared/ping/state.dart';

class PingPageState {
  static const _unset = Object();

  final PingState pingState;
  final bool loading;
  final bool loaded;
  final bool saving;
  final String? error;
  final bool invalidUrl;

  PingPageState({
    PingState? pingState,
    this.loading = true,
    this.loaded = false,
    this.saving = false,
    this.error,
    this.invalidUrl = false,
  }) : pingState = pingState ?? PingState();

  PingPageState copyWith({
    bool? loading,
    bool? loaded,
    bool? saving,
    Object? error = _unset,
    bool? invalidUrl,
  }) {
    return PingPageState(
      pingState: pingState,
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      saving: saving ?? this.saving,
      error: identical(error, _unset) ? this.error : error as String?,
      invalidUrl: invalidUrl ?? this.invalidUrl,
    );
  }
}

class PingController extends PageCubit<PingPageState> {
  PingController() : super(PingPageState()) {
    customUrlController.addListener(_urlChanged);
    load();
  }

  final customUrlController = TextEditingController();
  final customUrlFocusNode = FocusNode();
  String _lastUrlText = '';

  void _urlChanged() {
    final text = customUrlController.text;
    if (text == _lastUrlText) return;
    _lastUrlText = text;
    if (state.invalidUrl) emit(state.copyWith(invalidUrl: false));
  }

  void _revealUrl() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isPageActive) return;
      customUrlFocusNode.requestFocus();
      final fieldContext = customUrlFocusNode.context;
      if (fieldContext != null && fieldContext.mounted) {
        Scrollable.ensureVisible(
          fieldContext,
          alignment: .5,
          duration: const Duration(milliseconds: 120),
        );
      }
    });
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true, error: null, invalidUrl: false));
    try {
      final pingState = PingState();
      await pingState.readFromPreferences();
      if (!isPageActive) return;
      customUrlController.text = pingState.customUrl;
      emit(PingPageState(pingState: pingState, loading: false, loaded: true));
    } catch (error) {
      emit(state.copyWith(loading: false, error: failureDetails(error)));
    }
  }

  @override
  void disposePageResources() {
    customUrlController.removeListener(_urlChanged);
    customUrlController.dispose();
    customUrlFocusNode.dispose();
  }

  void updateTimeout(double value) {
    state.pingState.timeout = value;
    emit(state.copyWith());
  }

  void updateUrl(String value) {
    final url = PingUrl.fromString(value);
    if (url != null) {
      state.pingState.url = url;
      emit(state.copyWith(invalidUrl: false));
    }
  }

  void cancel(BuildContext context) => context.pop();

  Future<void> save(BuildContext context) async {
    if (!state.loaded || state.saving) return;
    final customUrl = customUrlController.text.trim();
    if (state.pingState.url == PingUrl.custom) {
      if (!PingUrl.isValidCustomUrl(customUrl)) {
        emit(state.copyWith(invalidUrl: true));
        _revealUrl();
        return;
      }
    }
    emit(state.copyWith(saving: true, error: null, invalidUrl: false));
    try {
      state.pingState.customUrl = customUrl;
      await state.pingState.saveToPreferences();
      if (isPageActive && context.mounted) {
        ContextAlert.settingsSaved(context, closePage: true);
      }
    } catch (error) {
      emit(state.copyWith(error: failureDetails(error)));
    } finally {
      emit(state.copyWith(saving: false));
    }
  }
}
