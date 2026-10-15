import 'package:onexray/core/db/database/enum.dart';

final class SubscriptionInput {
  const SubscriptionInput({
    required this.name,
    required this.url,
    this.userAgent,
    this.ageSecretKey,
    this.agePublicKey,
    this.hwidEnabled = false,
    this.hwid,
    this.panel = SubscriptionPanel.generic,
    this.mode,
  });

  final String name;
  final String url;
  final String? userAgent;
  final String? ageSecretKey;
  final String? agePublicKey;
  final bool hwidEnabled;
  final String? hwid;
  final SubscriptionPanel panel;

  /// Null lets a new source choose its mode after the response is classified.
  /// Editing an existing source without a mode retains its stored mode.
  final SubscriptionMode? mode;

  SubscriptionInput withHwid(String value) => SubscriptionInput(
    name: name,
    url: url,
    userAgent: userAgent,
    ageSecretKey: ageSecretKey,
    agePublicKey: agePublicKey,
    hwidEnabled: hwidEnabled,
    hwid: value,
    panel: panel,
    mode: mode,
  );

  String? get normalizedUserAgent {
    final value = userAgent?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get normalizedAgeSecretKey {
    final value = ageSecretKey?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get normalizedAgePublicKey {
    final value = agePublicKey?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  bool get hasIncompleteAgeKeyPair =>
      (normalizedAgeSecretKey == null) != (normalizedAgePublicKey == null);

  SubscriptionAgeContext? get normalizedAgeContext {
    final secretKey = normalizedAgeSecretKey;
    final publicKey = normalizedAgePublicKey;
    if (secretKey == null || publicKey == null) {
      return null;
    }
    return SubscriptionAgeContext(secretKey: secretKey, publicKey: publicKey);
  }
}

final class SubscriptionAgeContext {
  const SubscriptionAgeContext({
    required this.secretKey,
    required this.publicKey,
  });

  final String secretKey;
  final String publicKey;
}

final class SubscriptionInsertResult {
  const SubscriptionInsertResult({
    required this.status,
    this.subId = 0,
    this.count = 0,
    this.error,
  });

  final SubscriptionUpdateResult status;
  final int subId;
  final int count;
  final Object? error;

  bool get success => status == SubscriptionUpdateResult.success && count > 0;
}

final class SubscriptionNodeReferences {
  const SubscriptionNodeReferences({
    this.runningIds = const {},
    this.fixedId,
    this.finalExitId,
  });

  final Set<int> runningIds;
  final int? fixedId;
  final int? finalExitId;

  Set<int> get protectedIds => {
    ...runningIds.where((id) => id > 0),
    if (fixedId != null && fixedId! > 0) fixedId!,
    if (finalExitId != null && finalExitId! > 0) finalExitId!,
  };
}

final class SubscriptionRefreshResult {
  const SubscriptionRefreshResult({
    required this.status,
    this.count = 0,
    this.superseded = false,
    this.error,
  });

  final SubscriptionUpdateResult status;
  final int count;
  final bool superseded;
  final Object? error;

  bool get success =>
      !superseded && status == SubscriptionUpdateResult.success && count > 0;
}

/// Warnings after a local mode edit; an unavailable cache never undoes it.
final class SubscriptionModeAvailability {
  const SubscriptionModeAvailability({
    required this.count,
    required this.selectedCompatible,
  });
  final int count;
  final bool selectedCompatible;
  bool get hasActiveCache => count > 0;
}

enum SubscriptionUpdateResult {
  success,
  nameRequired,
  urlRequired,
  urlInvalid,
  userAgentInvalid,
  duplicateUrl,
  incompleteAgeKeys,
  notFound,
  downloadFailed,
  hwidRequired,
  hwidLimitReached,
  hwidRejected,
  invalidContent,
  invalidAgeSecretKey,
  missingAgeSecretKey,
  decryptFailed,
  contentTooLarge,
  writeFailed,
}

abstract final class SubscriptionUrl {
  static bool sameOrigin(String first, String second) {
    final a = Uri.tryParse(normalize(first));
    final b = Uri.tryParse(normalize(second));
    return a != null &&
        b != null &&
        a.hasAuthority &&
        b.hasAuthority &&
        a.scheme == b.scheme &&
        a.host == b.host &&
        a.port == b.port;
  }

  static String normalize(String value) {
    final normalized = value.replaceAll(RegExp(r"\s+"), "");
    final fragmentIndex = normalized.indexOf("#");
    return fragmentIndex < 0
        ? normalized
        : normalized.substring(0, fragmentIndex);
  }
}
