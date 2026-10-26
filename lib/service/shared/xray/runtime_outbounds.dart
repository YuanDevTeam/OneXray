import 'package:onexray/core/model/xray_json.dart';

XrayOutbound createFreedomOutbound({
  required String tag,
  String? interfaceName,
}) => XrayOutbound(
  tag: tag,
  protocol: 'freedom',
  streamSettings: interfaceName == null
      ? null
      : XrayStreamSettings(sockopt: XraySockopt(interface: interfaceName)),
);

XrayOutbound createBlackholeOutbound({required String tag}) =>
    XrayOutbound(tag: tag, protocol: 'blackhole');

XrayOutbound createDnsOutbound({
  required String tag,
  required String? dialerProxy,
  bool returnNonAddress = false,
}) => XrayOutbound(
  tag: tag,
  protocol: 'dns',
  settings: {
    'rules': [
      const XrayOutboundDnsRule(action: 'hijack', qType: '1,28'),
      XrayOutboundDnsRule(action: returnNonAddress ? 'return' : 'direct'),
    ].map((rule) => rule.toJson()).toList(),
  },
  streamSettings: dialerProxy == null
      ? null
      : XrayStreamSettings(sockopt: XraySockopt(dialerProxy: dialerProxy)),
);
