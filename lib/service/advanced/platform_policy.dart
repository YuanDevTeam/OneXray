import 'dart:convert';
import 'dart:io';

import 'package:onexray/core/ffi/windows/model.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/model/tun_json.dart';
import 'package:onexray/service/connect/dialing.dart';
import 'package:onexray/service/connect/settings.dart';

ConnectionPlatform get connectionPlatform => switch (Platform.operatingSystem) {
  'ios' => ConnectionPlatform.ios,
  'macos' => ConnectionPlatform.macos,
  'android' => ConnectionPlatform.android,
  'windows' => ConnectionPlatform.windows,
  'linux' => ConnectionPlatform.linux,
  _ => throw UnsupportedError('Unsupported platform'),
};

/// User policy is a value snapshot, not the mutable native TunJson or old prefs.
final class PlatformPolicy {
  final String _json;

  PlatformPolicy._(Map<String, dynamic> value) : _json = jsonEncode(value);

  factory PlatformPolicy.defaults() => PlatformPolicy.fromJson({});

  factory PlatformPolicy.fromJson(Map<String, dynamic> value) {
    final policy = _readPolicyObject(_defaults, value);
    policy['dialing'] = ServerDialingSettings.fromJson(
      policy['dialing'] as Map<String, dynamic>,
    ).toJson();
    for (final key in ['dnsIpv4Address', 'dnsIpv6Address', 'dnsServerName']) {
      policy[key] = (policy[key] as String).trim();
    }
    final android = policy['android'] as Map<String, dynamic>;
    if (!{'all', 'included', 'excluded'}.contains(android['appScope'])) {
      throw const FormatException('Invalid Android app scope');
    }
    for (final key in ['includedAppPackageNames', 'excludedAppPackageNames']) {
      if ((android[key] as List<String>).any(
        (name) => name.isEmpty || RegExp(r'[\s\x00]').hasMatch(name),
      )) {
        throw const FormatException('Invalid Android app package name');
      }
    }

    final apple = policy['apple'] as Map<String, dynamic>;
    for (final key in ['cellularAction', 'ethernetAction']) {
      if (!{'connect', 'disconnect'}.contains(apple[key])) {
        throw const FormatException('Invalid Apple network action');
      }
    }
    for (final key in ['connectWifiSsids', 'disconnectWifiSsids']) {
      // SSIDs are exact names; trimming nonblank values would change the match.
      apple[key] = (apple[key] as List<String>)
          .where((name) => name.trim().isNotEmpty)
          .toList();
    }
    if ((apple['connectWifiSsids'] as List<String>).any(
      (name) => (apple['disconnectWifiSsids'] as List<String>).contains(name),
    )) {
      throw const FormatException('A Wi-Fi name cannot have both actions');
    }

    final log = policy['log'] as Map<String, dynamic>;
    if (!{'error', 'warning', 'info', 'debug'}.contains(log['level'])) {
      throw const FormatException('Invalid Xray log level');
    }
    final sharing = policy['lanProxy'] as Map<String, dynamic>;
    final port = sharing['port'] as int;
    if (port < 1024 || port > 65535) {
      throw const FormatException('Proxy port must be between 1024 and 65535');
    }
    return PlatformPolicy._(policy);
  }

  Map<String, dynamic> toJson() => jsonDecode(_json) as Map<String, dynamic>;

  bool get ipv6Enabled => toJson()['ipv6Enabled'] as bool;
  ServerDialingSettings get dialing => ServerDialingSettings.fromJson(
    toJson()['dialing'] as Map<String, dynamic>,
  );
  String get xrayOutboundInterfaceName =>
      toJson()['xrayOutboundInterfaceName'] as String;
  bool get logEnabled => toJson()['log']['enabled'] as bool;
  String get logLevel => toJson()['log']['level'] as String;
  bool get recordDns => toJson()['log']['recordDns'] as bool;
  String get maskAddress => toJson()['log']['maskIp'] == true ? 'full' : '';
  bool get lanProxyEnabled => toJson()['lanProxy']['enabled'] as bool;
  int get lanProxyPort => toJson()['lanProxy']['port'] as int;

