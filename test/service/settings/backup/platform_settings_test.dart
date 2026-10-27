import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/backup/model.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/backup/platform_settings.dart';

void main() {
  final source = PlatformPolicy.fromJson({
    'ipv6Enabled': false,
    'dnsIpv4Address': '1.1.1.1',
    'dnsIpv6Address': '2606:4700:4700::1111',
    'dnsServerName': 'cloudflare-dns.com',
    'dialing': {'domainStrategy': 'ipv4First', 'happyEyeballs': true},
    'lanProxy': {'enabled': true, 'port': 18080},
    'log': {
      'enabled': true,
      'level': 'info',
      'recordDns': false,
      'maskIp': false,
    },
    'xrayOutboundInterfaceName': 'source-interface',
    'android': {
      'appScope': 'included',
      'includedAppPackageNames': [
        'net.example.installed',
        'net.example.missing',
      ],
      'excludedAppPackageNames': ['net.example.excluded'],
    },
    'apple': {
      'captureAllTraffic': true,
      'alwaysOn': true,
      'connectWifiSsids': ['Exact Wi-Fi'],
      'cellularAction': 'disconnect',
      'ethernetAction': 'disconnect',
    },
    'windows': {'alwaysOn': true, 'allowLocalNetwork': false},
  });
  final original = PlatformPolicy.fromJson({
    'xrayOutboundInterfaceName': 'target-interface',
  });

  for (final platform in ConnectionPlatform.values) {
    final settings = BackupPlatformSettings(platform);
    test('${platform.name} capture contains only its own VPN preferences', () {
      final captured = settings.capture(source);
      expect(captured.keys, [platform.name]);
      final policy = captured[platform.name] as Map<String, dynamic>;
      expect(policy['ipv6Enabled'], false);
      expect(policy['dnsIpv4Address'], '1.1.1.1');
      expect(policy['dnsIpv6Address'], '2606:4700:4700::1111');
      expect(policy['dnsServerName'], 'cloudflare-dns.com');
      expect(policy['dialing'], {
        'domainStrategy': 'ipv4First',
        'happyEyeballs': true,
      });
      expect(policy['lanProxy'], {'enabled': true, 'port': 18080});
      expect(policy['log'], source.toJson()['log']);
      expect(policy, isNot(contains('xrayOutboundInterfaceName')));
      expect(
        policy.containsKey('android'),
        platform == ConnectionPlatform.android,
      );
      expect(
        policy.containsKey('apple'),
        platform == ConnectionPlatform.ios ||
            platform == ConnectionPlatform.macos,
      );
      expect(
        policy.containsKey('windows'),
        platform == ConnectionPlatform.windows,
      );
    });

    test('${platform.name} backup only restores to a matching platform', () {
      final document = _document(settings.capture(source));
      for (final target in ConnectionPlatform.values) {
        final reader = BackupPlatformSettings(target);
        reader.validate(document);
        final restored = reader.restore(document, original);
        if (target != platform) {
          expect(restored, same(original));
          continue;
        }
        final policy = restored.toJson();
        expect(policy['ipv6Enabled'], false);
        expect(policy['dnsIpv4Address'], '1.1.1.1');
        expect(policy['xrayOutboundInterfaceName'], 'target-interface');
        expect(policy['dialing'], source.toJson()['dialing']);
        expect(policy['lanProxy'], source.toJson()['lanProxy']);
        expect(policy['log'], source.toJson()['log']);
        for (final section in ['android', 'apple', 'windows']) {
          final active = switch (section) {
            'android' => target == ConnectionPlatform.android,
            'apple' =>
              target == ConnectionPlatform.ios ||
                  target == ConnectionPlatform.macos,
            _ => target == ConnectionPlatform.windows,
          };
          expect(
            policy[section],
            active ? source.toJson()[section] : original.toJson()[section],
          );
        }
      }
    });

    test(
      '${platform.name} ignores malformed foreign sections and unknown fields',
      () {
        final document = _document({
          for (final other in ConnectionPlatform.values)
            if (other != platform) other.name: ['not a policy'],
          'futurePlatform': false,
          platform.name: {
            'futurePreference': {'value': 1},
            'ipv6Enabled': false,
            'xrayOutboundInterfaceName': 'must-not-be-restored',
            'log': {'level': 'debug', 'futureFlag': []},
            if (platform != ConnectionPlatform.android) 'android': false,
            if (platform != ConnectionPlatform.ios &&
                platform != ConnectionPlatform.macos)
              'apple': null,
            if (platform != ConnectionPlatform.windows)
              'windows': 'invalid foreign draft',
          },
        });
        settings.validate(document);
        final restored = settings.restore(document, original).toJson();
        expect(restored['ipv6Enabled'], false);
        expect(restored['log']['level'], 'debug');
        expect(restored['log']['enabled'], original.logEnabled);
        expect(restored['xrayOutboundInterfaceName'], 'target-interface');
      },
    );

    test('${platform.name} rejects malformed current sections', () {
      for (final invalid in [null, false, 1, [], 'invalid']) {
        final document = _document({platform.name: invalid});
        expect(() => settings.validate(document), throwsFormatException);
        expect(
          () => settings.restore(document, original),
          throwsFormatException,
        );
      }
      for (final invalid in <Map<String, dynamic>>[
        {'ipv6Enabled': 'false'},
        {'log': false},
        {
          'log': {'level': 5},
        },
        {
          'dialing': {'happyEyeballs': 'true'},
        },
        {
          'lanProxy': {'port': '18080'},
        },
      ]) {
        final document = _document({platform.name: invalid});
        expect(() => settings.validate(document), throwsFormatException);
        expect(
          () => settings.restore(document, original),
          throwsFormatException,
        );
      }
    });
  }

  test(
    'old and empty platform sections leave the current policy untouched',
    () {
      for (final platform in ConnectionPlatform.values) {
        final settings = BackupPlatformSettings(platform);
        for (final value in [null, <String, dynamic>{}]) {
          final document = _document(value);
          settings.validate(document);
          expect(settings.restore(document, original), same(original));
        }
      }
    },
  );

  test(
    'partial Android settings retain inactive lists and other local drafts',
    () {
      final settings = BackupPlatformSettings(ConnectionPlatform.android);
      final document = _document({
        'android': {
          'android': {
            'includedAppPackageNames': ['net.example.other-device'],
            'futureFlag': true,
          },
          'log': {'recordDns': true},
        },
      });
      settings.validate(document);
      final restored = settings.restore(document, source).toJson();
      expect(restored['android']['appScope'], 'included');
      expect(restored['android']['includedAppPackageNames'], [
        'net.example.other-device',
      ]);
      expect(restored['android']['excludedAppPackageNames'], [
        'net.example.excluded',
      ]);
      expect(restored['apple'], source.toJson()['apple']);
      expect(restored['windows'], source.toJson()['windows']);
      expect(restored['log']['recordDns'], true);
      expect(restored['log']['level'], 'info');
      expect(restored['xrayOutboundInterfaceName'], 'source-interface');
    },
  );

  test('Android package names and modes use existing policy validation', () {
    const settings = BackupPlatformSettings(ConnectionPlatform.android);
    for (final invalid in <Map<String, dynamic>>[
      {'appScope': 'unsupported'},
      {
        'includedAppPackageNames': ['invalid package'],
      },
      {
        'excludedAppPackageNames': [1],
      },
    ]) {
      final document = _document({
        'android': {'android': invalid},
      });
      expect(() => settings.validate(document), throwsFormatException);
      expect(() => settings.restore(document, original), throwsFormatException);
    }
  });

  test('captured Android lists retain packages absent from another device', () {
    const settings = BackupPlatformSettings(ConnectionPlatform.android);
    final restored = settings.restore(
      _document(settings.capture(source)),
      original,
    );
    expect(restored.toJson()['android']['includedAppPackageNames'], [
      'net.example.installed',
      'net.example.missing',
    ]);
  });
}

BackupDocument _document(Map<String, dynamic>? platformSettings) =>
    BackupDocument(
      createdAt: 1000,
      coreConfigs: const [],
      subscriptions: const [],
      routingProfiles: const [],
      smartRouting: const BackupSmartRouting(
        entryCount: 1,
        directRegions: [],
        directPrivate: true,
        directApple: true,
        directWindows: true,
        directDns: true,
        fakeDns: false,
        blockAds: false,
      ),
      geoData: const [],
      platformSettings: platformSettings,
    );
