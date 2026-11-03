import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/connect/platform_requirements.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/shared/failure.dart';

String connectionFailureReason(
  Object error, {
  String fallback = 'changeFailed',
}) => switch (error) {
  ConnectionResolutionException() => error.reason.name,
  ConnectionHostException() => error.reason,
  ConnectionPlatformRequirementException() => error.reason,
  AppFailure() => error.code,
  _ => fallback,
};

/// Shared by the connection status, action toasts and external-entry notices.
/// Counts come from resolution itself, never a second UI/database check.
String connectionFailureMessage(
  AppLocalizations l, {
  Object? error,
  String? issue,
  PlatformPermissionResult? permission,
  String? operation,
}) {
  issue ??= error == null ? null : connectionFailureReason(error);
  if (error is ConnectionHostException) permission ??= error.permission;
  final message = switch (issue) {
    'selectionUnavailable' =>
      '${l.prototypeNoAvailableEntries} · ${l.prototypeAddServers}',
    'insufficientCandidates' =>
      error is ConnectionResolutionException && error.requiredCount > 0
          ? '${l.prototypeNotEnoughServers} (${error.availableCount}/${error.requiredCount})'
          : l.prototypeNotEnoughServers,
    'finalExitUnavailable' =>
      '${l.prototypeVpnFinalExit} · ${l.prototypeNoAvailableEntries}',
    'selfReference' => l.prototypeFinalExitEntryConflict,
    'invalidSettings' => l.prototypeChooseNamedRoute,
    'permissionRequired' => switch (permission?.kind) {
      PlatformPermissionKind.androidLocalNetwork =>
        l.prototypeAllowLocalNetworkHint,
      PlatformPermissionKind.macosSystemExtension =>
        l.prototypeSystemApprovalRequired,
      _ => l.prototypeVpnPermissionRequired,
    },
    'interfaceRequired' ||
    'interfaceUnavailable' => l.prototypeChooseInterfaceNotice,
    'readFailed' ||
    'runtimeUnavailable' ||
    'nativeStatusFailed' => l.prototypeTemporarilyUnavailable,
    _ => nativeOperationFailureTitle(l, issue),
  };
  if (message == null) return appFailureMessage(l, error, operation: operation);
  return appFailureMessage(
    l,
    error is AppFailure ? error.cause : permission?.message,
    operation: message,
  );
}

/// Expected selection failures can be handled later; do not steal desktop focus.
bool connectionFailureNeedsWindow(Object error) =>
    switch (connectionFailureReason(error)) {
      'selectionUnavailable' ||
      'insufficientCandidates' ||
      'cancelled' => false,
      _ => true,
    };