  static const tunIpv4Address = '198.18.0.1';
  static const tunIpv6Address = 'fc00::1';
  String get dnsIpv4Address => toJson()['dnsIpv4Address'] as String;
  String get dnsIpv6Address => toJson()['dnsIpv6Address'] as String;
  String get dnsServerName => toJson()['dnsServerName'] as String;

  /// Native DNS setters require IP literals; Xray DNS syntax is independent.
  void validateDns(ConnectionPlatform platform, {WindowsMode? windowsMode}) {
    void checkAddress(String value, InternetAddressType family, String label) {
      final address = RegExp(r'[\[\]%\s]').hasMatch(value)
          ? null
          : InternetAddress.tryParse(value);
      if (address == null || address.type != family) {
        throw FormatException(
          '$label must be an ${family.name} address: $value',
        );
      }
    }

    checkAddress(dnsIpv4Address, InternetAddressType.IPv4, 'Tunnel DNS IPv4');
    if (ipv6Enabled ||
        (platform == ConnectionPlatform.windows &&
            (windowsMode ?? windowsBuildMode) == WindowsMode.msix)) {
      checkAddress(dnsIpv6Address, InternetAddressType.IPv6, 'Tunnel DNS IPv6');
    }
    if ((platform == ConnectionPlatform.ios ||
            platform == ConnectionPlatform.macos) &&
        toJson()['apple']['dnsOverTls'] == true &&
        dnsServerName.isEmpty) {
      throw const FormatException('DNS over TLS requires a server name');
    }
  }

  /// Compiles for a real start. Inactive platform drafts remain in [toJson].
  TunJson toTun(ConnectionPlatform platform, {WindowsMode? windowsMode}) {
    validateDns(platform, windowsMode: windowsMode);
    final policy = toJson();
    final tun = <String, dynamic>{
      'tunIPv4': tunIpv4Address,
      if (policy['ipv6Enabled'] == true) 'tunIPv6': tunIpv6Address,
      'tunDnsIPv4': dnsIpv4Address,
      if (policy['ipv6Enabled'] == true) 'tunDnsIPv6': dnsIpv6Address,
      'dnsServerName': dnsServerName,
      'enableIPv6': policy['ipv6Enabled'],
    };

    if (platform == ConnectionPlatform.windows ||
        platform == ConnectionPlatform.linux) {
      final interfaceName = policy['xrayOutboundInterfaceName'] as String;
      if (interfaceName.trim().isEmpty || interfaceName.contains('\u0000')) {
        throw const FormatException('Network interface is required');
      }
      tun['autoOutboundsInterface'] = interfaceName;
    }

    if (platform == ConnectionPlatform.windows &&
        (windowsMode ?? windowsBuildMode) == WindowsMode.msix) {
      _windowsPolicy();
    } else if (platform == ConnectionPlatform.android) {
      final android = policy['android'] as Map<String, dynamic>;
      final scope = android['appScope'];
      final included = (android['includedAppPackageNames'] as List)
          .cast<String>();
      if (scope == 'included' && included.isEmpty) {
        throw const FormatException(
          'Select at least one app before connecting',
        );
      }
      tun.addAll({
        'perAppVPNMode': scope == 'included' ? 'allow' : 'disallow',
        'allowAppList': scope == 'included' ? included : <String>[],
        'disallowAppList': scope == 'excluded'
            ? android['excludedAppPackageNames']
            : <String>[],
      });
    } else if (platform == ConnectionPlatform.ios ||
        platform == ConnectionPlatform.macos) {
      final apple = policy['apple'] as Map<String, dynamic>;
      final alwaysOn = apple['alwaysOn'] as bool;
      final onDemand = alwaysOn || apple['onDemandEnabled'] == true;
      final rules = <Map<String, dynamic>>[];
      if (alwaysOn) {
        rules.add({'mode': 'connect', 'interfaceType': 'any'});
      } else if (onDemand) {
        for (final action in ['disconnect', 'connect']) {
          final ssids = (apple['${action}WifiSsids'] as List).cast<String>();
          if (ssids.isNotEmpty) {
            rules.add({'mode': action, 'interfaceType': 'wifi', 'ssid': ssids});
          }
        }
        final network = platform == ConnectionPlatform.ios
            ? 'cellular'
            : 'ethernet';
        rules.add({
          'mode': apple['${network}Action'],
          'interfaceType': network,
        });
        rules.add({'mode': 'ignore', 'interfaceType': 'any'});
      }
      tun.addAll({
        'includeAllNetworks': apple['captureAllTraffic'],
        if (platform == ConnectionPlatform.ios &&
            apple['captureAllTraffic'] == false)
          'hideVpnIcon': apple['hideVpnIcon'],
        if (apple['captureAllTraffic'] == false)
          'excludedRoutes': _appleExcludedRoutes(
            (apple['excludedCidrs'] as List).cast<String>(),
            ipv6: policy['ipv6Enabled'] as bool,
          ),
        'excludeLocalNetworks': apple['allowLocalNetwork'],
        'excludeCellularServices': apple['bypassCellularServices'],
        'excludeAPNs': apple['bypassApplePushNotifications'],
        'excludeDeviceCommunication': apple['allowDeviceCommunication'],
        'enableDot': apple['dnsOverTls'],
        'onDemandEnabled': onDemand,
        'onDemandRules': rules,
      });
    }
    return TunJson.fromJson(tun);
  }

