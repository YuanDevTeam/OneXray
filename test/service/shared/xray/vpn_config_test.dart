import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/xray/vpn_config.dart';

void main() {
  test(
    'Raw receives a bounded DNS ingress without changing its default exit',
    () {
      final source = <String, dynamic>{
        'outbounds': [
          {'protocol': 'freedom'},
        ],
        'routing': {
          'domainStrategy': 'AsIs',
          'rules': [
            {
              'domain': ['full:example.test'],
              'outboundTag': 'blocked',
            },
          ],
        },
      };
      final before = jsonEncode(source);
      final result = VpnConfigAdapter.adapt(source);
      expect(result['outbounds'].first, source['outbounds'][0]);
      expect(result['inbounds'].single['tag'], 'tunIn');
      expect(result['routing']['rules'].first, {
        'type': 'field',
        'inboundTag': ['tunIn'],
        'network': 'tcp,udp',
        'port': '53',
        'outboundTag': VpnConfigAdapter.dnsTag,
      });
      expect(result['routing']['rules'].last, source['routing']['rules'][0]);
      expect(result['routing']['domainStrategy'], 'AsIs');
      expect(VpnConfigAdapter.adapt(result), result);
      expect(jsonEncode(source), before);
      expect(result.containsKey('dns'), isFalse);
      expect(result.containsKey('env'), isFalse);
    },
  );

  test('an explicit DNS policy remains authoritative for Raw', () {
    final rule = {
      'port': 53,
      'inboundTag': ['tunIn'],
      'outboundTag': 'user-dns',
      'network': 'udp',
      'ip': ['192.0.2.53'],
    };
    final source = <String, dynamic>{
      'inbounds': [
        {
          'tag': 'tunIn',
          'protocol': 'tun',
          'sniffing': {'enabled': false},
        },
      ],
      'outbounds': [
        {'tag': 'user-dns', 'protocol': 'freedom'},
      ],
      'routing': {
        'rules': [rule],
      },
    };
    final result = VpnConfigAdapter.adapt(source);
    expect(result, source);
  });
}
