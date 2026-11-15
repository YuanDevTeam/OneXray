import 'dart:convert';
import 'dart:io';

import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/ping/state.dart';

/// A read-only reference check of this run's App-managed proxy chains.
/// The native batch uses its own temporary Core and never updates saved delays.
class ConnectionStartupProbe {
  ConnectionStartupProbe({
    Future<List<PingBatchResult>> Function(List<PingBatchSource>, PingState)?
    runBatch,
    Future<PingState> Function()? readPingState,
    bool Function()? supported,
  }) : _runBatch = runBatch ?? PingBatchRunner.run,
       _readPingState = readPingState ?? _readPreferences,
       _supported = supported ?? _supportedPlatform;

  final Future<List<PingBatchResult>> Function(List<PingBatchSource>, PingState)
  _runBatch;
  final Future<PingState> Function() _readPingState;
  final bool Function() _supported;

  /// null means no unambiguous target or an unsupported execution environment.
  /// Any successful complete chain is enough; one failed alternate is not a
  /// reason to warn when another selected path remains reachable.
  Future<bool?> run(ConnectionRuntime runtime) async {
    final List<PingBatchSource> sources;
    final PingState pingState;
    try {
      if (!_supported()) return null;
      sources = _sources(runtime);
      if (sources.isEmpty) return null;
      pingState = await _readPingState();
    } catch (_) {
      return null;
    }
    try {
      final results = await _runBatch(sources, pingState);
      return results.length == sources.length &&
          results.any((result) => result.success);
    } catch (_) {
      return false;
    }
  }

  static Future<PingState> _readPreferences() async {
    final value = PingState();
    await value.readFromPreferences();
    return value;
  }

  static bool _supportedPlatform() =>
      !Platform.isIOS ||
      (!Platform.environment.containsKey('SIMULATOR_UDID') &&
          !Platform.environment.containsKey('SIMULATOR_DEVICE_NAME'));

  static List<PingBatchSource> _sources(ConnectionRuntime runtime) {
    if (runtime.configuration.connection.expert ||
        runtime.profile != null ||
        runtime.entries.isEmpty ||
        runtime.entries.length > PingBatchRunner.maxBatchSize) {
      return const [];
    }
    final json = jsonDecode(runtime.xrayJson);
    if (json is! Map<String, dynamic>) return const [];
    final routing = json['routing'];
    final outbounds = json['outbounds'];
    if (routing is! Map<String, dynamic> ||
        routing['balancers'] is! List ||
        outbounds is! List) {
      return const [];
    }
    final balancers = (routing['balancers'] as List)
        .whereType<Map<String, dynamic>>()
        .where((balancer) => balancer['tag'] == 'proxy')
        .toList();
    if (balancers.length != 1) return const [];
    final selectors = balancers.single['selector'];
    final tags = [
      for (var index = 0; index < runtime.entries.length; index++)
        '${runtime.finalExit == null ? 'app-entry' : 'app-exit'}-$index',
    ];
    if (selectors is! List ||
        selectors.length != tags.length ||
        selectors.toSet().length != tags.length ||
        !tags.every(selectors.contains)) {
      return const [];
    }
    for (final tag in tags) {
      if (outbounds
              .whereType<Map<String, dynamic>>()
              .where((outbound) => outbound['tag'] == tag)
              .length !=
          1) {
        return const [];
      }
    }
    return [
      for (final tag in tags)
        PingBatchSource(runtime.xrayJson, outboundTag: tag),
    ];
  }
}
