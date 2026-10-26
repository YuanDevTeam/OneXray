import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/service/advanced/local_api/configuration.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/raw/validator.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/document.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/xray/validation.dart';

const ordinary = '''{
  "name": "Local routing",
  "outbounds": [{}, {}],
  "routing": {
    "rules": [{"domain":["domain:example.com"],"outboundTag":"direct"}]
  }
}''';

const raw = '''{
  "name": "Raw",
  "outbounds": [{"tag":"direct","protocol":"freedom"}],
  "inbounds": [{"tag":"tunIn","protocol":"tun","sniffing":{"enabled":false}}],
  "log": {"error":"/unused/error.log"},
  "env": {"xray.location.asset":"/not-app-assets","XRAY_TUN_FD":"9"},
  "geodata": {"assets":[{"file":"extra.dat","url":"https://example.com/extra.dat"}]}
}''';

Map<String, dynamic> options() => {
  'platform': 'macos',
  'sessionDirectory': '/preview/no-files-created',
  'metricsPort': 18186,
  'socksPort': 18187,
  'ipv6': false,
};

Future<Map<String, dynamic>> resources(
  Future<Map<String, dynamic>> Function() action,
) => action();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all four kinds reuse the UI validation projection', () async {
    final inputs = [
      (
        kind: 'outbound',
        text: '{"tag":"Proxy","protocol":"freedom"}',
        expected: XrayValidation.nodes([
          {'tag': 'Proxy', 'protocol': 'freedom'},
        ]),
      ),
      (
        kind: 'routing',
        text: ordinary,
        expected: CustomRoutingService.validationJson(
          RoutingProfileDocument.parse(ordinary).state,
        ),
      ),
      (
        kind: 'advanced-routing',
        text: AdvancedRoutingProfile.defaultText,
        expected: CustomRoutingService.validationJson(
          AdvancedRoutingDocument.parse(AdvancedRoutingProfile.defaultText)
              .state,
        ),
      ),
      (kind: 'raw', text: raw, expected: XrayValidation.full(jsonDecode(raw))),
    ];
    for (final input in inputs) {
      var calls = 0;
      var inScope = false;
      final api = LocalApiConfiguration(
        withResources: (action) async {
          inScope = true;
          try {
            return await action();
          } finally {
            inScope = false;
          }
        },
        testXray: (text) async {
          expect(inScope, true);
          calls++;
          expect(text, input.expected);
          return '';
        },
      );
      final result = await api.validate({
        'kind': input.kind,
        'text': input.text,
      });
      expect(result['apiVersion'], 1);
      expect(result['status'], 'passed');
      expect(result['stage'], 'kernel');
      expect(result['diagnostics'], isEmpty);
      expect(result['validationConfig'], input.expected);
      expect(calls, 1);
    }
  });

  test(
    'routing validation uses freedom slots without explicit proxy nodes',
    () async {
      final api = LocalApiConfiguration(
        withResources: resources,
        testXray: (text) async {
          final config = jsonDecode(text);
          expect(config['outbounds'].take(2).toList(), [
            {'tag': 'app-entry-0', 'protocol': 'freedom'},
            {'tag': 'app-entry-1', 'protocol': 'freedom'},
          ]);
          expect(config['env']['xray.location.asset'], VpnConstants.datDir);
          expect(
            config['routing']['balancers'].single['fallbackTag'],
            'app-entry-0',
          );
          return '';
        },
      );
      final result = await api.validate({'kind': 'routing', 'text': ordinary});
      expect(result['status'], 'passed');
      expect(
        (result['limitations'] as List).last,
        contains('freedom placeholders'),
      );
    },
  );

  test(
    'syntax errors point into original UTF-16 source, before any rename',
    () async {
      var calls = 0;
      final api = LocalApiConfiguration(
        withResources: resources,
        testXray: (_) async {
          calls++;
          return '';
        },
      );
      const text = '{\r\n "name":"😀",\r\n "outbounds":[#]\r\n}';
      final result = await api.validate({
        'kind': 'raw',
        'text': text,
        'name': 'Renamed',
      });
      final diagnostic = (result['diagnostics'] as List).single;
      expect(result['status'], 'failed');
      expect(result['stage'], 'input');
      expect(diagnostic['offset'], text.indexOf('#'));
      expect(diagnostic['line'], 3);
      expect(diagnostic['column'], 15);
      expect(calls, 0);
    },
  );

  test(
    'App field errors retain source paths and never call the kernel',
    () async {
      final api = LocalApiConfiguration(
        withResources: resources,
        testXray: (_) async => fail('Invalid document reached the kernel'),
      );
      const text =
          '{"outbounds":[{}],"routing":{"rules":[{"sourceIP":["10.0.0.1"]}]}}';
      final result = await api.validate({'kind': 'routing', 'text': text});
      final diagnostic = (result['diagnostics'] as List).single;
      expect(result['status'], 'failed');
      expect(diagnostic['path'], ['routing', 'rules', 0, 'sourceIP']);
      expect(diagnostic['offset'], text.indexOf('["10.0.0.1"]'));
      expect(result, {
        'apiVersion': 1,
        'status': 'failed',
        'stage': 'input',
        'diagnostics': [
          {
            'code': 'invalidConfiguration',
            'message': 'Unsupported field: routing.rules[0].sourceIP',
            'path': ['routing', 'rules', 0, 'sourceIP'],
            'offset': 50,
            'line': 1,
            'column': 51,
          },
        ],
      });
    },
  );

  test(
    'both routing kinds reject unused Geodata without reaching the kernel',
    () async {
      final api = LocalApiConfiguration(
        withResources: resources,
        testXray: (_) async => fail('Unused Geodata reached the kernel'),
      );
      final text = jsonEncode({
        'outbounds': [{}],
        'geodata': {
          'assets': [
            {'file': 'extra.dat', 'url': 'https://example.com/extra.dat'},
          ],
        },
      });
      for (final kind in ['routing', 'advanced-routing']) {
        final result = await api.validate({'kind': kind, 'text': text});
        expect(result['status'], 'failed');
        expect(result['stage'], 'input');
        expect(
          (result['diagnostics'] as List).single['message'],
          'Geodata manifest contains an unused file',
        );
      }
    },
  );

  test('referenced routing manifests validate locally and name overrides remain enforced', () async {
    var calls = 0;
    final api = LocalApiConfiguration(
      withResources: resources,
      testXray: (text) async {
        calls++;
        final projected = jsonDecode(text);
        expect(projected.containsKey('geodata'), false);
        expect(
          (projected['routing']['rules'] as List).singleWhere(
            (rule) => rule.containsKey('domain'),
          )['domain'],
          ['ext:extra.dat:cn'],
        );
        return '';
      },
    );
    final text = jsonEncode({
      'name': 'Embedded name',
      'outbounds': [{}],
      'routing': {
        'rules': [
          {
            'domain': ['ext:extra.dat:cn'],
            'balancerTag': 'proxy',
          },
        ],
      },
      'geodata': {
        'assets': [
          {'file': 'extra.dat', 'url': 'https://example.com/extra.dat'},
        ],
      },
    });
    for (final kind in ['routing', 'advanced-routing']) {
      final valid = await api.validate({
        'kind': kind,
        'text': text,
        'name': 'API name',
      });
      expect(valid['status'], 'passed');
      final oversizedName = await api.validate({
        'kind': kind,
        'text': text,
        'name': 'N' * 33,
      });
      expect(oversizedName['status'], 'failed');
      expect(oversizedName['stage'], 'input');
      expect(
        (oversizedName['diagnostics'] as List).single['message'],
        contains('32 characters'),
      );
    }
    expect(calls, 2);
  });

  test(
    'kernel strings are verbatim and never interpreted as source locations',
    () async {
      const error = 'routing.rules[1]: bad expression (offset 38)';
      final api = LocalApiConfiguration(
        withResources: resources,
        testXray: (_) async => error,
      );
      for (final (kind, text) in [('routing', ordinary), ('raw', raw)]) {
        final result = await api.validate({'kind': kind, 'text': text});
        expect(result['status'], 'failed');
        expect(result['stage'], 'kernel');
        expect(result['diagnostics'], [
          {'code': 'kernelRejected', 'message': error},
        ]);
      }
    },
  );

  test('unavailable kernel differs from a rejected configuration', () async {
    final api = LocalApiConfiguration(
      withResources: resources,
      testXray: (_) async => throw PlatformException(
        code: 'unavailable',
        message: 'Core not loaded',
      ),
    );
    for (final (kind, text) in [
      ('outbound', '{"protocol":"freedom"}'),
      ('raw', raw),
    ]) {
      final result = await api.validate({'kind': kind, 'text': text});
      expect(result['status'], 'notRun');
      expect(result['stage'], 'kernel');
      expect(
        (result['diagnostics'] as List).single['code'],
        'validationUnavailable',
      );
    }
  });

  test(
    'resource failure returns notRun and does not call the kernel',
    () async {
      final api = LocalApiConfiguration(
        withResources: (_) async => throw StateError('Assets unavailable'),
        testXray: (_) async => fail('Unavailable assets reached the kernel'),
      );
      final result = await api.validate({
        'kind': 'outbound',
        'text': '{"protocol":"freedom"}',
      });
      expect(result['status'], 'notRun');
      expect(
        (result['diagnostics'] as List).single['code'],
        'resourcesUnavailable',
      );
    },
  );

  test('Raw explicit name reuses normalization without changing the submitted text', () async {
    const text = '{"outbounds":[{"protocol":"freedom"}]}';
    final api = LocalApiConfiguration(
      withResources: resources,
      testXray: (config) async {
        expect(jsonDecode(config)['name'], 'API raw');
        expect(
          config,
          XrayValidation.full(
            jsonDecode(
              XrayRawValidator.normalize(text, nameOverride: 'API raw').text,
            ),
          ),
        );
        return '';
      },
    );
    expect(
      (await api.validate({
        'kind': 'raw',
        'text': text,
        'name': 'API raw',
      }))['status'],
      'passed',
    );
    expect(jsonDecode(text).containsKey('name'), false);
  });

  test('Raw missing name uses the existing App diagnostic', () async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    final api = LocalApiConfiguration(
      withResources: resources,
      testXray: (_) async => fail('Nameless Raw reached the kernel'),
    );
    final result = await api.validate({
      'kind': 'raw',
      'text': '{"outbounds":[]}',
    });
    expect(result['status'], 'failed');
    expect((result['diagnostics'] as List).single['path'], ['name']);
  });

  test('outbound aliases share the existing tag normalization', () async {
    final api = LocalApiConfiguration(
      withResources: resources,
      testXray: (config) async {
        expect(jsonDecode(config)['outbounds'].single, {
          'tag': 'Legacy',
          'protocol': 'freedom',
        });
        return '';
      },
    );
    final result = await api.validate({
      'kind': 'outbound',
      'text': '{"name":"Legacy","protocol":"freedom"}',
      'name': 'Fallback',
    });
    expect(result['status'], 'passed');
  });

  test(
    'compile requires explicit runtime options and template entries',
    () async {
      final api = LocalApiConfiguration(withResources: resources);
      final missingOptions = await api.compile({
        'kind': 'routing',
        'text': ordinary,
      });
      expect(missingOptions['status'], 'failed');
      expect(missingOptions['stage'], 'compile');
      final missingNodes = await api.compile({
        'kind': 'routing',
        'text': ordinary,
        'options': options(),
      });
      expect(missingNodes['status'], 'failed');
      expect(
        (missingNodes['diagnostics'] as List).single['message'],
        contains('exactly 2'),
      );
    },
  );

  test(
    'Raw preview ignores LAN sharing options and keeps user inbounds',
    () async {
      final source = jsonDecode(raw) as Map<String, dynamic>;
      (source['inbounds'] as List).add({
        'tag': 'app-lan-proxy',
        'protocol': 'socks',
        'port': 11024,
        'listen': '127.0.0.1',
      });
      final text = jsonEncode(source);
      final api = LocalApiConfiguration(withResources: resources);
      final baseline = await api.compile({
        'kind': 'raw',
        'text': text,
        'options': options(),
      });
      expect(baseline['status'], 'passed');
      for (final port in [11024, 18186, 18187]) {
        final shared = await api.compile({
          'kind': 'raw',
          'text': text,
          'options': {
            ...options(),
            'lanProxyEnabled': true,
            'lanProxyPort': port,
          },
        });
        expect(shared['status'], 'passed');
        expect(shared['compiledConfig'], baseline['compiledConfig']);
      }
      expect(
        (jsonDecode(baseline['compiledConfig'] as String)['inbounds'] as List)
            .last,
        (source['inbounds'] as List).last,
      );
    },
  );

  test('routing compile is the existing compiler with explicit nodes, not a kernel test', () async {
    final nodes = [
      {'tag': 'Node A', 'protocol': 'freedom'},
      {'tag': 'Node B', 'protocol': 'freedom'},
    ];
    final api = LocalApiConfiguration(
      withResources: resources,
      testXray: (_) async => fail('Compile must not imply kernel validation'),
    );
    final request = <String, dynamic>{
      'kind': 'routing',
      'text': ordinary,
      'outbounds': nodes,
      'options': options(),
    };
    final before = jsonEncode(request);
    final result = await api.compile(request);
    expect(result['status'], 'passed');
    expect(result['stage'], 'compile');
    final expected = ConnectionCompiler.compile(
      settings: ConnectionSettings(trafficMode: TrafficMode.custom),
      entries: [
        for (final (index, outbound) in nodes.indexed)
          ResolvedServer(id: index + 1, sourceId: 0, outbound: outbound),
      ],
      custom: RoutingProfileDocument.parse(ordinary).state,
      regions: const RegionCatalog.empty(),
      options: RuntimeOptions(
        platform: ConnectionPlatform.macos,
        sessionDirectory: '/preview/no-files-created',
        metricsPort: 18186,
        socksPort: 18187,
        ipv6: false,
      ),
    ).xrayJson;
    expect(result['compiledConfig'], expected);
    expect(jsonEncode(request), before);
  });

  test(
    'advanced and Raw compile use user DNS and the App platform projection',
    () async {
      final api = LocalApiConfiguration(withResources: resources);
      for (final kind in ['advanced-routing', 'raw']) {
        final result = await api.compile({
          'kind': kind,
          'text': kind == 'raw' ? raw : AdvancedRoutingProfile.defaultText,
          if (kind == 'advanced-routing')
            'outbounds': [
              {'tag': 'One', 'protocol': 'freedom'},
            ],
          'options': options(),
        });
        expect(result['status'], 'passed');
        final compiled = jsonDecode(result['compiledConfig'] as String);
        expect(compiled['metrics']['listen'], '127.0.0.1:18186');
        expect(
          compiled['inbounds']
              .where((item) => item['tag'] == 'tunIn')
              .single['protocol'],
          'tun',
        );
        expect(compiled['env']['xray.location.asset'], VpnConstants.datDir);
        expect(compiled.containsKey('geodata'), false);
        if (kind == 'advanced-routing') {
          expect(compiled['dns']['servers'].single['address'], '8.8.8.8');
        }
      }
    },
  );

  test(
    'outbound compiles through all-VPN and Windows inputs are explicit',
    () async {
      final api = LocalApiConfiguration(withResources: resources);
      final request = <String, dynamic>{
        'kind': 'outbound',
        'text': '{"tag":"Node","protocol":"freedom"}',
        'options': {...options(), 'platform': 'windows'},
      };
      expect((await api.compile(request))['status'], 'failed');
      (request['options'] as Map)['windowsMode'] = 'msix';
      expect((await api.compile(request))['status'], 'failed');
      (request['options'] as Map)['interfaceName'] = 'Ethernet';
      final result = await api.compile(request);
      expect(result['status'], 'passed');
      final config = jsonDecode(result['compiledConfig'] as String);
      expect(config['inbounds'].single['protocol'], 'socks');
      expect(config['dns']['servers'].length, 1);
      expect(
        config['outbounds'].first['streamSettings']['sockopt']['interface'],
        'Ethernet',
      );
    },
  );

  test('request mistakes are structured and never invoke the kernel', () async {
    final api = LocalApiConfiguration(
      withResources: resources,
      testXray: (_) async => fail('Invalid input reached the kernel'),
    );
    for (final request in <Map<String, dynamic>>[
      {},
      {'kind': 'unknown', 'text': '{}'},
      {'kind': 'outbound', 'text': []},
      {'kind': 'outbound', 'text': '[]'},
      {'kind': 'raw', 'text': '{}', 'name': 123},
      {'kind': 'outbound', 'text': '{}', 'options': options()},
      {'kind': 'routing', 'text': ordinary, 'outbounds': []},
    ]) {
      final result = await api.validate(request);
      expect(result['status'], 'failed');
      expect(result['stage'], 'input');
    }
  });
}
