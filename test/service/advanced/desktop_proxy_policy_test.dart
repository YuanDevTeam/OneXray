import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/backup/model.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/backup/platform_settings.dart';

void main() {
  test('legacy preferences stay TUN and local proxy defaults are stable', () {
    final policy = PlatformPolicy.fromJson({});
    expect(policy.captureMode, CaptureMode.tun);
    expect(policy.autoSetSystemProxy, false);
    expect(policy.proxyPort, 10808);
    for (final platform in ConnectionPlatform.values) {
      expect(policy.usesProxy(platform), false);
    }
  });

  test(
    'proxy ignores tunnel-only drafts on desktop, mobile still validates TUN',
    () {
      final policy = PlatformPolicy.fromJson({
        'captureMode': 'proxy',
        'dnsIpv4Address': 'invalid',
        'dnsIpv6Address': '',
        'apple': {
          'dnsOverTls': true,
          'excludedCidrs': ['invalid'],
        },
        'windows': {
          'excludedCidrs': ['invalid'],
        },
      });
      for (final platform in [
        ConnectionPlatform.macos,
        ConnectionPlatform.windows,
        ConnectionPlatform.linux,
      ]) {
        expect(policy.usesProxy(platform), true);
        expect(policy.toTun(platform).toJson(), {'enableIPv6': true});
        expect(policy.runtimeDns(platform), (
          ipv4Address: '8.8.8.8',
          ipv6Address: '2001:4860:4860::8888',
        ));
      }
      for (final platform in [
        ConnectionPlatform.ios,
        ConnectionPlatform.android,
      ]) {
        expect(policy.usesProxy(platform), false);
        expect(() => policy.toTun(platform), throwsFormatException);
        expect(policy.runtimeDns(platform), (
          ipv4Address: 'invalid',
          ipv6Address: '',
        ));
      }
      expect(policy.dnsIpv4Address, 'invalid');
      expect(policy.dnsIpv6Address, '');
    },
  );

  test('proxy mode and port reject malformed or conflicting preferences', () {
    for (final fields in <Map<String, dynamic>>[
      {'captureMode': 'unknown'},
      {'captureMode': true},
      {'proxyPort': 80},
      {'proxyPort': 65536},
      {'proxyPort': '10808'},
      {'autoSetSystemProxy': 'true'},
      {
        'captureMode': 'proxy',
        'proxyPort': 11024,
        'lanProxy': {'enabled': true},
      },
    ]) {
      expect(() => PlatformPolicy.fromJson(fields), throwsFormatException);
    }
    expect(PlatformPolicy.fromJson({'proxyPort': 65535}).proxyPort, 65535);
  });

  test('only effective desktop proxy choices require reconnect', () {
    final tunnel = PlatformPolicy.fromJson({
      'xrayOutboundInterfaceName': 'Ethernet',
    });
    final proxy = PlatformPolicy.fromJson({
      ...tunnel.toJson(),
      'captureMode': 'proxy',
    });
    final changed = PlatformPolicy.fromJson({
      ...proxy.toJson(),
      'proxyPort': 18081,
    });
    final automatic = PlatformPolicy.fromJson({
      ...proxy.toJson(),
      'autoSetSystemProxy': true,
    });
    final interface = PlatformPolicy.fromJson({
      ...proxy.toJson(),
      'xrayOutboundInterfaceName': 'Another interface',
    });
    final tunnelDns = PlatformPolicy.fromJson({
      ...proxy.toJson(),
      'dnsIpv4Address': '',
      'dnsIpv6Address': 'invalid',
    });
    for (final platform in [
      ConnectionPlatform.macos,
      ConnectionPlatform.windows,
      ConnectionPlatform.linux,
    ]) {
      expect(PolicyEditorService.sameRuntime(tunnel, proxy, platform), false);
      expect(PolicyEditorService.sameRuntime(proxy, changed, platform), false);
      expect(
        PolicyEditorService.sameRuntime(proxy, automatic, platform),
        false,
      );
      expect(PolicyEditorService.sameRuntime(proxy, interface, platform), true);
      expect(PolicyEditorService.sameRuntime(proxy, tunnelDns, platform), true);
      expect(
        PolicyEditorService.sameRuntime(
          tunnel,
          PlatformPolicy.fromJson({...tunnel.toJson(), 'proxyPort': 18081}),
          platform,
        ),
        true,
      );
    }
    for (final platform in [
      ConnectionPlatform.ios,
      ConnectionPlatform.android,
    ]) {
      expect(PolicyEditorService.sameRuntime(tunnel, proxy, platform), true);
    }
  });

  test(
    'proxy preferences are device-local during backup capture and restore',
    () {
      final source = PlatformPolicy.fromJson({
        'captureMode': 'proxy',
        'proxyPort': 18081,
        'autoSetSystemProxy': true,
      });
      final target = PlatformPolicy.fromJson({
        'captureMode': 'proxy',
        'proxyPort': 19091,
        'autoSetSystemProxy': false,
      });
      for (final platform in ConnectionPlatform.values) {
        final backup = BackupPlatformSettings(platform);
        final captured = backup.capture(source);
        final selected = captured[platform.name] as Map<String, dynamic>;
        for (final field in [
          'captureMode',
          'proxyPort',
          'autoSetSystemProxy',
        ]) {
          expect(selected.containsKey(field), false);
        }
        // Even a forward/externally produced backup cannot replace device choices.
        selected.addAll({
          'captureMode': 'tun',
          'proxyPort': 28081,
          'autoSetSystemProxy': true,
        });
        final document = BackupDocument(
          createdAt: 1000,
          coreConfigs: const [],
          subscriptions: const [],
          routingProfiles: const [],
          geoData: const [],
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
          platformSettings: captured,
        );
        final restored = backup.restore(document, target);
        expect(restored.captureMode, target.captureMode);
        expect(restored.proxyPort, target.proxyPort);
        expect(restored.autoSetSystemProxy, target.autoSetSystemProxy);
      }
    },
  );

  test('backup preserves TUN DNS drafts without using them for proxy DNS', () {
    final backup = BackupPlatformSettings(ConnectionPlatform.macos);
    final source = PlatformPolicy.fromJson({
      'ipv6Enabled': false,
      'dnsIpv4Address': '1.1.1.1',
      'dnsIpv6Address': '',
    });
    final target = PlatformPolicy.fromJson({'captureMode': 'proxy'});
    final document = BackupDocument(
      createdAt: 1000,
      coreConfigs: const [],
      subscriptions: const [],
      routingProfiles: const [],
      geoData: const [],
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
      platformSettings: backup.capture(source),
    );
    backup.validate(document);
    final restored = backup.restore(document, target);
    final ipv6 = PlatformPolicy.fromJson({
      ...restored.toJson(),
      'ipv6Enabled': true,
    });
    expect(ipv6.captureMode, CaptureMode.proxy);
    expect(ipv6.dnsIpv4Address, '1.1.1.1');
    expect(ipv6.dnsIpv6Address, '');
    expect(ipv6.runtimeDns(ConnectionPlatform.macos), (
      ipv4Address: '8.8.8.8',
      ipv6Address: '2001:4860:4860::8888',
    ));
    final tunnel = PlatformPolicy.fromJson({
      ...ipv6.toJson(),
      'captureMode': 'tun',
    });
    expect(tunnel.runtimeDns(ConnectionPlatform.macos).ipv4Address, '1.1.1.1');
    expect(() => tunnel.toTun(ConnectionPlatform.macos), throwsFormatException);
  });
}
