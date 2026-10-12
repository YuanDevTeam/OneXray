import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/event_bus/state.dart';
import 'package:onexray/service/manager.dart';
import 'package:onexray/service/shared/ping/batch.dart';

class AppEventBus extends Cubit<AppEventBusState> {
  static late AppEventBus instance;

  bool _closing = false;
  int _downloads = 0;

  bool get _isActive => !_closing && !isClosed;

  AppEventBus() : super(AppEventBusState.initial()) {
    instance = this;
  }

  Future<void> asyncInitTheme() async {
    final themeCode = await PreferencesKey().readThemeCode();
    final languageCode = await PreferencesKey().readLanguageCode();
    if (!_isActive) {
      return;
    }
    emit(
      state.copyWith(
        themeCode: ThemeCode.fromString(themeCode),
        languageCode: LanguageCode.fromString(languageCode),
      ),
    );
  }

  void updatePinging(bool value) {
    emit(state.copyWith(pinging: value));
  }

  void updatePingResults(Map<int, PingBatchResult> results) {
    final failures = {...state.pingFailures};
    for (final entry in results.entries) {
      if (!entry.value.success) {
        failures[entry.key] = entry.value;
      } else {
        failures.remove(entry.key);
      }
    }
    emit(state.copyWith(pingFailures: Map.unmodifiable(failures)));
  }

  void clearPingFailures() => emit(state.copyWith(pingFailures: const {}));

  Future<T> trackDownload<T>(Future<T> Function() action) async {
    if (_downloads++ == 0) emit(state.copyWith(downloading: true));
    try {
      return await action();
    } finally {
      if (--_downloads == 0) emit(state.copyWith(downloading: false));
    }
  }

  void updateAppUpdateInfo(AppUpdateInfo? value) {
    emit(
      value == null
          ? state.copyWith(clearAppUpdateInfo: true)
          : state.copyWith(appUpdateInfo: value),
    );
  }

  Future<void> updateThemeCode(ThemeCode value) async {
    await PreferencesKey().saveThemeCode(value.name);
    if (!_isActive) {
      return;
    }
    emit(state.copyWith(themeCode: value));
  }

  Future<void> updateLanguageCode(LanguageCode value) async {
    await PreferencesKey().saveLanguageCode(value.name);
    if (!_isActive) {
      return;
    }
    emit(state.copyWith(languageCode: value));
  }

  @override
  void emit(AppEventBusState state) {
    if (!_isActive) {
      return;
    }
    super.emit(state);
  }

  @override
  Future<void> close() {
    if (_closing || isClosed) {
      return Future.value();
    }
    _closing = true;
    ServiceManager.serviceDispose();
    return super.close();
  }
}
