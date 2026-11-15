/// Local Core availability and automatic OS proxy configuration are separate.
final class DesktopSystemProxyCapability {
  const DesktopSystemProxyCapability({required this.supported, this.reason});

  final bool supported;
  final String? reason;
}

typedef SystemProxySnapshot = Map<String, dynamic>;

/// A small platform-specific write set, including values needed for restoration.
/// No adapter changes machine policy, system DNS, routing or a VPN profile.
abstract interface class SystemProxyAdapter {
  String get id;
  Future<DesktopSystemProxyCapability> capability();
  Future<SystemProxySnapshot> read();
  SystemProxySnapshot forEndpoint(SystemProxySnapshot before, int port);
  Future<void> write(SystemProxySnapshot snapshot);
  bool referencesEndpoint(SystemProxySnapshot snapshot, int port);
  bool restorationMatches(
    SystemProxySnapshot actual,
    SystemProxySnapshot before,
  );
}

final class UnsupportedSystemProxyAdapter implements SystemProxyAdapter {
  const UnsupportedSystemProxyAdapter(this.reason);

  final String reason;

  @override
  String get id => 'manual';

  @override
  Future<DesktopSystemProxyCapability> capability() async =>
      DesktopSystemProxyCapability(supported: false, reason: reason);

  @override
  Future<SystemProxySnapshot> read() => throw UnsupportedError(reason);

  @override
  SystemProxySnapshot forEndpoint(SystemProxySnapshot before, int port) =>
      throw UnsupportedError(reason);

  @override
  Future<void> write(SystemProxySnapshot snapshot) =>
      throw UnsupportedError(reason);

  @override
  bool referencesEndpoint(SystemProxySnapshot snapshot, int port) => false;

  @override
  bool restorationMatches(
    SystemProxySnapshot actual,
    SystemProxySnapshot before,
  ) => proxyValuesEqual(actual, before);
}

bool proxyValuesEqual(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && proxyValuesEqual(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (index) => index,
        ).every((index) => proxyValuesEqual(a[index], b[index]));
  }
  return a == b;
}

/// Only a partially applied *known* write set is eligible for startup rollback.
/// An outside value, even in a bypass field, prevents whole-snapshot restoration.
bool proxyValuesAreBeforeOrExpected(
  SystemProxySnapshot actual,
  SystemProxySnapshot before,
  SystemProxySnapshot expected,
) =>
    actual.length == expected.length &&
    actual.keys.every(
      (key) =>
          before.containsKey(key) &&
          expected.containsKey(key) &&
          (proxyValuesEqual(actual[key], before[key]) ||
              proxyValuesEqual(actual[key], expected[key])),
    );
