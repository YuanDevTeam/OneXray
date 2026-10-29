import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/servers/outbound/map.dart';

/// Shared by route compilation and its local validation placeholders.
abstract final class XrayFragment {
  static const tag = 'fragment';

  static bool matches(Map<String, dynamic> outbound) =>
      outbound['tag'] == tag && outbound['protocol'] == 'freedom';

  static Map<String, dynamic> defaultOutbound() => XrayOutbound(
    tag: tag,
    protocol: 'freedom',
    streamSettings: XrayStreamSettings(
      finalmask: {
        'tcp': [
          {
            'type': 'fragment',
            'settings': {
              'packets': 'tlshello',
              'length': '100-200',
              'delay': '10-20',
            },
          },
        ],
      },
    ),
  ).toJson();

  /// Only the selected entry roles are linked. Exit clones and user helper
  /// chains are not entries, even when they use the same protocol.
  static List<Map<String, dynamic>> connectEntries(
    Iterable<Map<String, dynamic>> entries,
    Iterable<Map<String, dynamic>> helpers,
  ) {
    final enabled = helpers.any(matches);
    return entries.map((source) {
      final outbound = JsonTool.copyMap(source);
      if (enabled) setOutboundDialerProxy(outbound, tag);
      return outbound;
    }).toList();
  }
}
