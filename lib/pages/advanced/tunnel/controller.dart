import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/service/connect/failure.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';
import 'package:onexray/service/advanced/tunnel/apple/removal.dart';
import 'package:onexray/service/shared/failure.dart';

enum TunnelDestination { dns, network, apple, android, windows, interface }

typedef OpenTunnelPage = Future<bool?> Function(
  BuildContext context,
  TunnelDestination destination,
  PolicyEditorDraft draft,
);
typedef OpenPolicyChild = Future<bool?> Function(
  BuildContext context,
  PolicyEditorDraft draft,
);
typedef OpenAndroidApps = Future<List<String>?> Function(
  BuildContext context,
  String mode,
  List<String> selected,
);

const _notProvided = Object();

@immutable
class PolicyEditorPageState {
  final PolicyEditorDraft? draft;
  final bool busy;
  final TunnelDestination? loadingDestination;
  final String? error;
  final TunnelDnsValidationException? dnsFailure;
  final Map<String, String> androidAppNames;
  final ConnectionView connection;
  final AppleVpnCapabilities? appleCapabilities;
  final bool appleCapabilitiesLoading;
  final bool? apnsPresetApplicable;
  final bool apnsPresetChecking;
  final List<OutboundInterfaceOption> interfaces;
  final bool interfacesLoading;
  final bool interfacesFailed;
  final bool? appleSystemExtension;
  final bool appleVpnRemovalLoading;
  final bool appleVpnRemovalBusy;
  final String? appleVpnRemovalError;
  final bool appleVpnRemovalRestartRequired;
  final bool? systemProxySupported;
  final bool systemProxyLoading;

  PolicyEditorPageState({
    this.draft,
    this.busy = false,
    this.loadingDestination,
    this.error,
    this.dnsFailure,
    Map<String, String> androidAppNames = const {},
    this.connection = const ConnectionView(),
    this.appleCapabilities,
    this.appleCapabilitiesLoading = false,
    this.apnsPresetApplicable,
    this.apnsPresetChecking = false,
    List<OutboundInterfaceOption> interfaces = const [],
    this.interfacesLoading = true,
    this.interfacesFailed = false,
    this.appleSystemExtension,
    this.appleVpnRemovalLoading = false,
    this.appleVpnRemovalBusy = false,
    this.appleVpnRemovalError,
    this.appleVpnRemovalRestartRequired = false,
    this.systemProxySupported,
    this.systemProxyLoading = false,
  }) : androidAppNames = Map<String, String>.unmodifiable(androidAppNames),
       interfaces = List<OutboundInterfaceOption>.unmodifiable(interfaces);

