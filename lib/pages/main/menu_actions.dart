import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/servers/subscription/format_confirmation.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/connection_action.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/failure.dart';
import 'package:onexray/service/launch/app_startup.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/subscription/failure.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/shared/menu/short_cut/service.dart';
import 'package:onexray/service/shared/notification/service.dart';
import 'package:onexray/core/tools/logger.dart';

Future<void> handleMobileQuickAction(
  BuildContext context,
  ShortCutAction action,
) async {
  final coordinator = ConnectionCoordinator.instance;
  try {
    switch (action) {
      case ShortCutAction.startVpn:
        context.goPrimaryRoot(AppPrimaryDestination.connect);
        await coordinator.connect();
      case ShortCutAction.stopVpn:
        context.goPrimaryRoot(AppPrimaryDestination.connect);
        await coordinator.disconnect();
      case ShortCutAction.chooseConfiguration:
        final configuration = await coordinator.configuration;
        if (context.mounted) {
          context.goPrimaryRoot(
            configuration.connection.expert
                ? AppPrimaryDestination.connect
                : AppPrimaryDestination.servers,
          );
        }
      case ShortCutAction.updateSubscriptions:
        context.goPrimaryRoot(AppPrimaryDestination.servers);
        final results = await SubscriptionService().refreshAll(
          confirmOrdinary: (name) => confirmOrdinarySubscription(context, name),
        );
        if (context.mounted) {
          final message = subscriptionRefreshMessage(
            AppLocalizations.of(context)!,
            results,
          );
          if (message.isNotEmpty) ContextAlert.showToast(context, message);
        }
    }
  } catch (error) {
    if (failureCancelled(error) ||
        connectionFailureReason(error) == 'cancelled') {
      return;
    }
    if (!context.mounted) return;
    final l = AppLocalizations.of(context)!;
    final connectionAction =
        action == ShortCutAction.startVpn || action == ShortCutAction.stopVpn;
    final message = connectionAction
        ? connectionFailureMessage(l, error: error)
        : appFailureMessage(l, error);
    if (connectionAction) {
      try {
        await NotificationService().pushNotification(message);
      } catch (notificationError, stackTrace) {
        ygLogger(
          'Quick action notification failed: $notificationError\n$stackTrace',
        );
      }
    }
    if (context.mounted) ContextAlert.showToast(context, message);
  }
}

/// Reuses the normal page's confirmation and commit implementation. Only an
/// actual reconnect confirmation needs to bring the desktop window forward.
Future<void> applyTrayConfiguration(
  BuildContext context,
  Map<String, dynamic> values,
  String label,
  Future<void> Function() validate,
) async {
  final coordinator = ConnectionCoordinator.instance;
  await coordinator.refresh();
  if (coordinator.state.value.phase == ConnectionPhase.connected) {
    await AppStartupService().showMainWindow();
  }
  if (!context.mounted) return;
  await applyConnectionChange(
    context,
    coordinator,
    values,
    label: (_) => label,
    validateAssets: validate,
    rethrowErrors: true,
  );
}

Future<bool> confirmTraySubscriptionFormat(
  BuildContext context,
  String name,
) async {
  await AppStartupService().showMainWindow();
  if (!context.mounted) return false;
  return confirmOrdinarySubscription(context, name);
}
