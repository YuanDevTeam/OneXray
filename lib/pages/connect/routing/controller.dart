import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/connection_action.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/provider_mode.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/editor.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/failure.dart';

class RoutingPageState {
  final ConnectionConfiguration? configuration;
  final List<RoutingProfileData> profiles;
  final Map<int, RoutingConfiguration> profileConfigurations;
  final Map<int, Object> profileErrors;
  final bool completeConfiguration;
  final bool busy;
  final bool failed;
  final String? error;
  final Object? failure;

  const RoutingPageState({
    this.configuration,
    this.profiles = const [],
    this.profileConfigurations = const {},
    this.profileErrors = const {},
    this.completeConfiguration = false,
    this.busy = false,
    this.failed = false,
    this.error,
    this.failure,
  });
}

const _unchanged = Object();

class RoutingPageController extends PageCubit<RoutingPageState> {
  final AppDatabase db;
  final ConnectionCoordinator coordinator;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  int _revision = 0;
  int _loadRevision = 0, _configurationRevision = 0, _profilesRevision = 0;
  int _operationRevision = 0;
  final Future<List<RoutingProfileData>> Function()? readProfiles;

  RoutingPageController({
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
    this.readProfiles,
  }) : db = database ?? AppDatabase(),
       coordinator = coordinator ?? ConnectionCoordinator.instance,
       super(const RoutingPageState()) {
    this.coordinator.state.addListener(_runtimeChanged);
    load();
  }

  void _update({
    ConnectionConfiguration? configuration,
    List<RoutingProfileData>? profiles,
    Map<int, RoutingConfiguration>? profileConfigurations,
    Map<int, Object>? profileErrors,
    bool? completeConfiguration,
    bool? busy,
    bool? failed,
    Object? error = _unchanged,
    Object? failure = _unchanged,
  }) => emit(
    RoutingPageState(
      configuration: configuration ?? state.configuration,
      profiles: profiles ?? state.profiles,
      profileConfigurations:
          profileConfigurations ?? state.profileConfigurations,
      profileErrors: profileErrors ?? state.profileErrors,
      completeConfiguration:
          completeConfiguration ?? state.completeConfiguration,
      busy: busy ?? state.busy,
      failed: failed ?? state.failed,
      error: identical(error, _unchanged) ? state.error : error as String?,
      failure: identical(failure, _unchanged) ? state.failure : failure,
    ),
  );

  Future<void> load() async {
    final revision = ++_loadRevision;
    final configurationRevision = _configurationRevision;
    final profilesRevision = _profilesRevision;
    final operationRevision = _operationRevision;
    _update(failed: false, error: null, failure: null);
    try {
      final configuration = await coordinator.configuration;
      final rows = await (readProfiles?.call() ?? db.routingProfileDao.allRows);
      if (!isPageActive || revision != _loadRevision) return;
      if (operationRevision != _operationRevision) return;
      final acceptConfiguration =
          configurationRevision == _configurationRevision;
      final acceptProfiles = profilesRevision == _profilesRevision;
      if (acceptConfiguration) {
        _configurationRevision++;
        _update(configuration: configuration);
      }
      if (acceptProfiles) _receiveProfiles(rows);
      _update(failed: false, failure: null, error: null);
      await _readCompleteConfiguration();
      if (_subscriptions.isEmpty && isPageActive && revision == _loadRevision) {
        _subscriptions.add(
          db.connectionConfigDao.watch().listen(
            (row) {
              if (!isPageActive) return;
              try {
                final configuration = ConnectionConfiguration.fromJson(
                  jsonDecode(row.configurationJson) as Map<String, dynamic>,
                );
                _configurationRevision++;
                _update(configuration: configuration);
                unawaited(_readCompleteConfiguration());
              } catch (failure) {
                _update(failed: true, failure: failure);
              }
            },
            onError: (Object failure) =>
                _update(failed: true, failure: failure),
          ),
        );
        _subscriptions.add(
          db.routingProfileDao.allRowsStream.listen(
            (rows) {
              if (isPageActive) _receiveProfiles(rows);
            },
            onError: (Object failure) =>
                _update(failed: true, failure: failure),
          ),
        );
      }
    } catch (failure) {
      if (isPageActive &&
          revision == _loadRevision &&
          operationRevision == _operationRevision) {
        _update(failed: true, failure: failure);
      }
    }
  }

  void _receiveProfiles(List<RoutingProfileData> rows) {
    final configurations = <int, RoutingConfiguration>{};
    final errors = <int, Object>{};
    // One damaged document must not hide the other routes or its own actions.
    for (final row in rows) {
      try {
        configurations[row.id] = CustomRoutingService.readConfiguration(row);
      } catch (failure) {
        errors[row.id] = failure;
      }
    }
    _profilesRevision++;
    _update(
      profiles: List.unmodifiable(rows),
      profileConfigurations: Map.unmodifiable(configurations),
      profileErrors: Map.unmodifiable(errors),
    );
  }

  void _runtimeChanged() => unawaited(_readCompleteConfiguration());

