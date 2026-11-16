import 'dart:io';

final class _Contract {
  final String type;
  final Set<String> swiftFields;
  final Set<String> kotlinFields;

  const _Contract(this.type, this.swiftFields, this.kotlinFields);
}

const _contracts = [
  _Contract(
    'TunJson',
    {
      'tunIPv4',
      'tunIPv6',
      'tunDnsIPv4',
      'tunDnsIPv6',
      'enableDot',
      'dnsServerName',
      'enableIPv6',
      'autoOutboundsInterface',
      'includeAllNetworks',
      'excludeLocalNetworks',
      'excludeCellularServices',
      'excludeAPNs',
      'excludeDeviceCommunication',
      'excludedRoutes',
      'hideVpnIcon',
      'onDemandEnabled',
      'onDemandRules',
      'perAppVPNMode',
      'allowAppList',
      'disallowAppList',
    },
    {
      'tunIPv4',
      'tunIPv6',
      'tunDnsIPv4',
      'tunDnsIPv6',
      'enableDot',
      'dnsServerName',
      'enableIPv6',
      'autoOutboundsInterface',
      'includeAllNetworks',
      'excludeLocalNetworks',
      'excludeCellularServices',
      'excludeAPNs',
      'excludeDeviceCommunication',
      'excludedRoutes',
      'hideVpnIcon',
      'onDemandEnabled',
      'onDemandRules',
      'perAppVPNMode',
      'allowAppList',
      'disallowAppList',
    },
  ),
  _Contract(
    'StartVpnRequest',
    {
      'tun',
      'socksPort',
      'metricsPort',
      'coreInvokeText',
      'snapshotToken',
      'metadataJson',
      'captureMode',
      'autoSetSystemProxy',
    },
    {
      'tun',
      'socksPort',
      'metricsPort',
      'coreInvokeText',
      'snapshotToken',
      'metadataJson',
      'captureMode',
      'autoSetSystemProxy',
    },
  ),
  _Contract(
    'XrayEnv',
    {'assetLocation', 'certLocation', 'tunFd'},
    {'assetLocation', 'certLocation', 'tunFd'},
  ),
  _Contract('RunXrayRequest', {'xrayJson'}, {'xrayJson'}),
  _Contract(
    'LibXrayInvokeRequest',
    {'apiVersion', 'method', 'payload'},
    {'apiVersion', 'method', 'payload'},
  ),
  _Contract(
    'LibXrayInvokeResponse',
    {'success', 'error', 'isSuccess'},
    {'success', 'error'},
  ),
];

void main() {
  final swift = File('swift/All/Model.swift').readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/net/yuandev/onexray/pigeon/Model.kt',
  ).readAsStringSync();

  if (!swift.contains('apiVersion: Int? = 3,') ||
      !kotlin.contains('apiVersion: Int? = 3,')) {
    throw StateError('Native libXray requests must use API version 3');
  }

  for (final contract in _contracts) {
    _check(
      'Swift ${contract.type}',
      _swiftFields(swift, contract.type),
      contract.swiftFields,
    );
    _check(
      'Kotlin ${contract.type}',
      _kotlinFields(kotlin, contract.type),
      contract.kotlinFields,
    );
  }
}

Set<String> _swiftFields(String source, String type) {
  final body = _balancedBody(source, 'struct $type', '{', '}');
  return RegExp(
    r'^\s*var\s+(\w+)\s*:',
    multiLine: true,
  ).allMatches(body).map((match) => match.group(1)!).toSet();
}

Set<String> _kotlinFields(String source, String type) {
  final body = _balancedBody(source, 'data class $type', '(', ')');
  return RegExp(
    r'^\s*val\s+(\w+)\s*:',
    multiLine: true,
  ).allMatches(body).map((match) => match.group(1)!).toSet();
}

String _balancedBody(
  String source,
  String marker,
  String opening,
  String closing,
) {
  final markerIndex = source.indexOf(marker);
  if (markerIndex < 0) {
    throw StateError('Missing $marker');
  }
  final start = source.indexOf(opening, markerIndex);
  if (start < 0) {
    throw StateError('Missing $opening after $marker');
  }
  var depth = 0;
  for (var index = start; index < source.length; index++) {
    final value = source[index];
    if (value == opening) {
      depth++;
    } else if (value == closing && --depth == 0) {
      return source.substring(start + 1, index);
    }
  }
  throw StateError('Unclosed $marker');
}

void _check(String label, Set<String> actual, Set<String> expected) {
  if (actual.length == expected.length && actual.containsAll(expected)) {
    return;
  }
  stderr.writeln('$label fields differ. expected=$expected actual=$actual');
  exitCode = 1;
}
