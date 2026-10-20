import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/shared/share/app_link_generator.dart';
import 'package:onexray/service/shared/share/app_link_model.dart';
import 'package:onexray/service/shared/share/app_link_parser.dart';
import 'package:onexray/service/shared/share/app_link_share_service.dart';

void main() {
  group('config links', () {
    for (final entry in const <CoreConfigType, OneXrayConfigLinkType>{
      CoreConfigType.outbound: OneXrayConfigLinkType.outbound,
      CoreConfigType.raw: OneXrayConfigLinkType.raw,
    }.entries) {
      test('generates and parses ${entry.value.wireName}', () {
        final xrayJson = entry.key == CoreConfigType.outbound
            ? '{"outbounds":[{"name":"Example","protocol":"vless"}]}'
            : '{"name":"Example"}';
        final uri = OneXrayAppLinkGenerator.config(
          _config(
            type: entry.key.name,
            data: base64Encode(utf8.encode(xrayJson)),
          ),
        );

        expect(uri, isNotNull);
        final generatedUri = uri!;
        expect(generatedUri.queryParameters['type'], entry.value.wireName);
        final link =
            OneXrayAppLinkParser.parse(generatedUri)! as OneXrayConfigLink;
        expect(link.type, entry.value);
        if (entry.key == CoreConfigType.outbound) {
          final wrapper = jsonDecode(link.xrayJson) as Map<String, dynamic>;
          final outbound =
              (wrapper['outbounds'] as List<dynamic>).single
                  as Map<String, dynamic>;
          expect(outbound['tag'], 'Example');
          expect(outbound, isNot(contains('name')));
        } else {
          expect(link.xrayJson, xrayJson);
        }
        expect(link.name, 'Shared Config');
      });
    }

    test('Raw link preserves unprojected fields and original JSON text', () {
      final source = <String, dynamic>{
        'name': 'Payload Profile',
        'dns': {
          'servers': ['1.1.1.1'],
          'future': {'keep': true},
          'text': 'keep  inner\nwhitespace',
        },
        'observatory': {
          'probeInterval': '30s',
          'future': {'keep': true},
        },
      };
      final text = '  \n${jsonEncode(source)}\n';
      final uri = OneXrayAppLinkGenerator.config(
        _config(
          type: CoreConfigType.raw.name,
          data: base64Encode(utf8.encode(text)),
        ),
      );
      final link = OneXrayAppLinkParser.parse(uri!)! as OneXrayConfigLink;

      expect(link.type, OneXrayConfigLinkType.raw);
      expect(link.name, 'Shared Config');
      expect(link.xrayJson, text);
      expect(jsonDecode(link.xrayJson), source);
    });

    test(
      'complete provider share is a named Raw graph with tunnel adaptation',
      () {
        final source = <String, dynamic>{
          'remarks': 'Provider remarks',
          'inbounds': [
            {'tag': 'provider-socks', 'protocol': 'socks', 'port': 1080},
          ],
          'outbounds': [
            {
              'tag': 'proxy-a',
              'protocol': 'socks',
              'streamSettings': {
                'sockopt': {'dialerProxy': 'proxy-b'},
              },
            },
            {'tag': 'proxy-b', 'protocol': 'socks'},
          ],
          'dns': {
            'servers': [
              {
                'address': '1.1.1.1',
                'expectedIPs': ['geoip:US'],
              },
            ],
          },
          'routing': {
            'domainStrategy': 'IPIfNonMatch',
            'balancers': [
              {
                'tag': 'provider',
                'selector': ['proxy-'],
              },
            ],
            'rules': [
              {
                'inboundTag': ['provider-socks'],
                'domain': ['domain:example.com'],
                'balancerTag': 'provider',
              },
            ],
          },
          'observatory': {
            'subjectSelector': ['proxy-'],
            'probeInterval': '30s',
          },
        };
        final original = jsonEncode(source);
        final row = _config(
          type: 'Remnawave',
          data: base64Encode(utf8.encode(original)),
        ).copyWith(subId: 7, name: 'Shared provider');
        final uri = OneXrayAppLinkGenerator.config(row)!;
        final link = OneXrayAppLinkParser.parse(uri)! as OneXrayConfigLink;
        final shared = jsonDecode(link.xrayJson) as Map;
        expect(link.type, OneXrayConfigLinkType.raw);
        expect(link.name, 'Shared provider');
        expect(shared['name'], 'Shared provider');
        expect(shared['remarks'], source['remarks']);
        expect((shared['inbounds'] as List).first['tag'], 'tunIn');
        expect((shared['inbounds'] as List).first['protocol'], 'tun');
        expect((shared['outbounds'] as List).take(2), source['outbounds']);
        expect(shared['dns'], source['dns']);
        expect(shared['observatory'], source['observatory']);
        expect(shared['routing']['balancers'], source['routing']['balancers']);
        expect((shared['routing']['rules'] as List).last['inboundTag'], [
          'provider-socks',
          'tunIn',
        ]);
        expect(utf8.decode(base64Decode(row.data!)), original);
      },
    );

    test(
      'preserved legacy outbound data cannot generate an invalid share link',
      () {
        final legacy = _config(
          type: CoreConfigType.outbound.name,
          data: 'not base64!',
        ).copyWith(id: 12, name: 'Config 12', subId: 7);
        expect(OneXrayAppLinkGenerator.config(legacy), isNull);
      },
    );

    test('finds custom GeoData references in routing and DNS', () {
      final data = base64Encode(
        utf8.encode(
          jsonEncode({
            'routing': {
              'rules': [
                {
                  'domain': [
                    'geosite:google',
                    'ext:community-domain.dat:streaming',
                  ],
                  'ip': ['geoip:private', 'ext:community-ip.dat:private'],
                },
              ],
            },
            'dns': {
              'servers': [
                '8.8.8.8',
                {
                  'address': '1.1.1.1',
                  'domains': ['ext:community-domain.dat:search'],
                  'expectedIPs': ['ext:dns-ip.dat:cloudflare'],
                },
              ],
            },
          }),
        ),
      );

      final names = OneXrayAppLinkGenerator.referencedGeoDataNames(
        _config(type: CoreConfigType.raw.name, data: data),
      );

      expect(names, {'community-domain', 'community-ip', 'dns-ip'});
    });

    test('places referenced GeoData links before the config link', () async {
      final data = base64Encode(
        utf8.encode(
          jsonEncode({
            'routing': {
              'rules': [
                {
                  'domain': ['ext:z-domain.dat:all', 'ext:a-domain.dat:all'],
                },
              ],
            },
          }),
        ),
      );
      final geoData = {
        'a-domain': _geoData('a-domain'),
        'z-domain': _geoData('z-domain'),
      };
      final service = OneXrayAppLinkShareService(
        geoDataLookup: (name) async => geoData[name],
      );

      final text = await service.config(
        _config(type: CoreConfigType.raw.name, data: data),
      );

      expect(text, isNotNull);
      final links = text!
          .split('\n')
          .map(Uri.parse)
          .map(OneXrayAppLinkParser.parse)
          .whereType<OneXrayAppLink>()
          .toList();
      expect(links, hasLength(3));
      expect(links[0], isA<OneXrayGeoDataLink>());
      expect(links[0].name, 'a-domain');
      expect(links[1], isA<OneXrayGeoDataLink>());
      expect(links[1].name, 'z-domain');
      expect(links[2], isA<OneXrayConfigLink>());
    });

    test(
      'shares DNS aliases, response filters and sniffing exclusion assets',
      () async {
        final source = {
          'dns': {
            'servers': [
              {
                'address': '1.1.1.1',
                'expectIPs': ['!ext:alias-ip.dat:blocked'],
                'unexpectedIPs': ['ext:response-ip.dat:untrusted'],
              },
            ],
          },
          'inbounds': [
            {
              'tag': 'tunIn',
              'sniffing': {
                'domainsExcluded': ['ext:excluded-domain.dat:internal'],
                'ipsExcluded': ['!ext:excluded-ip.dat:internal'],
              },
            },
          ],
          'outbounds': [
            {
              'protocol': 'vless',
              'settings': {'password': 'ext:credential.dat:private'},
            },
          ],
        };
        final config = _config(
          type: CoreConfigType.raw.name,
          data: base64Encode(utf8.encode(jsonEncode(source))),
        );
        expect(OneXrayAppLinkGenerator.referencedGeoDataNames(config), {
          'alias-ip',
          'response-ip',
          'excluded-domain',
          'excluded-ip',
        });
        final service = OneXrayAppLinkShareService(
          geoDataLookup: (name) async =>
              _geoData(name)
                  .copyWith(type: name.endsWith('-ip') ? 'ip' : 'domain'),
        );
        final shared = await service.config(config);
        final links = shared!
            .split('\n')
            .map(Uri.parse)
            .map(OneXrayAppLinkParser.parse)
            .whereType<OneXrayAppLink>()
            .toList();
        expect(links.whereType<OneXrayGeoDataLink>().map((link) => link.name), [
          'alias-ip',
          'excluded-domain',
          'excluded-ip',
          'response-ip',
        ]);
        expect(links.last, isA<OneXrayConfigLink>());
        expect((links.last as OneXrayConfigLink).xrayJson, jsonEncode(source));
      },
    );
  });

  group('subscription links', () {
    test('does not export HWID or consent, including when enabled', () {
      const hwid = 'unique-subscription-identity';
      final uri = OneXrayAppLinkGenerator.subscription(
        _subscription().copyWith(hwidEnabled: true, hwid: const Value(hwid)),
      )!;
      expect(uri.queryParameters, {
        'url': 'https://example.com/sub',
        'panel': 'generic',
        'mode': 'appManaged',
      });
      expect(uri.toString(), isNot(contains(hwid)));
      expect(OneXrayAppLinkParser.parse(uri), isA<OneXraySubscriptionLink>());
    });
    test(
      'subscription panel and persisted mode round-trip without credentials',
      () {
        for (final panel in SubscriptionPanel.values) {
          for (final mode in SubscriptionMode.values) {
            final row = _subscription().copyWith(
              panel: panel.name,
              mode: mode.name,
              hwidEnabled: true,
              hwid: const Value('private-hwid'),
              userAgent: const Value('Example/test (compatible)'),
            );
            final uri = OneXrayAppLinkGenerator.subscription(row)!;
            final link =
                OneXrayAppLinkParser.parse(uri)! as OneXraySubscriptionLink;
            expect(link.panel, panel);
            expect(link.mode, mode);
            expect(link.userAgent, 'Example/test (compatible)');
            expect(uri.toString(), isNot(contains('private-hwid')));
          }
        }
      },
    );
    test('normalizes a plain subscription URL', () {
      final uri = OneXrayAppLinkGenerator.subscription(
        _subscription(url: 'https://example.com/sub#provider-fragment'),
      );

      expect(uri, isNotNull);
      final link = OneXrayAppLinkParser.parse(uri!)! as OneXraySubscriptionLink;
      expect(link.url, 'https://example.com/sub');
      expect(link.name, 'Provider');
      expect(link.ageKeyType, isNull);
      expect(link.userAgent, isNull);
    });

    test('exports only the X25519 age type', () {
      const secretKey = 'AGE-SECRET-KEY-1PRIVATE';
      const publicKey = 'age1public';
      final uri = OneXrayAppLinkGenerator.subscription(
        _subscription(ageSecretKey: secretKey, agePublicKey: publicKey),
      );

      expect(uri, isNotNull);
      final text = uri.toString();
      expect(text, isNot(contains(secretKey)));
      expect(text, isNot(contains(publicKey)));
      final link = OneXrayAppLinkParser.parse(uri!)! as OneXraySubscriptionLink;
      expect(link.ageKeyType, AgeKeyType.x25519);
    });

    test('exports only the hybrid age type', () {
      final uri = OneXrayAppLinkGenerator.subscription(
        _subscription(
          ageSecretKey: 'AGE-SECRET-KEY-PQ-1PRIVATE',
          agePublicKey: 'age1pq1public',
        ),
      );

      expect(uri, isNotNull);
      final link = OneXrayAppLinkParser.parse(uri!)! as OneXraySubscriptionLink;
      expect(link.ageKeyType, AgeKeyType.hybrid);
    });

    test('rejects incomplete or unsupported age key pairs', () {
      expect(
        OneXrayAppLinkGenerator.subscription(
          _subscription(ageSecretKey: 'AGE-SECRET-KEY-1PRIVATE'),
        ),
        isNull,
      );
      expect(
        OneXrayAppLinkGenerator.subscription(
          _subscription(
            ageSecretKey: 'unsupported',
            agePublicKey: 'age1public',
          ),
        ),
        isNull,
      );
    });
  });

  test('generates and parses a GeoData link', () {
    final uri = OneXrayAppLinkGenerator.geoData(
      _geoData('Community Domain', url: 'https://example.com/community.dat'),
    );

    expect(uri, isNotNull);
    final link = OneXrayAppLinkParser.parse(uri!)! as OneXrayGeoDataLink;
    expect(link.name, 'Community Domain');
    expect(link.type, GeoDataType.domain);
    expect(link.url, 'https://example.com/community.dat');
  });
}

GeoDataData _geoData(String name, {String? url}) {
  return GeoDataData(
    installed: true,
    id: 3,
    name: name,
    type: GeoDataType.domain.name,
    url: url ?? 'https://example.com/$name.dat',
    timestamp: DateTime(2026),
    categoryCount: 10,
    ruleCount: 100,
  );
}

CoreConfigData _config({required String type, String data = 'e30='}) {
  return CoreConfigData(
    manualSortOrder: 0,
    id: 1,
    name: 'Shared Config',
    type: type,
    tags: '',
    data: data,
    delay: 0,
    subId: 0,
    favorite: false,
  );
}

SubscriptionData _subscription({
  String url = 'https://example.com/sub',
  String? ageSecretKey,
  String? agePublicKey,
}) {
  return SubscriptionData(
    panel: 'generic',
    mode: 'appManaged',
    id: 2,
    hwidEnabled: false,
    name: 'Provider',
    url: url,
    ageSecretKey: ageSecretKey,
    agePublicKey: agePublicKey,
    timestamp: DateTime(2026),
  );
}
