import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/model/tun_json.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/raw/validator.dart';

void main() {
  test('TUN and start request JSON fields match the native contract', () {
    final tun = TunJson(
      '192.168.3.1',
      'fd00::2',
      '8.8.8.8',
      '2001:4860:4860::8888',
      true,
      'dns.google',
      true,
      'Ethernet',
      true,
      false,
      false,
      false,
      false,
      ['10.250.0.0/16', '2001:db8::/64'],
      true,
      true,
      [
        OnDemandRule('connect', 'wifi', ['test']),
      ],
      'allow',
      ['app.allowed'],
      ['app.disallowed'],
    );
    final request = StartVpnRequest(
      tun,
      '11999',
      '12001',
      '{"apiVersion":3,"method":"runXray"}',
      snapshotToken: 'vole-session-v2:${List.filled(64, 'a').join()}',
      metadataJson: '{"mode":"smart"}',
    );

    expect(tun.toJson().keys.toSet(), {
      'tunIPv4',
      'tunIPv6',
      'tunDnsIPv4',
      'tunDnsIPv6',
      'enableDot',
      'dnsServerName',
      'enableIPv6',
      'autoOutboundsInterface',
      'includeAllNetworks',
      'excludeLocalNetworks',
      'excludeCellularServices',
      'excludeAPNs',
      'excludeDeviceCommunication',
      'excludedRoutes',
      'hideVpnIcon',
      'onDemandEnabled',
      'onDemandRules',
      'perAppVPNMode',
      'allowAppList',
      'disallowAppList',
    });
    expect(TunJson.fromJson(tun.toJson()).toJson(), tun.toJson());
    expect(request.toJson().keys.toSet(), {
      'tun',
      'socksPort',
      'metricsPort',
      'coreInvokeText',
      'snapshotToken',
      'metadataJson',
      'captureMode',
      'autoSetSystemProxy',
    });
  });

  test(
    'validation env JSON exposes the native-supported location keys',
    () async {
      final result = await XrayRawValidator.validate(
        '{"name":"Test","outbounds":[{"protocol":"freedom"}]}',
        testXray: (text) async {
          final config = jsonDecode(text) as Map<String, dynamic>;
          expect(config['env'], {
            'xray.location.asset': VpnConstants.datDir,
            'xray.location.cert': VpnConstants.datDir,
          });
          return '';
        },
      );
      expect(result.name, 'Test');
    },
  );

  test('runXray request uses the v3 in-memory JSON contract', () {
    final request = LibXrayInvokeRequest(
      method: LibXrayMethod.runXray,
      payload: RunXrayRequest('{"outbounds":[]}').toJson(),
    );

    expect(request.toJson(), {
      'apiVersion': 3,
      'method': 'runXray',
      'payload': {'xrayJson': '{"outbounds":[]}'},
    });
  });

  test('testXray API 3 sends only configuration JSON', () {
    final request = LibXrayInvokeRequest(
      method: LibXrayMethod.testXray,
      payload: TestXrayRequest('{"outbounds":[]}').toJson(),
    );

    expect(request.toJson(), {
      'apiVersion': 3,
      'method': 'testXray',
      'payload': {'xrayJson': '{"outbounds":[]}'},
    });
  });

  test('age subscription requests use the typed v3 contract', () {
    final convert = LibXrayInvokeRequest(
      method: LibXrayMethod.convertShareLinksToXrayJson,
      payload: ConvertShareLinksToXrayJsonRequest(
        'encrypted text',
        age: AgeDecryptConfig('AGE-SECRET-KEY-1TEST'),
      ).toJson(),
    );
    final generate = LibXrayInvokeRequest(
      method: LibXrayMethod.generateAgeKeyPair,
      payload: GenerateAgeKeyPairRequest(AgeKeyType.x25519).toJson(),
    );
    final generateHybrid = LibXrayInvokeRequest(
      method: LibXrayMethod.generateAgeKeyPair,
      payload: GenerateAgeKeyPairRequest(AgeKeyType.hybrid).toJson(),
    );

    expect(convert.toJson(), {
      'apiVersion': 3,
      'method': 'convertShareLinksToXrayJson',
      'payload': {
        'text': 'encrypted text',
        'age': {'secretKey': 'AGE-SECRET-KEY-1TEST'},
      },
    });
    expect(generate.toJson(), {
      'apiVersion': 3,
      'method': 'generateAgeKeyPair',
      'payload': {'keyType': 'x25519'},
    });
    expect(generateHybrid.toJson(), {
      'apiVersion': 3,
      'method': 'generateAgeKeyPair',
      'payload': {'keyType': 'hybrid'},
    });
  });
}
