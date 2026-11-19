import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/xray/provider_geodata.dart';

String _happHeader(Map<String, dynamic> profile, {String action = 'onadd'}) =>
    'happ://routing/$action/${base64Encode(utf8.encode(jsonEncode(profile)))}';

void main() {
  final ipFile = 'onexray-provider-geoip-${List.filled(64, 'a').join()}.dat';
  final siteFile =
      'onexray-provider-geosite-${List.filled(64, 'b').join()}.dat';
  final binding = ProviderGeoDataBinding(
    geoIpFile: ipFile,
    geoSiteFile: siteFile,
    geoIpUrl: 'https://provider.test/ip.dat',
    geoSiteUrl: 'https://provider.test/site.dat',
  );

  test('reads the whole Happ base64 payload with exact GeoData keys', () {
    final header = _happHeader({
      'Name': 'test ???',
      'Geoipurl': 'https://provider.test/ip.dat',
      'Geositeurl': 'https://provider.test/site.dat',
      'DirectSites': ['geosite:unrelated'],
    });
    // This UTF-8 fixture encodes at least one Base64 slash after the prefix.
    expect(header.substring('happ://routing/onadd/'.length), contains('/'));
    final result = ProviderGeoDataUrls.fromRoutingHeader([header])!;
    expect(result.geoIpUrl, 'https://provider.test/ip.dat');
    expect(result.geoSiteUrl, 'https://provider.test/site.dat');
  });

  test('allows a single asset and ignores unsupported profile transports', () {
    final result = ProviderGeoDataUrls.fromRoutingHeader([
      'incy://autorouting/onadd/https://provider.test/profile',
      _happHeader({
        'Geoipurl': '',
        'Geositeurl': 'https://provider.test/site.dat',
      }, action: 'add'),
    ])!;
    expect(result.geoIpUrl, isNull);
    expect(result.geoSiteUrl, 'https://provider.test/site.dat');
    expect(ProviderGeoDataUrls.fromRoutingHeader(null), isNull);
    expect(
      ProviderGeoDataUrls.fromRoutingHeader([
        'incy://routing/onadd/not-a-supported-value',
        'happ://routing/off',
      ]),
      isNull,
    );
  });

  test('rejects malformed supported headers and invalid asset URLs', () {
    for (final header in [
      'happ://routing/onadd',
      'happ://routing/onadd/not%2Fbase64',
      _happHeader({
        'Geoipurl': ['not', 'a', 'string'],
      }),
      _happHeader({'Geositeurl': 'http://provider.test/site.dat'}),
      _happHeader({'Geositeurl': 'https://user@provider.test/site.dat'}),
    ]) {
      expect(
        () => ProviderGeoDataUrls.fromRoutingHeader([header]),
        throwsFormatException,
      );
    }
    final header = _happHeader({'Geoipurl': 'https://provider.test/ip.dat'});
    expect(
      () => ProviderGeoDataUrls.fromRoutingHeader([header, header]),
      throwsFormatException,
    );
  });

  test('stores only validated typed filenames in a profile binding', () {
    final restored = ProviderGeoDataBinding.decode(binding.encode())!;
    expect(restored.files, [ipFile, siteFile]);
    expect(restored.geoSiteUrl, binding.geoSiteUrl);
    expect(ProviderGeoDataBinding.decode(null), isNull);
    expect(ProviderGeoDataBinding.decode('{}'), isNull);
    expect(isProviderGeoDataFileName(ipFile), isTrue);
    expect(isProviderGeoDataFileName('../$ipFile'), isFalse);
    expect(
      () => ProviderGeoDataBinding.decode(jsonEncode({'geoIpFile': siteFile})),
      throwsFormatException,
    );
    expect(
      () => ProviderGeoDataBinding.decode(
        jsonEncode({'geoIpFile': '/tmp/$ipFile'}),
      ),
      throwsFormatException,
    );
  });

  test('projects only Xray GeoData positions and keeps the original JSON', () {
    final raw = {
      'remarks': 'geosite:provider',
      'routing': {
        'rules': [
          {
            'domain': 'geosite:PROVIDER@!flag,regexp:geosite:unchanged',
            'domains': [
              'ext-site:./geosite.dat:DEFAULT',
              'ext:other.dat:OTHER',
            ],
            'ip': ['!!geoip:!provider', 'ext-ip:geoip.dat:!private'],
            'sourceIP': ['geoip:provider'],
            'source': 'geoip:!private',
            'localIP': '192.0.2.0/24,geoip:private',
            'outboundTag': 'geosite:provider',
          },
        ],
      },
      'dns': {
        'hosts': {
          'ext-domain:geosite.dat:provider': '192.0.2.1',
          'literal.example': '198.51.100.3',
        },
        'servers': [
          {
            'address': 'tcp://192.0.2.53',
            'domains': ['geosite:provider'],
            'expectedIPs': '*,geoip:!private',
            'expectIPs': ['geoip:provider'],
            'unexpectedIPs': ['ext-ip:geoip.dat:private'],
          },
        ],
      },
      'inbounds': [
        {
          'sniffing': {
            'domainsExcluded': 'geosite:provider',
            'ipsExcluded': ['geoip:private'],
          },
        },
      ],
      'outbounds': [
        {
          'protocol': 'dns',
          'settings': {
            'rules': [
              {
                'domain': ['geosite:provider'],
              },
            ],
          },
        },
        {
          'protocol': 'direct',
          'settings': {
            'finalRules': [
              {'ip': 'geoip:private'},
            ],
          },
          'streamSettings': {
            'finalmask': {
              'tcp': [
                {
                  'type': 'filter',
                  'settings': {
                    'blockedSourceIPs': ['geoip:!private'],
                    'allowedSourceIPs': ['!geoip:provider'],
                  },
                },
              ],
            },
          },
        },
      ],
    };
    final original = jsonEncode(raw);
    final projected = binding.apply(raw);
    final routing = projected['routing'] as Map;
    final rule = (routing['rules'] as List).single as Map;
    expect(
      rule['domain'],
      'ext:$siteFile:PROVIDER@!flag,regexp:geosite:unchanged',
    );
    expect(rule['domains'], ['ext:$siteFile:DEFAULT', 'ext:other.dat:OTHER']);
    expect(rule['ip'], ['!!ext:$ipFile:!provider', 'ext:$ipFile:!private']);
    expect(rule['sourceIP'], ['ext:$ipFile:provider']);
    expect(rule['source'], 'ext:$ipFile:!private');
    expect(rule['localIP'], '192.0.2.0/24,ext:$ipFile:private');
    expect(rule['outboundTag'], 'geosite:provider');
    final dns = projected['dns'] as Map;
    expect(dns['hosts'], {
      'ext:$siteFile:provider': '192.0.2.1',
      'literal.example': '198.51.100.3',
    });
    final server = (dns['servers'] as List).single as Map;
    expect(server['domains'], ['ext:$siteFile:provider']);
    expect(server['expectedIPs'], '*,ext:$ipFile:!private');
    expect(server['expectIPs'], ['ext:$ipFile:provider']);
    expect(server['unexpectedIPs'], ['ext:$ipFile:private']);
    final inbound = (projected['inbounds'] as List).single as Map;
    expect(inbound['sniffing'], {
      'domainsExcluded': 'ext:$siteFile:provider',
      'ipsExcluded': ['ext:$ipFile:private'],
    });
    final outbounds = projected['outbounds'] as List;
    expect(outbounds.first['settings']['rules'], [
      {
        'domain': ['ext:$siteFile:provider'],
      },
    ]);
    expect(outbounds.last['settings']['finalRules'], [
      {'ip': 'ext:$ipFile:private'},
    ]);
    final filter = outbounds.last['streamSettings']['finalmask']['tcp'].single;
    expect(filter['settings'], {
      'blockedSourceIPs': ['ext:$ipFile:!private'],
      'allowedSourceIPs': ['!ext:$ipFile:provider'],
    });
    expect(projected['remarks'], 'geosite:provider');
    expect(jsonEncode(raw), original);
    expect(binding.apply(projected), projected);
  });

  test('preserves the default family with no provider file', () {
    final partial = ProviderGeoDataBinding(geoSiteFile: siteFile);
    expect(
      partial.apply({
        'routing': {
          'rules': [
            {
              'domain': ['geosite:provider'],
              'ip': ['geoip:private'],
            },
          ],
        },
      }),
      {
        'routing': {
          'rules': [
            {
              'domain': ['ext:$siteFile:provider'],
              'ip': ['geoip:private'],
            },
          ],
        },
      },
    );
  });

  test('rejects DNS hosts key collisions after applying a binding', () {
    expect(
      () => binding.apply({
        'dns': {
          'hosts': {
            'geosite:provider': '192.0.2.1',
            'ext-site:geosite.dat:provider': '198.51.100.3',
          },
        },
      }),
      throwsFormatException,
    );
  });

  test('rejects private aliases belonging to another binding', () {
    final other = 'onexray-provider-geosite-${List.filled(64, 'c').join()}.dat';
    for (final file in [other, './$other', '$other/', other.toUpperCase()]) {
      expect(
        () => binding.apply({
          'routing': {
            'rules': [
              {
                'domain': ['ext:$file:provider'],
              },
            ],
          },
        }),
        throwsFormatException,
      );
    }
  });

  test('rejects script-based resolution only when assets are bound', () {
    final raw = {
      'routing': {'script': 'runtime.lua'},
    };
    expect(() => binding.apply(raw), throwsFormatException);
    expect(const ProviderGeoDataBinding().apply(raw), raw);
  });
}
