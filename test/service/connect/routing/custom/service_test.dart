import 'dart:convert';

import 'package:onexray/core/errors/failure.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/routing/custom/editor.dart';

void main() {
  test(
    'commit rejects an original changed after a successful preflight',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final service = CustomRoutingService(db);
      final id = await service.save(RoutingProfileState(name: 'Original'));
      final original = (await db.routingProfileDao.searchRow(id))!;
      final draft = RoutingProfileState(id: id, name: 'Draft');
      await service.checkSave(draft, original: original);
      await service.save(RoutingProfileState(id: id, name: 'Concurrent edit'));
      await expectLater(
        service.save(draft, original: original),
        throwsA(
          isA<CustomRoutingEditorException>().having(
            (e) => e.reason,
            'reason',
            'changed',
          ),
        ),
      );
      expect(
        (await db.routingProfileDao.searchRow(id))!.name,
        'Concurrent edit',
      );
    },
  );

  test('FakeDNS persists in Base64 DNS settings and is generated for validation only', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = CustomRoutingService(db);
    final disabled = RoutingProfileState(name: 'FakeDNS');
    final state = disabled.copyWith(fakeDns: true);
    expect(CustomRoutingEditorService.sameRouting(disabled, state), false);
    final id = await service.save(state);
    final row = (await db.routingProfileDao.searchRow(id))!;
    final stored = jsonDecode(utf8.decode(base64Decode(row.data)));
    expect(stored.containsKey('fakedns'), false);
    expect(
      (stored['dns']['servers'] as List).singleWhere(
        (server) => server['tag'] == 'app-dns-fake',
      ),
      {'tag': 'app-dns-fake', 'address': 'fakedns'},
    );
    expect(CustomRoutingService.read(row).fakeDns, true);
    await CustomRoutingService.validate(
      state,
      testXray: (text) async {
        final config = jsonDecode(text) as Map<String, dynamic>;
        expect(
          (config['dns']['servers'] as List).singleWhere(
            (server) => server['tag'] == 'app-dns-fake',
          )['address'],
          'fakedns',
        );
        expect(config['fakedns'], [
          {'ipPool': '198.19.0.0/16', 'poolSize': 32768},
          {'ipPool': '2001:2::/48', 'poolSize': 32768},
        ]);
        expect(XrayJson.fromJson(config).toJson(), config);
        expect(config['inbounds'].single['protocol'], 'socks');
        expect(config['inbounds'].single['sniffing']['enabled'], true);
        expect(config['inbounds'].single['sniffing']['destOverride'], [
          'http',
          'tls',
          'quic',
          'fakedns',
        ]);
        return '';
      },
    );
    await service.save(state.copyWith(id: id, fakeDns: false));
    expect(
      CustomRoutingService.read((await db.routingProfileDao.searchRow(id))!)
          .fakeDns,
      false,
    );
  });

  test('routing validation passes native fields to libXray with local entry placeholders', () async {
    final state = RoutingProfileState(
      name: 'Route',
      entryCount: 3,
      directDnsAddress: '1.1.1.1',
      rules: [
        RoutingRuleState(
          port: 0,
          network: 'TCP',
          protocol: const ['http'],
          localOS: const ['android', 'darwin'],
        ),
      ],
    );
    final source = state.encode();
    expect(jsonDecode(source)['outbounds'], [{}, {}, {}]);
    var calls = 0;
    Future<String> check(String text) async {
      calls++;
      final config = jsonDecode(text);
      final directDns = (config['dns']['servers'] as List).singleWhere(
        (server) => server['tag'] == 'app-dns-direct',
      );
      expect(directDns['address'], '1.1.1.1');
      expect(directDns['skipFallback'], true);
      expect(directDns['domains'], isEmpty);
      expect(config['env']['xray.location.asset'], VpnConstants.datDir);
      expect(config['outbounds'], [
        for (var i = 0; i < 3; i++)
          {'tag': 'app-entry-$i', 'protocol': 'freedom'},
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ]);
      expect(config['routing']['domainStrategy'], 'IPIfNonMatch');
      expect(config['routing']['rules'], [state.rules.single.toJson()]);
      expect(config['routing']['balancers'].single, {
        'tag': 'proxy',
        'selector': ['app-entry-0', 'app-entry-1', 'app-entry-2'],
        'strategy': {'type': 'roundRobin'},
        'fallbackTag': 'direct',
      });
      expect(config['observatory'], {'subjectSelector': []});
      return calls == 1 ? '' : 'Core rejected rule';
    }

    await CustomRoutingService.validate(state, testXray: check);
    await expectLater(
      CustomRoutingService.validate(state, testXray: check),
      throwsA(
        isA<AppFailure>().having((e) => e.cause, 'cause', 'Core rejected rule'),
      ),
    );
    expect(calls, 2);
    expect(state.encode(), source);
  });

  test(
    'names use Unicode characters and trimmed case-insensitive uniqueness',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final service = CustomRoutingService(database);
      final id = await service.save(RoutingProfileState(name: ' Route '));
      expect((await database.routingProfileDao.searchRow(id))!.name, 'Route');
      await expectLater(
        service.save(RoutingProfileState(name: 'route')),
        throwsA(
          isA<CustomRoutingEditorException>().having(
            (e) => e.reason,
            'reason',
            'duplicate',
          ),
        ),
      );
      final name = List.filled(32, '🌐').join();
      await service.save(RoutingProfileState(id: id, name: name));
      expect((await database.routingProfileDao.searchRow(id))!.name, name);
    },
  );
  test(
    'custom saves share one strict limit/encoding boundary; edits stay allowed',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final service = CustomRoutingService(database);
      final state = RoutingProfileState(
        name: 'One',
        directDnsAddress: '9.9.9.9',
        rules: [
          RoutingRuleState(
            ruleTag: 'Example',
            domain: const ['domain:example.com'],
            protocol: const ['http'],
            localOS: const ['ios', 'android'],
            action: RoutingRuleAction.direct,
          ),
        ],
      );
      final id = await service.save(state);
      final row = (await database.routingProfileDao.searchRow(id))!;
      final stored = jsonDecode(utf8.decode(base64Decode(row.data))) as Map;
      expect(stored['outbounds'], [{}]);
      expect(stored['dns'], {
        'disableCache': false,
        'disableFallbackIfMatch': false,
        'servers': [
          {'tag': 'app-dns-proxy', 'address': '8.8.8.8'},
          {'tag': 'app-dns-direct', 'address': '9.9.9.9'},
        ],
      });
      expect(stored.containsKey('name'), false);
      expect(stored.containsKey('geodata'), false);
      final roundTrip = CustomRoutingService.read(row);
      expect(roundTrip.id, id);
      expect(roundTrip.name, 'One');
      expect(roundTrip.entryCount, 1);
      expect(roundTrip.directDnsAddress, '9.9.9.9');
      expect(roundTrip.xrayJson.routing!.domainStrategy, 'IPIfNonMatch');
      expect(stored['routing']['domainStrategy'], 'IPIfNonMatch');
      expect(roundTrip.rules.single.toJson(), state.rules.single.toJson());
      await service.save(RoutingProfileState(name: 'Two'));
      await service.save(RoutingProfileState(name: 'Three'));
      await expectLater(
        service.save(RoutingProfileState(name: 'Four')),
        throwsA(
          isA<CustomRoutingEditorException>().having(
            (e) => e.reason,
            'reason',
            'limit',
          ),
        ),
      );
      await service.save(state.copyWith(id: id, name: 'Edited'));
      expect((await database.routingProfileDao.searchRow(id))!.name, 'Edited');
      expect(
        CustomRoutingService.read(
          (await database.routingProfileDao.searchRow(id))!,
        ).xrayJson.routing!.domainStrategy,
        'IPIfNonMatch',
      );
    },
  );
}
