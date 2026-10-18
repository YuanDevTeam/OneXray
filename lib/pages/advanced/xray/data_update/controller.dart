import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';

class AutoUpdatePageState {
  final AutoUpdateState autoUpdateState;
  final bool loading;
  final bool loaded;
  final bool saving;
  final bool failed;
  final Object? failure;
  AutoUpdatePageState({
    AutoUpdateState? autoUpdateState,
    this.loading = true,
    this.saving = false,
    this.failed = false,
    this.failure,
    this.loaded = false,
  }) : autoUpdateState = autoUpdateState ?? AutoUpdateState();

  AutoUpdatePageState copyWith({
    bool? loading,
    bool? loaded,
    bool? saving,
    bool? failed,
    Object? failure,
  }) => AutoUpdatePageState(
    autoUpdateState: autoUpdateState,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    failed: failed ?? this.failed,
    failure: failed == false ? null : failure ?? this.failure,
    loaded: loaded ?? this.loaded,
  );
}

class AutoUpdateController extends PageCubit<AutoUpdatePageState> {
  AutoUpdateController() : super(AutoUpdatePageState()) {
    load();
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true, failed: false));
    try {
      final value = AutoUpdateState();
      await value.readFromPreferences();
      emit(
        AutoUpdatePageState(
          autoUpdateState: value,
          loading: false,
          loaded: true,
        ),
      );
    } catch (error) {
      emit(state.copyWith(loading: false, failed: true, failure: error));
    }
  }

  void updateSubscriptionEnabled(bool value) {
    state.autoUpdateState.subscriptionEnabled = value;
    emit(state.copyWith());
  }

  void updateSubscriptionInterval(AutoUpdateInterval? value) {
    if (value == null) return;
    state.autoUpdateState.subscriptionInterval = value;
    emit(state.copyWith());
  }

  void updateGeoDataEnable(bool value) {
    state.autoUpdateState.geoDataEnable = value;
    emit(state.copyWith());
  }

  void updateGeoDataInterval(AutoUpdateInterval? value) {
    if (value == null) return;
    state.autoUpdateState.geoDataInterval = value;
    emit(state.copyWith());
  }

  void cancel(BuildContext context) => context.pop();

  Future<void> save(BuildContext context) async {
    if (!state.loaded || state.saving) return;
    emit(state.copyWith(saving: true, failed: false));
    try {
      await state.autoUpdateState.saveToPreferences();
      if (context.mounted) ContextAlert.settingsSaved(context, closePage: true);
    } catch (error) {
      emit(state.copyWith(failed: true, failure: error));
    } finally {
      emit(state.copyWith(saving: false));
    }
  }
}
