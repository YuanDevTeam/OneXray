import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/dialing.dart';

void main() {
  test('missing and unknown strategies retain the system default', () {
    for (final json in <Map<String, dynamic>>[
      {},
      {'domainStrategy': 'unknown'},
    ]) {
      final settings = ServerDialingSettings.fromJson(json);
      expect(settings.domainStrategy, ServerDomainStrategy.system);
      expect(settings.happyEyeballs, isFalse);
      for (final ipv6 in [false, true]) {
        final effective = settings.effective(ipv6: ipv6);
        expect(effective.domainStrategy, 'AsIs');
        expect(effective.happyEyeballs, isFalse);
        expect(effective.enabled, isFalse);
      }
    }
  });

  test('all stored preferences survive a JSON round trip', () {
    for (final strategy in ServerDomainStrategy.values) {
      for (final happyEyeballs in [false, true]) {
        final settings = ServerDialingSettings(
          domainStrategy: strategy,
          happyEyeballs: happyEyeballs,
        );
        final restored = ServerDialingSettings.fromJson(settings.toJson());
        expect(restored.domainStrategy, strategy);
        expect(restored.happyEyeballs, happyEyeballs);
      }
    }
  });

  test('system Happy Eyeballs only enables Core resolution with IPv6', () {
    const settings = ServerDialingSettings(happyEyeballs: true);
    expect(settings.effective(ipv6: true).toJson(), {
      'domainStrategy': 'UseIP',
      'happyEyeballs': true,
    });
    expect(settings.effective(ipv6: true).enabled, isTrue);
    expect(settings.effective(ipv6: false).toJson(), {
      'domainStrategy': 'AsIs',
      'happyEyeballs': false,
    });
    expect(settings.happyEyeballs, isTrue);
  });

  test('explicit strategies compile to their Core names', () {
    const names = {
      ServerDomainStrategy.useIp: 'UseIP',
      ServerDomainStrategy.ipv4: 'UseIPv4',
      ServerDomainStrategy.ipv6: 'UseIPv6',
      ServerDomainStrategy.ipv4First: 'UseIPv4v6',
      ServerDomainStrategy.ipv6First: 'UseIPv6v4',
    };
    for (final entry in names.entries) {
      for (final happyEyeballs in [false, true]) {
        final settings = ServerDialingSettings(
          domainStrategy: entry.key,
          happyEyeballs: happyEyeballs,
        );
        final effective = settings.effective(ipv6: true);
        expect(effective.domainStrategy, entry.value);
        expect(effective.enabled, isTrue);
        expect(
          effective.happyEyeballs,
          entry.key == ServerDomainStrategy.useIp && happyEyeballs,
        );
      }
    }
  });

  test('IPv6 off narrows explicit strategies without rewriting preference', () {
    for (final strategy in ServerDomainStrategy.values.skip(1)) {
      const ipv4 = EffectiveServerDialing(domainStrategy: 'UseIPv4');
      final settings = ServerDialingSettings(
        domainStrategy: strategy,
        happyEyeballs: true,
      );
      expect(settings.effective(ipv6: false), ipv4);
      expect(settings.effective(ipv6: false).hashCode, ipv4.hashCode);
      expect(settings.domainStrategy, strategy);
      expect(settings.happyEyeballs, isTrue);
      expect(settings.effective(ipv6: true).domainStrategy, isNot('AsIs'));
    }
  });

  test('effective comparison ignores inactive Happy Eyeballs preference', () {
    const off = ServerDialingSettings(
      domainStrategy: ServerDomainStrategy.ipv6First,
    );
    const on = ServerDialingSettings(
      domainStrategy: ServerDomainStrategy.ipv6First,
      happyEyeballs: true,
    );
    expect(on.effective(ipv6: true), off.effective(ipv6: true));
    expect(on.effective(ipv6: false), off.effective(ipv6: false));
    expect(
      const ServerDialingSettings().effective(ipv6: true),
      isNot(
        const ServerDialingSettings(happyEyeballs: true).effective(ipv6: true),
      ),
    );
  });
}
