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
  final bool completeConfiguration;
  final bool busy;
  final bool failed;
  final String? error;

  const RoutingPageState({
    this.configuration,
    this.profiles = const [],
    this.completeConfiguration = false,
    this.busy = false,
    this.failed = false,
    this.error,
  });
}

class RoutingPageController extends PageCubit<RoutingPageState> {
  final AppDatabase db;
  final ConnectionCoordinator coordinator;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  int _revision = 0;

  RoutingPageController({
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
  }) : db = database ?? AppDatabase(),
       coordinator = coordinator ?? ConnectionCoordinator.instance,
       super(const RoutingPageState()) {
    this.coordinator.state.addListener(_runtimeChanged);
    load();
  }

  void _update({
    ConnectionConfiguration? configuration,
    List<RoutingProfileData>? profiles,
    bool? completeConfiguration,
    bool? busy,
    bool? failed,
    String? error,
  }) => emit(
    RoutingPageState(
      configuration: configuration ?? state.configuration,
      profiles: profiles ?? state.profiles,
      completeConfiguration:
          completeConfiguration ?? state.completeConfiguration,
      busy: busy ?? state.busy,
      failed: failed ?? state.failed,
      error: error,
    ),
  );

  Future<void> load() async {
    _update(failed: false);
    try {
      final configuration = await coordinator.configuration;
      final rows = await db.routingProfileDao.allRows;
      for (final row in rows) {
        CustomRoutingService.readConfiguration(row);
      }
      if (!isPageActive) return;
      _update(configuration: configuration, profiles: rows);
      await _readCompleteConfiguration();
      if (_subscriptions.isEmpty && isPageActive) {
        _subscriptions.add(
          db.connectionConfigDao.watch().listen((row) {
            try {
              _update(
                configuration: ConnectionConfiguration.fromJson(
                  jsonDecode(row.configurationJson) as Map<String, dynamic>,
                ),
              );
              unawaited(_readCompleteConfiguration());
            } catch (_) {
              _update(failed: true);
            }
          }, onError: (_) => _update(failed: true)),
        );
        _subscriptions.add(
          db.routingProfileDao.allRowsStream.listen((rows) {
            try {
              for (final row in rows) {
                CustomRoutingService.readConfiguration(row);
              }
              _update(profiles: rows);
            } catch (_) {
              _update(failed: true);
            }
          }, onError: (_) => _update(failed: true)),
        );
      }
    } catch (_) {
      _update(failed: true);
    }
  }

  void _runtimeChanged() => unawaited(_readCompleteConfiguration());

  Future<void> _readCompleteConfiguration() async {
    final configuration = state.configuration;
    if (configuration == null) return;
    final revision = ++_revision;
    try {
      final complete =
          configuration.connection.expert ||
          await usesProviderConfiguration(
            db,
            configuration.connection,
            runtime: coordinator.state.value.runtime,
          );
      if (isPageActive && revision == _revision) {
        _update(completeConfiguration: complete);
      }
    } catch (_) {
      if (revision == _revision) _update(failed: true);
    }
  }

  RoutingConfiguration configurationFor(RoutingProfileData row) =>
      CustomRoutingService.readConfiguration(row);

  Future<void> select(BuildContext context, TrafficMode mode, {int? id}) async {
    if (state.busy) return;
    _update(busy: true);
    try {
      final current = await coordinator.configuration;
      final complete =
          current.connection.expert ||
          await usesProviderConfiguration(
            db,
            current.connection,
            runtime: coordinator.state.value.runtime,
          );
      if (!context.mounted || !isPageActive) return;
      await applyConnectionChange(
        context,
        coordinator,
        {
          'trafficMode': mode.name,
          'customId': mode == TrafficMode.custom ? id : null,
        },
        affectsRuntime: !complete,
        label: (settings) {
          final l = AppLocalizations.of(context)!;
          if (mode == TrafficMode.smart) return l.prototypeSmartRouting;
          if (mode == TrafficMode.allVpn) return l.prototypeAllViaVpn;
          return state.profiles.firstWhere((row) => row.id == id).name;
        },
      );
    } catch (failure) {
      if (context.mounted)
        _update(
          error: appFailureMessage(AppLocalizations.of(context)!, failure),
        );
    } finally {
      _update(busy: false);
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
    _update(busy: true);
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
      _update(error: appFailureMessage(l, failure));
    } finally {
      _update(busy: false);
    }
  }

  @override
  Future<void> disposePageResources() async {
    _revision++;
    coordinator.state.removeListener(_runtimeChanged);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
