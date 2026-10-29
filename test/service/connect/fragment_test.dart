import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/state_db.dart';
import 'package:onexray/service/connect/settings.dart';

import 'compiler_test.dart' show catalog, node, options;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'smart and ordinary fragment toggles keep proxy selection and defaults',
    () {
      for (final mode in [TrafficMode.smart, TrafficMode.custom]) {
        for (final count in [1, 3]) {
          for (final enabled in [false, true]) {
            final entries = [for (var i = 0; i < count; i++) node(i + 1)];
            final originalEntries = [
              for (final entry in entries) entry.outbound,
            ];
            final helper = _fragment();
            final draft = RoutingProfileState(
              name: 'Custom',
              entryCount: count,
              fragmentOutbound: enabled ? helper : null,
            );
            final custom = RoutingProfileStateDb.readData(
              name: draft.name,
              data: draft.databaseData,
            );
            final saved = custom.toJson();
            final compiled = ConnectionCompiler.compile(
              settings: ConnectionSettings(
                trafficMode: mode,
                smart: SmartRoutingSettings(
                  entryCount: count,
                  fragment: enabled,
                ),
              ),
              entries: entries,
              custom: mode == TrafficMode.custom ? custom : null,
              regions: catalog,
              options: options(),
            );
            final config = compiled.config;
            _expectEntries(config, count, enabled: enabled);
            expect(_outbounds(config).map((outbound) => outbound['tag']), [
              for (var i = 0; i < count; i++) 'app-entry-$i',
              if (enabled) 'fragment',
              'direct',
              'block',
              'dnsOut',
              'app-dns-forward',
            ]);
            expect(compiled.nodeTags.keys, [
              for (var i = 0; i < count; i++) 'app-entry-$i',
            ]);
            expect(_dialer(_outbound(config, 'direct')), isNull);
            expect(_dialer(_outbound(config, 'dnsOut')), 'app-dns-forward');
            if (enabled) {
              expect(
                _outbound(config, 'fragment'),
                mode == TrafficMode.custom ? helper : _defaultFragment(),
              );
            }
            expect(custom.toJson(), saved);
            expect([
              for (final entry in entries) entry.outbound,
            ], originalEntries);
          }
        }
      }
    },
  );

  test('smart final exits retain each entry link before fragmentation', () {
    for (final count in [1, 3]) {
      final entries = [for (var i = 0; i < count; i++) node(i + 1)];
      final exit = node(9);
      final originalExit = exit.outbound;
      final compiled = ConnectionCompiler.compile(
        settings: ConnectionSettings(
          smart: SmartRoutingSettings(
            entryCount: count,
            finalExitId: exit.id,
            fragment: true,
          ),
        ),
        entries: entries,
        finalExit: exit,
        regions: catalog,
        options: options(),
      );
      final config = compiled.config;
      expect(_outbounds(config).first['tag'], 'app-exit-0');
      expect(config['routing']['balancers'].single['selector'], [
        for (var i = 0; i < count; i++) 'app-exit-$i',
      ]);
      for (var i = 0; i < count; i++) {
        expect(_dialer(_outbound(config, 'app-exit-$i')), 'app-entry-$i');
        expect(_dialer(_outbound(config, 'app-entry-$i')), 'fragment');
      }
      expect(compiled.nodeTags.containsKey('fragment'), false);
      expect(exit.outbound, originalExit);
      expect(_outbound(config, 'fragment'), _defaultFragment());
    }
  });

  test('ordinary FinalMask helpers persist and keep validation wiring', () {
    for (final count in [1, 3]) {
      final helper = _defaultFragment();
      final original = jsonDecode(jsonEncode(helper));
      final draft = RoutingProfileState(
        name: 'FinalMask',
        entryCount: count,
        fragmentOutbound: helper,
      );
      final custom = RoutingProfileStateDb.readData(
        name: draft.name,
        data: draft.databaseData,
      );
      expect(custom.fragmentOutbound, original);
      final saved = custom.toJson();
      final runtime = ConnectionCompiler.compile(
        settings: ConnectionSettings(trafficMode: TrafficMode.custom),
        custom: custom,
        entries: [for (var i = 0; i < count; i++) node(i + 1)],
        regions: catalog,
        options: options(),
      ).config;
      final validation = jsonDecode(
        CustomRoutingService.validationJson(custom),
      ) as Map<String, dynamic>;
      for (final config in [runtime, validation]) {
        _expectEntries(config, count, enabled: true);
        expect(_outbound(config, 'fragment'), original);
        expect(_outbound(config, 'fragment').containsKey('settings'), false);
      }
      expect(custom.toJson(), saved);
      expect(helper, original);
    }
  });

  test('advanced templates attach entries and retain custom helper chains', () {
    for (final count in [1, 3]) {
      final source = _template(count);
      final original = jsonDecode(jsonEncode(source));
      final state = AdvancedRoutingDocument.parse(jsonEncode(source)).state;
      final config = ConnectionCompiler.compile(
        settings: ConnectionSettings(trafficMode: TrafficMode.custom),
        custom: state,
        entries: [for (var i = 0; i < count; i++) node(i + 1)],
        regions: catalog,
        options: options(),
      ).config;
      _expectEntries(config, count, enabled: true);
      expect(_outbound(config, 'fragment'), _fragment());
      expect(_outbound(config, 'manual'), _manualHelper());
      expect(_dialer(_outbound(config, 'fragment')), 'direct');
      expect(_dialer(_outbound(config, 'manual')), 'fragment');
      expect(config['routing']['rules'], source['routing']['rules']);
      expect(state.toJson(), original);
      expect(source, original);
    }
  });

  test('advanced forwarding requires both freedom and the fragment tag', () {
    for (final helper in [
      {'tag': 'fragment', 'protocol': 'blackhole'},
      {..._fragment(), 'tag': 'splitter'},
    ]) {
      final state = AdvancedRoutingDocument.parse(
        jsonEncode({
          'outbounds': [{}, helper],
        }),
      ).state;
      final config = ConnectionCompiler.compile(
        settings: ConnectionSettings(trafficMode: TrafficMode.custom),
        custom: state,
        entries: [node(1)],
        regions: catalog,
        options: options(),
      ).config;
      _expectEntries(config, 1, enabled: false);
      expect(_outbound(config, helper['tag'] as String), helper);
    }
  });

  test('ordinary and advanced validation use the runtime fragment links', () {
    for (final count in [1, 3]) {
      final ordinary = RoutingProfileState(
        name: 'Custom',
        entryCount: count,
        fragmentOutbound: _fragment(),
      );
      final advanced = AdvancedRoutingDocument.parse(
        jsonEncode(_template(count)),
      ).state;
      for (final state in <RoutingConfiguration>[ordinary, advanced]) {
        final saved = state.toJson();
        final validation = jsonDecode(
          CustomRoutingService.validationJson(state),
        ) as Map<String, dynamic>;
        final runtime = ConnectionCompiler.compile(
          settings: ConnectionSettings(trafficMode: TrafficMode.custom),
          custom: state,
          entries: [for (var i = 0; i < count; i++) node(i + 1)],
          regions: catalog,
          options: options(),
        ).config;
        _expectEntries(validation, count, enabled: true);
        for (var i = 0; i < count; i++) {
          expect(
            _dialer(_outbound(validation, 'app-entry-$i')),
            _dialer(_outbound(runtime, 'app-entry-$i')),
          );
        }
        expect(_outbound(validation, 'fragment'), _fragment());
        expect(state.toJson(), saved);
      }
    }
  });

  test('Windows and Linux bind fragment helpers to the selected interface', () {
    for (final platform in [
      ConnectionPlatform.windows,
      ConnectionPlatform.linux,
    ]) {
      final ordinary = RoutingProfileState(
        name: 'Custom',
        fragmentOutbound: _fragment(),
      );
      final advanced = AdvancedRoutingDocument.parse(jsonEncode(_template(1)))
          .state;
      for (final state in <RoutingConfiguration?>[null, ordinary, advanced]) {
        final saved = state?.toJson();
        final config = ConnectionCompiler.compile(
          settings: ConnectionSettings(
            trafficMode: state == null ? TrafficMode.smart : TrafficMode.custom,
            smart: SmartRoutingSettings(fragment: true),
          ),
          custom: state,
          entries: [node(1)],
          regions: catalog,
          options: options(
            platform: platform,
            interfaceName: 'selected-interface',
          ),
        ).config;
        expect(
          _outbound(
            config,
            'fragment',
          )['streamSettings']['sockopt']['interface'],
          'selected-interface',
        );
        expect(state?.toJson(), saved);
      }
    }
  });

  test('Raw and All VPN do not inherit smart fragment forwarding', () {
    final source = <String, dynamic>{
      'outbounds': [
        {
          'tag': 'user-entry',
          'protocol': 'freedom',
          'settings': {'domainStrategy': 'UseIPv4'},
          'streamSettings': {
            'sockopt': {'dialerProxy': 'manual'},
          },
        },
        {'tag': 'plain-entry', 'protocol': 'freedom'},
        _fragment(),
        _manualHelper(),
        {'tag': 'direct', 'protocol': 'freedom'},
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          {
            'domain': ['example.test'],
            'outboundTag': 'plain-entry',
          },
        ],
      },
    };
    final original = jsonDecode(jsonEncode(source));
    final raw = ConnectionCompiler.compile(
      settings: ConnectionSettings(
        expert: true,
        smart: SmartRoutingSettings(fragment: true),
      ),
      raw: source,
      entries: [],
      regions: catalog,
      options: options(),
    ).config;
    expect(
      (raw['outbounds'] as List)
          .take((source['outbounds'] as List).length)
          .toList(),
      source['outbounds'],
    );
    expect(raw['routing']['rules'].last, source['routing']['rules'].single);
    expect(
      raw['routing']['domainStrategy'],
      source['routing']['domainStrategy'],
    );
    expect(_outbounds(raw).first['tag'], 'user-entry');
    expect(_dialer(_outbound(raw, 'user-entry')), 'manual');
    expect(_dialer(_outbound(raw, 'plain-entry')), isNull);
    expect(source, original);

    final allVpn = ConnectionCompiler.compile(
      settings: ConnectionSettings(
        trafficMode: TrafficMode.allVpn,
        smart: SmartRoutingSettings(fragment: true),
      ),
      entries: [node(1)],
      regions: catalog,
      options: options(),
    ).config;
    _expectEntries(allVpn, 1, enabled: false);
    expect(
      _outbounds(allVpn).any((outbound) => outbound['tag'] == 'fragment'),
      false,
    );
  });
}

