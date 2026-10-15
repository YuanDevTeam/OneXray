import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/model.dart';

enum OneXrayConfigLinkType {
  outbound('outbound'),
  custom('custom'),
  customAdvanced('custom-advanced'),
  raw('raw');

  const OneXrayConfigLinkType(this.wireName);

  final String wireName;
}

sealed class OneXrayAppLink {
  const OneXrayAppLink({required this.name});

  final String name;
}

final class OneXrayConfigLink extends OneXrayAppLink {
  const OneXrayConfigLink({
    required super.name,
    required this.type,
    required this.xrayJson,
  });

  final OneXrayConfigLinkType type;
  final String xrayJson;
}

final class OneXraySubscriptionLink extends OneXrayAppLink {
  const OneXraySubscriptionLink({
    required super.name,
    required this.url,
    this.ageKeyType,
    this.userAgent,
    this.panel = SubscriptionPanel.generic,
    this.mode,
  });

  final String url;
  final AgeKeyType? ageKeyType;
  final String? userAgent;
  final SubscriptionPanel panel;
  final SubscriptionMode? mode;
}

final class OneXrayGeoDataLink extends OneXrayAppLink {
  const OneXrayGeoDataLink({
    required super.name,
    required this.type,
    required this.url,
  });

  final GeoDataType type;
  final String url;
}