  PolicyEditorPageState copyWith({
    Object? draft = _notProvided,
    bool? busy,
    Object? loadingDestination = _notProvided,
    Object? error = _notProvided,
    Object? dnsFailure = _notProvided,
    Map<String, String>? androidAppNames,
    ConnectionView? connection,
    Object? appleCapabilities = _notProvided,
    bool? appleCapabilitiesLoading,
    Object? apnsPresetApplicable = _notProvided,
    bool? apnsPresetChecking,
    List<OutboundInterfaceOption>? interfaces,
    bool? interfacesLoading,
    bool? interfacesFailed,
    Object? appleSystemExtension = _notProvided,
    bool? appleVpnRemovalLoading,
    bool? appleVpnRemovalBusy,
    Object? appleVpnRemovalError = _notProvided,
    bool? appleVpnRemovalRestartRequired,
    bool? systemProxySupported,
    bool? systemProxyLoading,
  }) => PolicyEditorPageState(
    draft: identical(draft, _notProvided)
        ? this.draft
        : draft as PolicyEditorDraft?,
    busy: busy ?? this.busy,
    loadingDestination: identical(loadingDestination, _notProvided)
        ? this.loadingDestination
        : loadingDestination as TunnelDestination?,
    error: identical(error, _notProvided) ? this.error : error as String?,
    dnsFailure: identical(dnsFailure, _notProvided)
        ? this.dnsFailure
        : dnsFailure as TunnelDnsValidationException?,
    androidAppNames: androidAppNames ?? this.androidAppNames,
    connection: connection ?? this.connection,
    appleCapabilities: identical(appleCapabilities, _notProvided)
        ? this.appleCapabilities
        : appleCapabilities as AppleVpnCapabilities?,
    appleCapabilitiesLoading:
        appleCapabilitiesLoading ?? this.appleCapabilitiesLoading,
    apnsPresetApplicable: identical(apnsPresetApplicable, _notProvided)
        ? this.apnsPresetApplicable
        : apnsPresetApplicable as bool?,
    apnsPresetChecking: apnsPresetChecking ?? this.apnsPresetChecking,
    interfaces: interfaces ?? this.interfaces,
    interfacesLoading: interfacesLoading ?? this.interfacesLoading,
    interfacesFailed: interfacesFailed ?? this.interfacesFailed,
    appleSystemExtension: identical(appleSystemExtension, _notProvided)
        ? this.appleSystemExtension
        : appleSystemExtension as bool?,
    appleVpnRemovalLoading:
        appleVpnRemovalLoading ?? this.appleVpnRemovalLoading,
    appleVpnRemovalBusy: appleVpnRemovalBusy ?? this.appleVpnRemovalBusy,
    appleVpnRemovalError: identical(appleVpnRemovalError, _notProvided)
        ? this.appleVpnRemovalError
        : appleVpnRemovalError as String?,
    appleVpnRemovalRestartRequired:
        appleVpnRemovalRestartRequired ?? this.appleVpnRemovalRestartRequired,
    systemProxySupported: systemProxySupported ?? this.systemProxySupported,
    systemProxyLoading: systemProxyLoading ?? this.systemProxyLoading,
  );
}

class PolicyEditorController extends PageCubit<PolicyEditorPageState> {
  final PolicyEditorService service;
  final AppleVpnRemovalService appleVpnRemoval;
  final _dnsFocusNodes = <TunnelDnsField, FocusNode>{};
  final _dnsTouched = <TunnelDnsField>{};
  bool _dnsSubmitted = false;
  int _apnsPresetCheck = 0;
  bool? _apnsPresetPageVisible;

  PolicyEditorController({
    PolicyEditorDraft? draft,
    PolicyEditorService? service,
    AppleVpnRemovalService? appleVpnRemoval,
  }) : this._(draft, service ?? PolicyEditorService(), appleVpnRemoval);

  PolicyEditorController._(
    PolicyEditorDraft? draft,
    this.service,
    AppleVpnRemovalService? appleVpnRemoval,
  ) : appleVpnRemoval =
          appleVpnRemoval ??
          AppleVpnRemovalService(coordinator: service.coordinator),
      super(
        PolicyEditorPageState(
          draft: draft?.copy(),
          connection: service.coordinator.state.value,
          appleSystemExtension: service.platform == ConnectionPlatform.ios
              ? false
              : null,
        ),
      ) {
    service.coordinator.state.addListener(_connectionChanged);
  }

  ConnectionPlatform get platform => service.platform;
  bool get supportsWindowsSystemVpn => service.supportsWindowsSystemVpn;
  bool get supportsProxy => service.supportsProxy;
  bool get proxyMode => supportsProxy && value['captureMode'] == 'proxy';
  bool get activeProxy => state.connection.runtime?.isProxy ?? proxyMode;

  Future<void> loadProxyCapability() async {
    if (!supportsProxy ||
        state.systemProxyLoading ||
        state.systemProxySupported != null) {
      return;
    }
    emit(state.copyWith(systemProxyLoading: true));
    try {
      final capability = await service.proxyCapability();
      if (isPageActive) {
        emit(state.copyWith(systemProxySupported: capability.supported));
      }
    } catch (_) {
      if (isPageActive) emit(state.copyWith(systemProxySupported: false));
    } finally {
      if (isPageActive) emit(state.copyWith(systemProxyLoading: false));
    }
  }