Map<String, dynamic> _defaultFragment() => {
  'tag': 'fragment',
  'protocol': 'freedom',
  'streamSettings': {
    'finalmask': {
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
  },
};

Map<String, dynamic> _fragment() => {
  'tag': 'fragment',
  'protocol': 'freedom',
  'settings': {
    'fragment': {
      'packets': '1-3',
      'length': '25-50',
      'interval': '0-2',
      'maxSplit': '4-8',
    },
    'userLevel': 2,
  },
  'streamSettings': {
    'sockopt': {'dialerProxy': 'direct'},
  },
};

Map<String, dynamic> _manualHelper() => {
  'tag': 'manual',
  'protocol': 'freedom',
  'streamSettings': {
    'sockopt': {'dialerProxy': 'fragment'},
  },
};

Map<String, dynamic> _template(int count) => {
  'outbounds': [
    for (var i = 0; i < count; i++) <String, dynamic>{},
    _fragment(),
    _manualHelper(),
  ],
  'dns': {
    'servers': ['8.8.8.8'],
  },
  'routing': {
    'domainStrategy': 'AsIs',
    'rules': [
      {
        'domain': ['domain:example.test'],
        'balancerTag': 'proxy',
      },
    ],
  },
};

List<Map<String, dynamic>> _outbounds(Map<String, dynamic> config) =>
    (config['outbounds'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _outbound(Map<String, dynamic> config, String tag) =>
    _outbounds(config).singleWhere((outbound) => outbound['tag'] == tag);

Object? _dialer(Map<String, dynamic> outbound) =>
    ((outbound['streamSettings'] as Map?)?['sockopt'] as Map?)?['dialerProxy'];

void _expectEntries(
  Map<String, dynamic> config,
  int count, {
  required bool enabled,
}) {
  expect(_outbounds(config).first['tag'], 'app-entry-0');
  expect(config['routing']['balancers'].single['selector'], [
    for (var i = 0; i < count; i++) 'app-entry-$i',
  ]);
  for (var i = 0; i < count; i++) {
    expect(
      _dialer(_outbound(config, 'app-entry-$i')),
      enabled ? 'fragment' : null,
    );
  }
}
