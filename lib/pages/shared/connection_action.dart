import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/failure.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> runConnectionAction(
  BuildContext context,
  ConnectionCoordinator coordinator,
  Future<void> Function() action, {
  bool rethrowErrors = false,
}) async {
  try {
    await action();
    return true;
  } catch (error) {
    if (rethrowErrors) rethrow;
    if (!failureCancelled(error) &&
        connectionFailureReason(error) != 'cancelled' &&
        coordinator.state.value.issue != 'cancelled' &&
        context.mounted) {
      final l = AppLocalizations.of(context)!;
      final permission = error is ConnectionHostException
          ? error.permission
          : null;
      if (connectionFailureReason(error) == 'permissionRequired' &&
          permission?.kind == PlatformPermissionKind.macosSystemExtension &&
          permission?.state != PlatformPermissionState.failed) {
        await ContextAlert.showPermissionDialog(
          context,
          title: l.prototypeSystemApprovalRequired,
          message: l.systemExtensionApprovalHint,
          openSettings: () => launchUrl(
            Uri.parse('x-apple.systempreferences:'),
            mode: LaunchMode.externalApplication,
          ),
        );
      } else {
        ContextAlert.showToast(
          context,
          connectionFailureMessage(l, error: error),
        );
      }
    }
    return false;
  }
}

Future<ConnectionConfiguration?> applyConnectionChange(
  BuildContext context,
  ConnectionCoordinator coordinator,
  Map<String, dynamic> values, {
  required String Function(ConnectionSettings) label,
  Future<void> Function()? writeAssets,
  Future<void> Function()? validateAssets,
  bool rethrowErrors = false,
}) async {
  final current = await coordinator.configuration;
  final next = ConnectionConfiguration(
    connection: ConnectionSettings.fromJson({
      ...current.connection.toJson(),
      ...values,
    }),
    policy: current.policy,
  );
  if (next.encode() == current.encode() && writeAssets == null) return current;
  if (!context.mounted) return null;
  final reconnect = coordinator.state.value.phase == ConnectionPhase.connected;
  if (reconnect &&
      !await showApplyAndReconnectDialog(
        context,
        label: label(next.connection),
      )) {
    return null;
  }
  if (!context.mounted) return null;
  ConnectionConfiguration? saved;
  await runConnectionAction(context, coordinator, () async {
    await coordinator.apply(
      next,
      writeAssets: writeAssets,
      validateAssets: validateAssets,
      expectedConfiguration: current.encode(),
      allowReconnect: reconnect,
    );
    saved = await coordinator.configuration;
  }, rethrowErrors: rethrowErrors);
  return saved;
}