  WindowsVpnPolicy toWindowsPolicy() {
    validateDns(ConnectionPlatform.windows, windowsMode: WindowsMode.msix);
    return _windowsPolicy();
  }

  WindowsVpnPolicy _windowsPolicy() {
    final policy = toJson();
    final windows = policy['windows'] as Map<String, dynamic>;
    final cidrs = (windows['excludedCidrs'] as List).cast<String>();
    _validateExclusions(
      cidrs,
      dnsAddresses: [dnsIpv4Address, dnsIpv6Address],
      ipv6: policy['ipv6Enabled'] as bool,
    );
    return WindowsVpnPolicy(
      alwaysOn: windows['alwaysOn'] as bool,
      allowLocalNetwork: windows['allowLocalNetwork'] as bool,
      excludedCidrs: List.unmodifiable(cidrs),
    );
  }
}

const _defaults = <String, dynamic>{
  'ipv6Enabled': true,
  'dialing': {'domainStrategy': 'system', 'happyEyeballs': false},
  'dnsIpv4Address': '8.8.8.8',
  'dnsIpv6Address': '2001:4860:4860::8888',
  'dnsServerName': 'dns.google',
  'xrayOutboundInterfaceName': '',
  'lanProxy': {'enabled': false, 'port': 11024},
  'android': {
    'appScope': 'all',
    'includedAppPackageNames': <String>[],
    'excludedAppPackageNames': <String>[],
  },
  'apple': {
    'captureAllTraffic': false,
    'hideVpnIcon': false,
    'excludedCidrs': <String>[],
    'allowLocalNetwork': true,
    'bypassCellularServices': true,
    'bypassApplePushNotifications': true,
    'allowDeviceCommunication': true,
    'dnsOverTls': false,
    'alwaysOn': false,
    'onDemandEnabled': false,
    'connectWifiSsids': <String>[],
    'disconnectWifiSsids': <String>[],
    'cellularAction': 'connect',
    'ethernetAction': 'connect',
  },
  'windows': {
    'alwaysOn': false,
    'allowLocalNetwork': true,
    'excludedCidrs': <String>[],
  },
  'log': {
    'enabled': false,
    'level': 'warning',
    'recordDns': true,
    'maskIp': true,
  },
};

