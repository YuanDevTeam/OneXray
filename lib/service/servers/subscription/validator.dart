import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/network/model.dart';
import 'package:onexray/service/servers/subscription/model.dart';

abstract final class SubscriptionValidator {
  static SubscriptionUpdateResult? validate(SubscriptionInput input) {
    if (input.name.trim().isEmpty) return SubscriptionUpdateResult.nameRequired;
    if (input.url.isEmpty) return SubscriptionUpdateResult.urlRequired;
    final uri = Uri.tryParse(input.url);
    if (uri == null || !NetClient.isHttpsDownloadUri(uri)) {
      return SubscriptionUpdateResult.urlInvalid;
    }
    if (!DownloadRequestHeaders.isValidUserAgent(input.normalizedUserAgent)) {
      return SubscriptionUpdateResult.userAgentInvalid;
    }
    if (input.hasIncompleteAgeKeyPair) {
      return SubscriptionUpdateResult.incompleteAgeKeys;
    }
    return null;
  }
}
