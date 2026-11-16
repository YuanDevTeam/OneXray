import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/base_ffi_api.dart';
import 'package:onexray/core/proxy/system_proxy.dart';
import 'package:onexray/core/proxy/windows_proxy.dart';
import 'package:onexray/core/proxy/gnome_proxy.dart';

void main() {
  final adapter = WindowsSystemProxyAdapter();
  const before = <String, dynamic>{
    'flags': 13,
    'server': 'old:3128',
    'bypass': '<local>;*.lan',
    'autoConfigUrl': 'https://example.test/proxy.pac',
  };
  test('Windows desired state preserves stored PAC and bypass while disabling their flags', () {
    final desired = adapter.forEndpoint(before, 10808);
    expect(desired, {
      'flags': 3,
      'server': 'http=127.0.0.1:10808;https=127.0.0.1:10808',
      'bypass': before['bypass'],
      'autoConfigUrl': before['autoConfigUrl'],
    });
    expect(before['flags'], 13);
  });
  test('ownership checks exact active endpoints, not an address substring or bypass', () {
    final expected = adapter.forEndpoint(before, 10808);
    expect(adapter.referencesEndpoint(expected, 10808), isTrue);
    expect(
      adapter.referencesEndpoint({
        ...expected,
        'server': 'http= LOCALHOST:10808',
      }, 10808),
      isTrue,
    );
    expect(
      adapter.referencesEndpoint({...expected, 'flags': 1}, 10808),
      isFalse,
    );
    expect(
      adapter.referencesEndpoint({
        ...expected,
        'server': '127.0.0.1:108080',
      }, 10808),
      isFalse,
    );
    expect(
      adapter.referencesEndpoint({
        ...expected,
        'server': 'other:3128',
        'bypass': '127.0.0.1:10808',
      }, 10808),
      isFalse,
    );
  });
  test(
    'partial rollback permits only values from the original or known write set',
    () {
      final expected = adapter.forEndpoint(before, 10808);
      expect(
        proxyValuesAreBeforeOrExpected(
          {...before, 'server': expected['server']},
          before,
          expected,
        ),
        isTrue,
      );
      expect(
        proxyValuesAreBeforeOrExpected(
          {...expected, 'bypass': 'new-user-rule'},
          before,
          expected,
        ),
        isFalse,
      );
    },
  );
  test('recovery comparison preserves null user overrides and typed effective values', () {
    expect(
      proxyValuesEqual(
        {
          'mode': {'effective': "'none'", 'user': null},
        },
        {
          'mode': {'user': null, 'effective': "'none'"},
        },
      ),
      isTrue,
    );
    expect(
      proxyValuesEqual(
        {
          'mode': {'effective': "'none'", 'user': null},
        },
        {
          'mode': {'effective': "'none'", 'user': "'none'"},
        },
      ),
      isFalse,
    );
  });
  test('GNOME restoration confirms user/default provenance while allowing new inherited values', () {
    final gnome = GnomeSystemProxyAdapter();
    const before = <String, dynamic>{
      'mode': {'effective': "'none'", 'user': null},
      'http.port': {'effective': '8080', 'user': '8080'},
    };
    expect(
      gnome.restorationMatches({
        'mode': {'effective': "'auto'", 'user': null},
        'http.port': {'effective': '8080', 'user': '8080'},
      }, before),
      isTrue,
    );
    expect(
      gnome.restorationMatches({
        'mode': {'effective': "'none'", 'user': "'none'"},
        'http.port': {'effective': '8080', 'user': '8080'},
      }, before),
      isFalse,
    );
    expect(
      gnome.referencesEndpoint({
        'mode': {'effective': "'manual'", 'user': "'manual'"},
        'http.host': {'effective': "'LOCALHOST'", 'user': "'LOCALHOST'"},
        'http.port': {'effective': '10808', 'user': '10808'},
      }, 10808),
      isTrue,
    );
  });
  test('proxy CLI arguments omit DNS and interface without relaxing TUN validation', () {
    expect(
      desktopCoreRunArguments(
        dns: '',
        interfaceName: '',
        configPath: '/proxy/xray.json',
        setDns: false,
      ),
      ['run', '-set-dns=false', '-config', '/proxy/xray.json'],
    );
    expect(
      () => desktopCoreRunArguments(
        dns: '',
        interfaceName: '',
        configPath: '/tun/xray.json',
      ),
      throwsFormatException,
    );
    expect(
      () => desktopCoreRunArguments(
        dns: '',
        interfaceName: '',
        configPath: '',
        setDns: false,
      ),
      throwsFormatException,
    );
  });
}
