import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/xray/metrics/model.dart';

void main() {
  test('current traffic counts only tunnel counters', () {
    final metrics = XrayMetricsVars.fromJson({
      'stats': {
        'inbound': {
          'tunIn': {'uplink': 120, 'downlink': 240},
          'app-lan-proxy': {'uplink': 30, 'downlink': 60},
          'user-http': {'uplink': 1000, 'downlink': 2000},
        },
      },
    });
    expect(metrics.managedTraffic.uplink, 120);
    expect(metrics.managedTraffic.downlink, 240);
    expect(metrics.toJson()['stats']['inbound'], {
      'tunIn': {'uplink': 120, 'downlink': 240},
    });
  });

  test('LAN-only traffic does not contribute to connection traffic', () {
    final metrics = XrayMetricsVars.fromJson({
      'stats': {
        'inbound': {
          'app-lan-proxy': {'uplink': 30, 'downlink': 60},
        },
      },
    });
    expect(metrics.managedTraffic.uplink, 0);
    expect(metrics.managedTraffic.downlink, 0);
  });

  test('uncreated counters remain zero', () {
    final metrics = XrayMetricsVars.fromJson({
      'stats': {'inbound': <String, dynamic>{}},
    });
    expect(metrics.managedTraffic.uplink, 0);
    expect(metrics.managedTraffic.downlink, 0);
  });

  test(
    'observatory reads Core snake_case numeric seconds and omitted defaults',
    () {
      final metrics = XrayMetricsVars.fromJson({
        'stats': {'inbound': <String, dynamic>{}},
        'observatory': {
          'app-entry-0': {
            'alive': true,
            'delay': 52,
            'outbound_tag': 'app-entry-0',
            'last_try_time': 1791676800,
            'last_seen_time': 1791676800,
          },
          'app-entry-1': {
            'delay': 99999999,
            'outbound_tag': 'app-entry-1',
            'last_try_time': 1791676801,
            'last_error_reason': 'connection refused',
          },
        },
      });
      final available = metrics.observatory!['app-entry-0']!;
      expect(available.alive, true);
      expect(available.delay, 52);
      expect(available.lastTryTime, 1791676800);
      expect(available.lastSeenTime, 1791676800);
      // Go omitempty leaves false absent; the domain maps a reported failure.
      expect(metrics.observatory!['app-entry-1']!.alive, isNull);
      expect(
        metrics.toJson()['observatory']['app-entry-0']['last_try_time'],
        1791676800,
      );
    },
  );

  test('missing or null observatory does not change tunnel counters', () {
    for (final json in [
      {
        'stats': {'inbound': <String, dynamic>{}},
      },
      {
        'stats': {'inbound': <String, dynamic>{}},
        'observatory': null,
      },
    ]) {
      final metrics = XrayMetricsVars.fromJson(json);
      expect(metrics.observatory, isNull);
      expect(metrics.managedTraffic, (uplink: 0, downlink: 0));
    }
  });
}
