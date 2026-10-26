import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/settings.dart';

import 'compiler_test.dart' show catalog, node, options;

void main() {
  test('ordinary DNS forwarding defaults to the selected proxy balancer', () {
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(smart: SmartRoutingSettings(entryCount: 2)),
      entries: [node(1), node(2)],
      regions: catalog,
      options: options(),
    ).config;
    final dns = (config['outbounds'] as List).singleWhere(
      (outbound) => outbound['tag'] == 'dnsOut',
    );
    expect(dns['streamSettings']['sockopt']['dialerProxy'], 'app-dns-forward');
  });

  for (final mode in [TrafficMode.smart, TrafficMode.custom]) {
    for (final policy in NonAddressDnsPolicy.values) {
      for (final count in [1, 2, 3]) {
        test(
          '${mode.name} ${policy.name} preserves $count complete proxy chains',
          () {
            final dns = RoutingDnsSettings(nonAddressPolicy: policy);
            final config = ConnectionCompiler.compile(
              settings: ConnectionSettings(
                trafficMode: mode,
                smart: SmartRoutingSettings(entryCount: count, dns: dns),
              ),
              custom: mode == TrafficMode.custom
                  ? RoutingProfileState(
                      name: 'DNS policy',
                      entryCount: count,
                      dns: dns,
                    )
                  : null,
              entries: [for (var i = 1; i <= count; i++) node(i)],
              regions: catalog,
              options: options(),
            ).config;
            final outbounds = (config['outbounds'] as List).cast<Map>();
            final forwarding = outbounds.singleWhere(
              (outbound) => outbound['tag'] == 'dnsOut',
            );
            expect(forwarding['settings']['rules'], [
              {'action': 'hijack', 'qType': '1,28'},
              {
                'action': policy == NonAddressDnsPolicy.empty
                    ? 'return'
                    : 'direct',
              },
            ]);
            expect(
              forwarding['streamSettings']?['sockopt']?['dialerProxy'],
              switch (policy) {
                NonAddressDnsPolicy.proxy => 'app-dns-forward',
                NonAddressDnsPolicy.direct => 'direct',
                NonAddressDnsPolicy.empty => null,
              },
            );
            final balancer = config['routing']['balancers'].single;
            expect(balancer['selector'], [
              for (var i = 0; i < count; i++) 'app-entry-$i',
            ]);
            expect(balancer['fallbackTag'], 'app-entry-0');
            final helpers = outbounds.where(
              (outbound) => outbound['protocol'] == 'loopback',
            );
            final rules = (config['routing']['rules'] as List).cast<Map>();
            if (policy == NonAddressDnsPolicy.proxy) {
              expect(helpers.single['settings'], {
                'inboundTag': 'app-dns-forward',
              });
              final rule = rules.first;
              expect(rule['inboundTag'], ['app-dns-forward']);
              expect(rule['balancerTag'], 'proxy');
              expect(rule.containsKey('port'), isFalse);
            } else {
              expect(helpers, isEmpty);
              expect(
                rules.any(
                  (rule) =>
                      (rule['inboundTag'] as List?)?.contains(
                        'app-dns-forward',
                      ) ==
                      true,
                ),
                isFalse,
              );
            }
          },
        );
      }
    }
  }

  test(
    'proxy DNS uses complete final-exit chains with fragment and leastPing',
    () {
      final result = ConnectionCompiler.compile(
        settings: ConnectionSettings(
          smart: SmartRoutingSettings(
            entryCount: 2,
            finalExitId: 9,
            fragment: true,
            selection: const RoutingSelectionSettings(type: 'leastPing'),
          ),
        ),
        entries: [node(1), node(2)],
        finalExit: node(9),
        regions: catalog,
        options: options(),
      );
      final config = result.config;
      expect(config['routing']['balancers'].single['selector'], [
        'app-exit-0',
        'app-exit-1',
      ]);
      expect(
        config['routing']['balancers'].single['fallbackTag'],
        'app-exit-0',
      );
      expect(config['observatory']['subjectSelector'], [
        'app-exit-0',
        'app-exit-1',
      ]);
      expect(result.nodeTags.containsKey('app-dns-forward'), isFalse);
    },
  );

  test('all VPN keeps its fixed proxy forwarding path', () {
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(trafficMode: TrafficMode.allVpn),
      entries: [node(1)],
      regions: catalog,
      options: options(),
    ).config;
    final dns = (config['outbounds'] as List).singleWhere(
      (outbound) => outbound['tag'] == 'dnsOut',
    );
    expect(dns['streamSettings']['sockopt']['dialerProxy'], 'app-entry-0');
    expect(
      (config['outbounds'] as List).any(
        (outbound) => outbound['protocol'] == 'loopback',
      ),
      isFalse,
    );
  });

  test('ordinary save validation includes the actual DNS forwarding graph', () {
    for (final policy in NonAddressDnsPolicy.values) {
      final state = RoutingProfileState(
        name: 'Validate DNS',
        dns: RoutingDnsSettings(nonAddressPolicy: policy),
      );
      final config = jsonDecode(CustomRoutingService.validationJson(state));
      final dns = (config['outbounds'] as List).singleWhere(
        (outbound) => outbound['tag'] == 'dnsOut',
      );
      expect(
        dns['settings']['rules'].last['action'],
        policy == NonAddressDnsPolicy.empty ? 'return' : 'direct',
      );
      expect(
        config['routing']['balancers'].single['fallbackTag'],
        'app-entry-0',
      );
      expect(
        (config['routing']['rules'] as List).isNotEmpty,
        policy == NonAddressDnsPolicy.proxy,
      );
    }
  });
}