  PolicyEditorDraft? get draft => state.draft;
  bool get busy => state.busy;
  String? get error => state.error;
  bool get connected => state.connection.phase == ConnectionPhase.connected;
  bool get blocked => state.busy || state.appleVpnRemovalBusy;
  bool get supportsAppleVpnRemoval =>
      platform == ConnectionPlatform.ios ||
      platform == ConnectionPlatform.macos;
  bool get runtimeBusy => state.connection.busy;
  Map<String, dynamic> get value => state.draft!.policy;
  Map<String, dynamic> group(String key) => value[key] as Map<String, dynamic>;
  bool get apnsPresetEnabled =>
      platform == ConnectionPlatform.ios &&
      draft != null &&
      group('apple')['apnsProxyPreset'] == true;
  bool get canEnableApnsPreset =>
      state.appleCapabilities?.serviceExclusions == true &&
      state.apnsPresetApplicable == true;
  bool get apnsPresetApplied =>
      connected && state.connection.runtime?.apnsProxyPresetApplied == true;
  bool get apnsPresetManagesSettings =>
      apnsPresetEnabled && (canEnableApnsPreset || apnsPresetApplied);
  bool get effectiveIpv6 =>
      apnsPresetManagesSettings || value['ipv6Enabled'] == true;
  bool get apnsPresetDisconnectsOnCellular =>
      apnsPresetManagesSettings &&
      group('apple')['alwaysOn'] != true &&
      group('apple')['onDemandEnabled'] == true &&
      group('apple')['cellularAction'] == 'disconnect';
  List<String> strings(String groupName, String key) =>
      List<String>.unmodifiable(
        List<String>.from(group(groupName)[key] as List),
      );

  String androidAppName(String packageName) =>
      state.androidAppNames[packageName] ?? packageName;

  FocusNode dnsFocusNode(TunnelDnsField field) =>
      _dnsFocusNodes.putIfAbsent(field, () {
        final node = FocusNode(debugLabel: 'Tunnel DNS ${field.name}');
        node.addListener(() {
          if (!node.hasFocus && isPageActive && !blocked && draft != null) {
            _dnsTouched.add(field);
            emit(state.copyWith(dnsFailure: _visibleDnsFailure(value)));
          }
        });
        return node;
      });

  String? dnsErrorText(AppLocalizations l, TunnelDnsField field) {
    if (state.dnsFailure?.field != field) return null;
    return switch (field) {
      TunnelDnsField.ipv4 => l.tunnelDnsIpv4Invalid,
      TunnelDnsField.ipv6 => l.tunnelDnsIpv6Invalid,
      TunnelDnsField.serverName => l.tunnelDnsServerNameRequired,
    };
  }

  TunnelDnsValidationException? _visibleDnsFailure(
    Map<String, dynamic> policy,
  ) {
    if (!_dnsSubmitted && _dnsTouched.isEmpty) return null;
    try {
      final base = PlatformPolicy.fromJson(policy);
      final effective = canEnableApnsPreset && base.appleApnsProxyPreset
          ? base.withApnsProxyPresetApplied()
          : base;
      effective.validateDns(platform, windowsMode: service.windowsMode);
    } on TunnelDnsValidationException catch (error) {
      if (_dnsSubmitted || _dnsTouched.contains(error.field)) return error;
    } on FormatException {
      // Other policy errors keep their existing page-level save feedback.
    }
    return null;
  }