Map<String, dynamic> _readPolicyObject(
  Map<String, dynamic> defaults,
  Map value,
) {
  if (value.keys.any((key) => !defaults.containsKey(key))) {
    throw const FormatException('Unknown platform policy field');
  }
  return defaults.map<String, dynamic>((key, fallback) {
    final item = value.containsKey(key) ? value[key] : fallback;
    if (fallback is Map<String, dynamic> && item is Map) {
      return MapEntry(key, _readPolicyObject(fallback, item));
    }
    if (fallback is List && item is List && item.every((v) => v is String)) {
      return MapEntry(key, List<String>.from(item));
    }
    if (fallback is bool && item is bool ||
        fallback is String && item is String ||
        fallback is int && item is int) {
      return MapEntry(key, item);
    }
    throw FormatException('Invalid platform policy field: $key');
  });
}

List<String> _appleExcludedRoutes(List<String> values, {required bool ipv6}) {
  final routes = <String>[];
  for (final value in values) {
    final parts = value.split('/');
    final address =
        parts.length == 2 && !RegExp(r'[\[\]%\s]').hasMatch(parts[0])
        ? InternetAddress.tryParse(parts[0])
        : null;
    final prefix =
        parts.length == 2 &&
            RegExp(r'^[0-9]+$').stringMatch(parts[1]) == parts[1]
        ? int.tryParse(parts[1])
        : null;
    if (address == null ||
        prefix == null ||
        prefix > address.rawAddress.length * 8) {
      throw FormatException('Invalid Apple VPN exclusion CIDR: $value');
    }
    final bytes = address.rawAddress;
    for (var i = 0; i < bytes.length; i++) {
      if ((bytes[i] & _mask(prefix, i)) != bytes[i]) {
        throw FormatException(
          'Apple VPN exclusion must be a network: $value. '
          'Use /32 or /128 for a single address.',
        );
      }
    }
    if (ipv6 || address.type == InternetAddressType.IPv4) {
      routes.add('${address.address}/$prefix');
    }
  }
  return routes;
}

void _validateExclusions(
  List<String> values, {
  required List<String> dnsAddresses,
  bool ipv6 = true,
}) {
  if (values.length > 64) {
    throw const FormatException('Windows VPN allows at most 64 exclusions');
  }
  final seen = <String>{};
  final dns = [
    for (final address in dnsAddresses) InternetAddress(address).rawAddress,
  ];
  for (final value in values) {
    final parts = value.split('/');
    final address =
        parts.length == 2 && !RegExp(r'[\[\]%\s]').hasMatch(parts[0])
        ? InternetAddress.tryParse(parts[0])
        : null;
    final prefix =
        parts.length == 2 &&
            RegExp(r'^[1-9][0-9]*$').stringMatch(parts[1]) == parts[1]
        ? int.tryParse(parts[1])
        : null;
    if (address == null ||
        prefix == null ||
        prefix > address.rawAddress.length * 8) {
      throw const FormatException('Invalid Windows VPN exclusion CIDR');
    }
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 &&
        parts[0] != bytes.join('.')) {
      throw const FormatException('Invalid Windows VPN exclusion CIDR');
    }
    if (!ipv6 && address.type == InternetAddressType.IPv6) {
      throw const FormatException('IPv6 exclusions require IPv6 to be enabled');
    }
    for (var i = 0; i < bytes.length; i++) {
      if ((bytes[i] & _mask(prefix, i)) != bytes[i]) {
        throw const FormatException('Windows VPN exclusion must be a network');
      }
    }
    if (!seen.add('${bytes.join(',')}/$prefix')) {
      throw const FormatException('Duplicate Windows VPN exclusion');
    }
    for (final server in dns) {
      if (server.length == bytes.length &&
          bytes.indexed.every(
            (entry) => (server[entry.$1] & _mask(prefix, entry.$1)) == entry.$2,
          )) {
        throw const FormatException(
          'Windows VPN exclusion contains tunnel DNS',
        );
      }
    }
  }
}

int _mask(int prefix, int byteIndex) {
  final bits = prefix - byteIndex * 8;
  return bits >= 8
      ? 255
      : bits <= 0
      ? 0
      : (255 << (8 - bits)) & 255;
}
