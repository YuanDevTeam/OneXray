import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/routing/custom/document.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/state_db.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';

ResolvedServer node(int id) => ResolvedServer(
  id: id,
  sourceId: 1,
  outbound: {'protocol': 'freedom', 'tag': 'Node $id'},
);
Map<String, dynamic> compile(
  SmartRoutingSettings smart, {
  bool fixed = false,
  ResolvedServer? finalExit,
}) => jsonDecode(
  ConnectionCompiler.compile(
    settings: ConnectionSettings(
      smart: smart,
      selection: fixed
          ? const ServerSelection.server(1)
          : const ServerSelection.automatic(),
    ),
    entries: fixed
        ? [node(1)]
        : [for (var i = 1; i <= smart.entryCount; i++) node(i)],
    finalExit: finalExit,
    regions: const RegionCatalog.empty(),
    options: RuntimeOptions(
      platform: ConnectionPlatform.android,
      sessionDirectory: '/unused',
      socksPort: 1080,
      metricsPort: 1081,
      lanProxyEnabled: true,
    ),
  ).xrayJson,
) as Map<String, dynamic>;
void main() {
  test('old disabled sniffing preferences ignore retired exclusions', () {
    final settings = RoutingSniffingSettings.fromJson({
      'enabled': false,
      'domainsExcluded': ['ext:missing.dat:cn'],
      'ipsExcluded': ['regexp:['],
    });
    expect(settings.toJson(), {
      'enabled': false,
      'routeOnly': false,
      'metadataOnly': false,
    });
    final state = RoutingProfileState(name: 'disabled', sniffing: settings);
    expect(
      RoutingProfileDocument.parse(
        state.encode(),
        name: 'disabled',
      ).state.sniffing.toJson(),
      settings.toJson(),
    );
    expect(
      compile(
        SmartRoutingSettings(sniffing: settings),
      )['inbounds'][0]['sniffing'],
      {'enabled': false},
    );
  });
  test('leastPing observes complete exits and retains explicit direct rules ahead of catchall', () {
    final smart = SmartRoutingSettings(
      entryCount: 2,
      finalExitId: 3,
      selection: const RoutingSelectionSettings(type: 'leastPing'),
      sniffing: const RoutingSniffingSettings(routeOnly: true),
    );
    final json = compile(smart, finalExit: node(3));
    expect(json['routing']['balancers'].single['selector'], [
      'app-exit-0',
      'app-exit-1',
    ]);
    expect(json['routing']['balancers'].single['fallbackTag'], 'app-exit-0');
    expect(json['observatory']['subjectSelector'], [
      'app-exit-0',
      'app-exit-1',
    ]);
    expect(json['routing']['rules'].last['inboundTag'], [
      'tunIn',
      'app-lan-proxy',
    ]);
    expect(json['inbounds'][0]['sniffing'], json['inbounds'][1]['sniffing']);
    expect(json['inbounds'][0]['sniffing']['routeOnly'], true);
    expect(
      json['outbounds'][0]['streamSettings']['sockopt']['dialerProxy'],
      'app-entry-0',
    );
  });
  test('fixed single node skips probes while retaining the preference', () {
    final smart = SmartRoutingSettings(
      entryCount: 2,
      selection: const RoutingSelectionSettings(type: 'leastPing'),
    );
    final json = compile(smart, fixed: true);
    expect(json['observatory']['subjectSelector'], isEmpty);
    expect(
      json['routing']['balancers'].single['strategy']['type'],
      'roundRobin',
    );
    expect(
      json['routing']['rules'].last['ruleTag'],
      isNot('app-proxy-catchall'),
    );
    expect(smart.selection.type, 'leastPing');
  });
  test('ordinary saved and shared preferences roundtrip without runtime-owned fields', () {
    final state = RoutingProfileState(
      name: 'test',
      entryCount: 2,
      dns: const RoutingDnsSettings(
        proxyResolvers: [RoutingDnsResolver(address: '1.1.1.1')],
        sameExitOnly: true,
      ),
      sniffing: const RoutingSniffingSettings(metadataOnly: true),
      selection: const RoutingSelectionSettings(
        type: 'leastPing',
        probeInterval: '30s',
      ),
    );
    final decoded = RoutingProfileDocument.parse(
      state.encode(),
      name: 'test',
    ).state;
    expect(decoded.dns.toJson(), state.dns.toJson());
    expect(decoded.sniffing.toJson(), state.sniffing.toJson());
    expect(decoded.selection.toJson(), state.selection.toJson());
    expect(
      RoutingProfileStateDb.readData(
        id: 1,
        name: 'test',
        data: state.databaseData,
      ).toJson(),
      state.toJson(),
    );
    expect(state.toJson()['observatory'].containsKey('subjectSelector'), false);
    expect(
      state.toJson()['routing']['balancers'].single.containsKey('selector'),
      false,
    );
  });
  test('advanced selection owns only managed client catchall and preserves sniffing', () {
    final profile = AdvancedRoutingDocument.fromJson({
      'outbounds': [<String, dynamic>{}, <String, dynamic>{}],
      'inbounds': [
        {
          'tag': 'tunIn',
          'sniffing': {'enabled': false},
        },
      ],
      'routing': {
        'balancers': [
          {
            'tag': 'proxy',
            'strategy': {'type': 'leastPing'},
          },
        ],
        'rules': [
          {
            'domain': ['domain:example.com'],
            'outboundTag': 'direct',
          },
        ],
      },
      'observatory': {'probeInterval': '30s'},
    }).state;
    final filled = profile.fillSlots([
      {'tag': 'app-entry-0', 'protocol': 'freedom'},
      {'tag': 'app-entry-1', 'protocol': 'freedom'},
    ]);
    expect(filled['inbounds'].single['sniffing'], {'enabled': false});
    expect(filled['routing']['rules'].last['inboundTag'], ['tunIn']);
    expect(filled['routing']['rules'].first['outboundTag'], 'direct');
    expect(filled['routing']['balancers'].single['fallbackTag'], 'app-entry-0');
  });
}