  void _revealDns(TunnelDnsField field) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isPageActive || state.dnsFailure?.field != field) return;
      final node = _dnsFocusNodes[field];
      final fieldContext = node?.context;
      if (node == null ||
          fieldContext == null ||
          !fieldContext.mounted ||
          ModalRoute.of(fieldContext)?.isCurrent == false) {
        return;
      }
      node.requestFocus();
      Scrollable.ensureVisible(
        fieldContext,
        alignment: .5,
        duration: const Duration(milliseconds: 120),
      );
    });
  }

  Future<void> loadAndroidAppNames() async {
    try {
      final apps = await AppHostApi().getInstalledApps();
      if (!isPageActive) return;
      emit(
        state.copyWith(
          androidAppNames: {
            for (final app in apps)
              if (app.name.isNotEmpty) app.packageName: app.name,
          },
        ),
      );
    } catch (error) {
      emit(state.copyWith(error: failureDetails(error)));
    }
  }

  Future<void> load(BuildContext context) => _loadDraft(context, service.load);

  Future<void> _loadDraft(
    BuildContext context,
    Future<PolicyEditorDraft?> Function() read, {
    TunnelDestination? destination,
  }) async {
    if (state.appleVpnRemovalBusy) return;
    _dnsTouched.clear();
    _dnsSubmitted = false;
    emit(
      state.copyWith(
        busy: true,
        error: null,
        dnsFailure: null,
        loadingDestination: destination,
      ),
    );
    try {
      final loaded = await read();
      if (loaded != null) {
        emit(state.copyWith(draft: loaded));
        unawaited(refreshApnsPresetApplicability());
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
      emit(state.copyWith(busy: false, loadingDestination: null));
    }
  }

  Future<void> readAppleCapabilities({bool reportError = false}) async {
    if (state.appleCapabilitiesLoading) return;
    emit(
      state.copyWith(
        appleCapabilitiesLoading: true,
        error: reportError ? null : state.error,
      ),
    );
    try {
      final capabilities = await AppHostApi().appleVpnCapabilities();
      emit(state.copyWith(appleCapabilities: capabilities));
    } catch (error) {
      emit(state.copyWith(appleCapabilities: null));
      if (reportError) emit(state.copyWith(error: failureDetails(error)));
    } finally {
      emit(state.copyWith(appleCapabilitiesLoading: false));
    }
    await refreshApnsPresetApplicability();
  }

  void apnsPresetPageVisibilityChanged(BuildContext context, bool visible) {
    final returned = _apnsPresetPageVisible == false && visible;
    _apnsPresetPageVisible = visible;
    if (platform != ConnectionPlatform.ios || !visible || !isPageActive) return;
    if (state.appleCapabilities == null && !blocked && !returned) {
      unawaited(readAppleCapabilities());
    } else if (returned &&
        !blocked &&
        !runtimeBusy &&
        state.appleCapabilities?.serviceExclusions == true) {
      if (draft?.hasChanges == false) {
        unawaited(load(context));
      } else {
        unawaited(refreshApnsPresetApplicability());
      }
    }
  }

  Future<void> refreshApnsPresetApplicability() async {
    final original = draft?.original;
    if (platform != ConnectionPlatform.ios ||
        original == null ||
        state.appleCapabilities?.serviceExclusions != true ||
        !isPageActive) {
      return;
    }
    final check = ++_apnsPresetCheck;
    emit(state.copyWith(apnsPresetChecking: true));
    bool? applicable;
    try {
      applicable = await service.apnsProxyPresetApplicable(original);
    } catch (_) {
      // Leave the check retryable without changing the manual preferences.
    }
    if (isPageActive && check == _apnsPresetCheck) {
      emit(
        state.copyWith(
          apnsPresetApplicable: applicable,
          apnsPresetChecking: false,
        ),
      );
    }
  }

  Future<void> toggleApnsProxyPreset(
    BuildContext context,
    bool enabled, {
    bool saveImmediately = false,
  }) async {
    final current = draft;
    if (platform != ConnectionPlatform.ios ||
        current == null ||
        blocked ||
        runtimeBusy ||
        enabled == apnsPresetEnabled ||
        enabled && !canEnableApnsPreset) {
      return;
    }
    update('apnsProxyPreset', enabled, section: 'apple');
    if (saveImmediately && !current.hasChanges) {
      final saved = await save(context, pop: false);
      if (!saved && isPageActive) emit(state.copyWith(draft: current));
    }
  }

  Future<void> loadAppleVpnRemoval(BuildContext context) async {
    if (!supportsAppleVpnRemoval ||
        state.appleSystemExtension != null ||
        state.appleVpnRemovalLoading) {
      return;
    }
    emit(
      state.copyWith(appleVpnRemovalLoading: true, appleVpnRemovalError: null),
    );
    try {
      final systemExtension = await appleVpnRemoval.useSystemExtension();
      emit(state.copyWith(appleSystemExtension: systemExtension));
    } catch (error) {
      if (context.mounted) {
        final l = AppLocalizations.of(context)!;
        emit(
          state.copyWith(
            appleVpnRemovalError: appFailureMessage(
              l,
              error,
              operation: l.tunnelVpnRemovalEditionFailed,
            ),
          ),
        );
      }
    } finally {
      emit(state.copyWith(appleVpnRemovalLoading: false));
    }
  }

  Future<void> removeAppleVpn(BuildContext context) async {
    final systemExtension = state.appleSystemExtension;
    if (!supportsAppleVpnRemoval ||
        systemExtension == null ||
        blocked ||
        runtimeBusy ||
        state.appleVpnRemovalRestartRequired) {
      return;
    }
    final l = AppLocalizations.of(context)!;
    final label = systemExtension
        ? l.tunnelUninstallSystemExtension
        : l.tunnelDeleteVpnConfiguration;
    emit(state.copyWith(appleVpnRemovalBusy: true));
    try {
      if (!await AppConfirmationDialog(
            title: label,
            content: systemExtension
                ? l.tunnelUninstallSystemExtensionConfirmation
                : l.tunnelDeleteVpnConfigurationConfirmation,
            cancelLabel: l.prototypeCancel,
            confirmLabel: label,
            destructive: true,
            barrierDismissible: false,
          ).show(context) ||
          !context.mounted ||
          !isPageActive) {
        return;
      }
      emit(state.copyWith(appleVpnRemovalError: null));
      final result = await appleVpnRemoval.remove();
      final restartRequired = result == AppleVpnRemovalResult.restartRequired;
      emit(state.copyWith(appleVpnRemovalRestartRequired: restartRequired));
      if (context.mounted) {
        ContextAlert.showToast(
          context,
          restartRequired
              ? l.tunnelSystemExtensionRestartRequired
              : systemExtension
              ? l.tunnelSystemExtensionRemoved
              : l.tunnelVpnConfigurationRemoved,
        );
      }
    } catch (error) {
      emit(
        state.copyWith(
          appleVpnRemovalError: appFailureMessage(
            l,
            error,
            operation: l.tunnelVpnRemovalFailed,
          ),
        ),
      );
    } finally {
      emit(state.copyWith(appleVpnRemovalBusy: false));
    }
  }

  void update(String key, Object value, {String? section}) {
    final current = state.draft;
    if (blocked || current == null) {
      return;
    }
    final next = current.copy();
    final target = section == null
        ? next.policy
        : next.policy[section] as Map<String, dynamic>;
    target[key] = value;
    final dnsChanged =
        section == null &&
            const {
              'dnsIpv4Address',
              'dnsIpv6Address',
              'dnsServerName',
              'ipv6Enabled',
            }.contains(key) ||
        section == 'apple' && key == 'dnsOverTls';
    final dnsFailure = dnsChanged
        ? _visibleDnsFailure(next.policy)
        : state.dnsFailure;
    final failingKey = switch (state.dnsFailure?.field) {
      TunnelDnsField.ipv4 => 'dnsIpv4Address',
      TunnelDnsField.ipv6 => 'dnsIpv6Address',
      TunnelDnsField.serverName => 'dnsServerName',
      null => null,
    };
    final sameDnsFailure =
        failingKey != null &&
        dnsFailure?.field == state.dnsFailure?.field &&
        current.policy[failingKey] == next.policy[failingKey];
    emit(
      state.copyWith(
        draft: next,
        error: sameDnsFailure ? state.error : null,
        dnsFailure: dnsFailure,
      ),
    );
  }

  bool get emptyIncluded =>
      draft != null &&
      platform == ConnectionPlatform.android &&
      group('android')['appScope'] == 'included' &&
      strings('android', 'includedAppPackageNames').isEmpty;

  bool get ipv6Conflict =>
      draft != null &&
      supportsWindowsSystemVpn &&
      value['ipv6Enabled'] == false &&
      strings('windows', 'excludedCidrs').any((value) => value.contains(':'));

  bool get wifiConflict {
    if (draft == null) {
      return false;
    }
    final disconnect = strings('apple', 'disconnectWifiSsids').toSet();
    return strings(
      'apple',
      'connectWifiSsids',
    ).any((name) => name.trim().isNotEmpty && disconnect.contains(name));
  }

  String? validationHint(AppLocalizations l) {
    if (proxyMode) {
      final port = value['proxyPort'] as int;
      if (port < 1024 || port > 65535) return l.localApiPortInvalid;
      if (value['lanProxy']['enabled'] == true &&
          value['lanProxy']['port'] == port) {
        return l.desktopProxyPortConflict;
      }
      return null;
    }
    if (ipv6Conflict) {
      return l.prototypeIpv6BypassConflict;
    }
    if (wifiConflict) {
      return l.prototypeWifiActionConflict;
    }
    if (service.requiresInterface &&
        (value['xrayOutboundInterfaceName'] as String).trim().isEmpty) {
      return l.prototypeChooseInterfaceBeforeSaving;
    }
    return null;
  }

  String saveLabel(AppLocalizations l) => state.connection.canDisconnect
      ? emptyIncluded
            ? l.prototypeDisconnectVpn
            : l.prototypeSaveAndReconnect
      : l.prototypeSave;

  Future<bool> save(BuildContext context, {bool pop = true}) async {
    final current = state.draft;
    if (blocked || runtimeBusy || current == null) {
      return false;
    }
    final l = AppLocalizations.of(context)!;
    final hint = validationHint(l);
    if (hint != null) {
      emit(state.copyWith(error: hint));
      return false;
    }
    _dnsSubmitted = true;
    emit(state.copyWith(busy: true, error: null, dnsFailure: null));
    try {
      final saved = await service.save(
        draft: current,
        confirm: (disconnect) => confirmSave(context, disconnect),
      );
      if (!saved &&
          platform == ConnectionPlatform.ios &&
          current.original.policy.appleApnsProxyPreset != apnsPresetEnabled) {
        final restored = current.copy();
        restored.policy['apple']['apnsProxyPreset'] =
            current.original.policy.appleApnsProxyPreset;
        emit(state.copyWith(draft: restored));
      }
      if (saved && isPageActive) {
        if (context.mounted) {
          ContextAlert.showToast(context, l.prototypeSettingsSaved);
        }
        if (pop &&
            context.mounted &&
            ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop(true);
        } else if (!pop) {
          emit(state.copyWith(draft: await service.load()));
          unawaited(refreshApnsPresetApplicability());
        }
      }
      return saved;
    } catch (error) {
      emit(
        state.copyWith(
          error: connectionFailureMessage(
            l,
            error: error,
            operation: l.buttonSaveFailed,
          ),
          dnsFailure: error is TunnelDnsValidationException ? error : null,
        ),
      );
      if (error is TunnelDnsValidationException) _revealDns(error.field);
      return false;
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  Future<bool> confirmSave(BuildContext context, bool disconnect) {
    if (!context.mounted) return Future.value(false);
    final l = AppLocalizations.of(context)!;
    final presetChanged =
        platform == ConnectionPlatform.ios &&
        draft?.original.policy.appleApnsProxyPreset != apnsPresetEnabled;
    return ContextAlert.showConfirmDialog(
      context,
      title: l.prototypeApplyChange,
      content: disconnect
          ? '${l.prototypeNoAppsSelected}. ${l.prototypeDisconnectVpn}.'
          : l.prototypeReconnectNotice,
      confirmLabel: disconnect
          ? l.prototypeDisconnectVpn
          : presetChanged
          ? apnsPresetEnabled
                ? l.tunnelApnsPresetEnableReconnect
                : l.tunnelApnsPresetDisableReconnect
          : l.prototypeSaveAndReconnect,
    );
  }

  Future<void> openChild(BuildContext context, OpenPolicyChild open) async {
    if (blocked || draft == null) {
      return;
    }
    final saved = await open(context, draft!.copy());
    if (saved == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> openPlatform(
    BuildContext context,
    TunnelDestination destination,
    OpenTunnelPage open,
  ) async {
    final current = draft;
    if (blocked || current == null) {
      return;
    }
    // The root stays mounted while other branches change the connection plan.
    if (!current.hasChanges) {
      final navigation = GoRouter.maybeOf(context)?.routeInformationProvider;
      final initialRequest = navigation?.value;
      final visibility = TickerMode.getValuesNotifier(context);
      final route = ModalRoute.of(context);
      final cancelled = Completer<PolicyEditorDraft?>();
      // A branch switch is announced before the old route becomes offstage.
      void cancelIfLeft() {
        if (!cancelled.isCompleted &&
            (!visibility.value.enabled ||
                !identical(navigation?.value, initialRequest))) {
          cancelled.complete(null);
        }
      }

      navigation?.addListener(cancelIfLeft);
      visibility.addListener(cancelIfLeft);
      try {
        await _loadDraft(
          context,
          () => Future.any([service.load(), cancelled.future]),
          destination: destination,
        );
        if (!context.mounted ||
            !isPageActive ||
            cancelled.isCompleted ||
            error != null ||
            !visibility.value.enabled ||
            route?.isCurrent == false) {
          return;
        }
      } finally {
        visibility.removeListener(cancelIfLeft);
        navigation?.removeListener(cancelIfLeft);
      }
    }
    final saved = await open(context, destination, draft!.copy());
    if (saved == true && context.mounted && isPageActive) {
      await load(context);
    }
  }

  Future<void> selectApps(BuildContext context, OpenAndroidApps open) async {
    if (blocked) {
      return;
    }
    final mode = group('android')['appScope'] as String;
    final key = mode == 'included'
        ? 'includedAppPackageNames'
        : 'excludedAppPackageNames';
    final selected = await open(context, mode, strings('android', key));
    if (isPageActive && selected != null) {
      update(key, selected, section: 'android');
    }
  }

  void cancel(BuildContext context) {
    Navigator.of(context).pop();
  }

  void restoreDefaults() {
    final current = state.draft;
    if (blocked || current == null) return;
    _dnsTouched.clear();
    _dnsSubmitted = false;
    emit(
      state.copyWith(
        draft: PolicyEditorDraft(
          current.original,
          PlatformPolicy.defaults().toJson(),
        ),
        error: null,
        dnsFailure: null,
      ),
    );
  }

  void _connectionChanged() {
    final before = state.connection;
    final after = service.coordinator.state.value;
    emit(state.copyWith(connection: after));
    if (!after.busy &&
        (before.phase != after.phase ||
            before.runtime?.identity != after.runtime?.identity)) {
      unawaited(refreshApnsPresetApplicability());
    }
  }

  @override
  void disposePageResources() {
    service.coordinator.state.removeListener(_connectionChanged);
    for (final node in _dnsFocusNodes.values) {
      node.dispose();
    }
  }
}
