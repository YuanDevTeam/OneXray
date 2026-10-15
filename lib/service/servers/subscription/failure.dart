import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/shared/failure.dart';

String subscriptionFailureMessage(
  AppLocalizations l,
  SubscriptionUpdateResult status, {
  Object? error,
  bool updating = false,
}) {
  if (failureCancelled(error)) return l.buttonCancel;
  return appFailureMessage(
    l,
    error ??
        (status == SubscriptionUpdateResult.notFound
            ? const AppFailure(FailureCategory.conflict, 'notFound')
            : null),
    operation: switch (status) {
      SubscriptionUpdateResult.nameRequired => l.validationNameRequired,
      SubscriptionUpdateResult.urlRequired => l.validationUrlRequired,
      SubscriptionUpdateResult.urlInvalid => l.validationUrlInvalid,
      SubscriptionUpdateResult.userAgentInvalid =>
        l.subscriptionUserAgentInvalid,
      SubscriptionUpdateResult.duplicateUrl => l.validationUrlDuplicate,
      SubscriptionUpdateResult.incompleteAgeKeys =>
        l.prototypeAgeBothKeysRequired,
      SubscriptionUpdateResult.downloadFailed => l.subscriptionDownloadFailed,
      SubscriptionUpdateResult.hwidRequired => l.subscriptionHwidRequired,
      SubscriptionUpdateResult.hwidLimitReached =>
        l.subscriptionHwidLimitReached,
      SubscriptionUpdateResult.hwidRejected => l.subscriptionHwidRejected,
      SubscriptionUpdateResult.remnawaveFormatMismatch =>
        l.subscriptionRemnawaveFormatTitle,
      SubscriptionUpdateResult.invalidAgeSecretKey =>
        l.subscriptionInvalidAgeSecretKey,
      SubscriptionUpdateResult.missingAgeSecretKey =>
        l.subscriptionMissingAgeSecretKey,
      SubscriptionUpdateResult.decryptFailed => l.subscriptionDecryptFailed,
      SubscriptionUpdateResult.contentTooLarge =>
        l.subscriptionDecryptedTooLarge,
      SubscriptionUpdateResult.invalidContent =>
        updating
            ? l.prototypeNoAvailableEntries
            : l.prototypeSubscriptionNotAdded,
      SubscriptionUpdateResult.notFound => l.prototypeTemporarilyUnavailable,
      _ => l.buttonSaveFailed,
    },
  );
}

/// The same result feedback is used by mobile quick actions and the tray.
String subscriptionRefreshMessage(
  AppLocalizations l,
  Map<SubscriptionData, SubscriptionRefreshResult> results,
) {
  if (results.isEmpty) return l.prototypeNoMatchingSubscriptions;
  return [
    for (final entry in results.entries)
      if (!entry.value.superseded && !failureCancelled(entry.value.error))
        '${entry.key.name}: ${entry.value.success ? l.prototypeUsableNodes(entry.value.count) : subscriptionFailureMessage(l, entry.value.status, error: entry.value.error, updating: true)}',
  ].join('\n');
}
