import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/launch/setup/selectors.dart';
import 'package:onexray/pages/main/url.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/launch/setup.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/shared/failure.dart';

enum SetupAction {
  acceptPrivacy,
  privacy,
  back,
  chooseInterface,
  chooseRegion,
  useTunnel,
  useProxy,
  finish,
  retry,
}

class SetupPageState {
  final SetupStep step;
  final bool busy;
  final SetupAction? activeAction;
  final bool localReady;
  final String interfaceName;
  final List<String>? regions;
  final SetupFailure? failure;
  final CaptureMode captureMode;

  const SetupPageState({
    this.step = SetupStep.welcome,
    this.busy = true,
    this.activeAction,
    this.localReady = false,
    this.interfaceName = '',
    this.regions,
    this.failure,
    this.captureMode = CaptureMode.tun,
  });

  bool ready({required bool requiresInterface}) =>
      localReady && (!requiresInterface || interfaceName.isNotEmpty);

  SetupPageState copyWith({
    SetupStep? step,
    bool? busy,
    SetupAction? activeAction,
    bool clearAction = false,
    bool? localReady,
    String? interfaceName,
    List<String>? regions,
    SetupFailure? failure,
    bool clearFailure = false,
    CaptureMode? captureMode,
  }) => SetupPageState(
    step: step ?? this.step,
    busy: busy ?? this.busy,
    activeAction: clearAction ? null : activeAction ?? this.activeAction,
    localReady: localReady ?? this.localReady,
    interfaceName: interfaceName ?? this.interfaceName,
    regions: regions == null ? this.regions : List.unmodifiable(regions),
    failure: clearFailure ? null : failure ?? this.failure,
    captureMode: captureMode ?? this.captureMode,
  );
}

class SetupController extends PageCubit<SetupPageState> {
  final SetupService service;
  bool _modeLoaded = false;

  SetupController({SetupService? service})
    : service = service ?? SetupService(),
      super(const SetupPageState()) {
    unawaited(
      _perform(() async {
        emit(state.copyWith(step: await this.service.currentStep()));
        await _load();
      }, initial: true),
    );
  }

  void handleAction(BuildContext context, SetupAction action) {
    if (action == SetupAction.privacy) {
      unawaited(context.push('${RouterPath.setup}/privacy'));
      return;
    }
    if (state.busy) return;
    if (action == SetupAction.useTunnel || action == SetupAction.useProxy) {
      if (service.supportsProxy) {
        emit(
          state.copyWith(
            captureMode: action == SetupAction.useProxy
                ? CaptureMode.proxy
                : CaptureMode.tun,
            clearFailure: true,
          ),
        );
      }
      return;
    }
    if (action == SetupAction.back) {
      showWelcome();
      return;
    }
    emit(state.copyWith(activeAction: action));
    switch (action) {
      case SetupAction.acceptPrivacy:
        unawaited(acceptPrivacy());
      case SetupAction.privacy || SetupAction.back:
        break;
      case SetupAction.useTunnel || SetupAction.useProxy:
        break;
      case SetupAction.chooseInterface:
        unawaited(chooseInterface(context));
      case SetupAction.chooseRegion:
        unawaited(chooseRegion(context));
      case SetupAction.finish:
        unawaited(finish());
      case SetupAction.retry:
        unawaited(retry());
    }
  }

  Future<void> _load() async {
    if (state.step != SetupStep.configuration) return;
    emit(state.copyWith(localReady: false));
    await service.prepareLocal();
    final configuration = await service.configuration();
    final codes = await service.regionCodes();
    emit(
      state.copyWith(
        localReady: true,
        captureMode: _modeLoaded
            ? state.captureMode
            : configuration.policy.captureMode,
        interfaceName: state.interfaceName.isEmpty
            ? configuration.policy.xrayOutboundInterfaceName
            : state.interfaceName,
      ),
    );
    _modeLoaded = true;
    if (state.regions == null) {
      final region = await service.suggestRegion();
      if (region != null && codes.contains(region)) {
        emit(state.copyWith(regions: [region]));
      }
    }
  }

  Future<void> retry() => _perform(_load);

  void showWelcome() =>
      emit(state.copyWith(step: SetupStep.welcome, clearFailure: true));

  Future<void> acceptPrivacy() => _perform(() async {
    await service.acceptPrivacy();
    emit(state.copyWith(step: SetupStep.configuration, clearAction: true));
    await _load();
  });

  Future<void> chooseInterface(BuildContext context) => _perform(() async {
    final options = await service.interfaces();
    if (!context.mounted) return;
    final name = await context.push<String>(
      '${RouterPath.setup}/interface',
      extra: SetupInterfaceParams(options, state.interfaceName),
    );
    if (name != null) emit(state.copyWith(interfaceName: name));
  });

  Future<void> chooseRegion(BuildContext context) => _perform(() async {
    final regions = await context.push<List<String>>(
      '${RouterPath.setup}/region',
      extra: state.regions ?? const <String>[],
    );
    if (regions != null) emit(state.copyWith(regions: regions));
  });

  Future<void> finish() => _perform(() async {
    await service.finish(
      interfaceName: state.interfaceName,
      regions: state.regions,
      captureMode: state.captureMode,
    );
    emit(state.copyWith(step: SetupStep.complete));
  });

  void goConnect(BuildContext context) => context.go(RouterPath.connect);

  String failureText(AppLocalizations l10n) =>
      switch (state.failure?.component) {
        'interface' => l10n.prototypeChooseInterfaceNotice,
        _ => appFailureMessage(l10n, state.failure),
      };

  Future<void> _perform(
    Future<void> Function() action, {
    bool initial = false,
  }) async {
    if (state.busy && !initial) return;
    emit(state.copyWith(busy: true, clearFailure: true));
    try {
      await action();
    } catch (error) {
      emit(
        state.copyWith(
          failure: error is SetupFailure
              ? error
              : SetupFailure('local', cause: error),
        ),
      );
    } finally {
      emit(state.copyWith(busy: false, clearAction: true));
    }
  }
}