  Future<void> _readCompleteConfiguration() async {
    final configuration = state.configuration;
    if (configuration == null) return;
    final revision = ++_revision;
    final configurationRevision = _configurationRevision;
    final operationRevision = _operationRevision;
    try {
      final complete =
          configuration.connection.expert ||
          await usesProviderConfiguration(
            db,
            configuration.connection,
            runtime: coordinator.state.value.runtime,
          );
      if (isPageActive &&
          revision == _revision &&
          configurationRevision == _configurationRevision &&
          operationRevision == _operationRevision) {
        _update(completeConfiguration: complete);
      }
    } catch (failure) {
      if (isPageActive &&
          revision == _revision &&
          configurationRevision == _configurationRevision &&
          operationRevision == _operationRevision) {
        _update(failed: true, failure: failure);
      }
    }
  }

  RoutingConfiguration? configurationFor(RoutingProfileData row) =>
      state.profileConfigurations[row.id];

  bool canUseProfile(int? id) =>
      id != null &&
      state.profiles.any((row) => row.id == id) &&
      state.profileConfigurations.containsKey(id) &&
      !state.profileErrors.containsKey(id);

  Future<void> _validateProfile(int id) async {
    final row = await db.routingProfileDao.searchRow(id);
    if (row == null) throw const CustomRoutingEditorException('missing');
    CustomRoutingService.readConfiguration(row);
  }

  Future<void> select(BuildContext context, TrafficMode mode, {int? id}) async {
    if (state.busy) return;
    if (mode == TrafficMode.custom && !canUseProfile(id)) {
      _update(
        error: state.profileErrors[id] == null
            ? AppLocalizations.of(context)!.prototypeTemporarilyUnavailable
            : appFailureMessage(
                AppLocalizations.of(context)!,
                state.profileErrors[id],
              ),
      );
      return;
    }
    final operation = ++_operationRevision;
    _update(busy: true, error: null);
    try {
      final current = await coordinator.configuration;
      final complete =
          current.connection.expert ||
          await usesProviderConfiguration(
            db,
            current.connection,
            runtime: coordinator.state.value.runtime,
          );
      if (!context.mounted ||
          !isPageActive ||
          operation != _operationRevision) {
        return;
      }
      final saved = await applyConnectionChange(
        context,
        coordinator,
        {
          'trafficMode': mode.name,
          'customId': mode == TrafficMode.custom ? id : null,
        },
        affectsRuntime: !complete,
        validateAssets: mode == TrafficMode.custom
            ? () => _validateProfile(id!)
            : null,
        label: (settings) {
          final l = AppLocalizations.of(context)!;
          if (mode == TrafficMode.smart) return l.prototypeSmartRouting;
          if (mode == TrafficMode.allVpn) return l.prototypeAllViaVpn;
          return state.profiles.firstWhere((row) => row.id == id).name;
        },
      );
      if (saved != null && isPageActive && operation == _operationRevision) {
        _configurationRevision++;
        _update(configuration: saved);
      }
    } catch (failure) {
      if (context.mounted && isPageActive && operation == _operationRevision) {
        _update(
          error: appFailureMessage(AppLocalizations.of(context)!, failure),
        );
      }
    } finally {
      if (operation == _operationRevision) {
        _update(busy: false);
        if (isPageActive) unawaited(_readCompleteConfiguration());
      }
    }
  }

  Future<void> edit(BuildContext context, [RoutingProfileData? row]) async {
    if (state.busy) return;
    final advanced =
        row?.advanced ?? await showCustomRoutingModeDialog(context);
    if (advanced == null || !context.mounted) return;
    await context.pushScoped(
      advanced
          ? AppPageDestination.advancedRouting
          : AppPageDestination.customRouting,
      extra: row?.id,
    );
  }

  Future<void> delete(BuildContext context, RoutingProfileData row) async {
    if (state.busy) return;
    final l = AppLocalizations.of(context)!;
    final operation = ++_operationRevision;
    _update(busy: true, error: null);
    try {
      await CustomRoutingEditorService(
        database: db,
        coordinator: coordinator,
      ).delete(
        row,
        confirm: (selected, reconnect) => context.mounted
            ? ContextAlert.showConfirmDialog(
                context,
                title: l.prototypeDeleteName(row.name),
                content: reconnect
                    ? l.prototypeDeletingRouteReconnectNotice
                    : selected
                    ? l.prototypeDeletedRouteSmartNotice
                    : l.prototypeRemoveRouteNotice,
                confirmLabel: reconnect
                    ? l.prototypeSwitchAndReconnect
                    : selected
                    ? l.prototypeDeleteAndUseSmartRouting
                    : l.prototypeDeleteRoute,
              )
            : Future.value(false),
      );
    } catch (failure) {
      if (isPageActive && operation == _operationRevision) {
        _update(error: appFailureMessage(l, failure));
      }
    } finally {
      if (operation == _operationRevision) _update(busy: false);
    }
  }

  @override
  Future<void> disposePageResources() async {
    _revision++;
    _loadRevision++;
    _operationRevision++;
    coordinator.state.removeListener(_runtimeChanged);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
