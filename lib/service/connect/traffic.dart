import 'dart:convert';

import 'package:onexray/service/shared/xray/metrics/model.dart';

/// One in-memory sample from the active Xray metrics endpoint.
class ConnectionTraffic {
  final int uplink;
  final int downlink;
  final int sampledAtMs;
  final List<RuntimePathObservation> observations;

  const ConnectionTraffic({
    required this.uplink,
    required this.downlink,
    required this.sampledAtMs,
    this.observations = const [],
  });
}

enum RuntimePathAvailability { unknown, available, failed }

/// A complete App-managed proxy chain, identified by its exact runtime tag.
class RuntimeObservationPath {
  final String tag;
  final String entryName;
  final String? finalExitName;

  const RuntimeObservationPath({
    required this.tag,
    required this.entryName,
    this.finalExitName,
  });

  /// Display only automatic leastPing selection of at least two managed chains.
  /// Prefix matching is a Core detail; UI identity uses full generated tags.
  static List<RuntimeObservationPath> fromConfiguration({
    required String xrayJson,
    required List<String> entryNames,
    String? finalExitName,
  }) {
    if (entryNames.length < 2) return const [];
    try {
      final json = jsonDecode(xrayJson);
      if (json is! Map<String, dynamic>) return const [];
      final routing = json['routing'];
      final observatory = json['observatory'];
      if (routing is! Map<String, dynamic> ||
          routing['balancers'] is! List ||
          observatory is! Map<String, dynamic> ||
          observatory['subjectSelector'] is! List) {
        return const [];
      }
      final balancers = (routing['balancers'] as List).where(
        (value) => value is Map<String, dynamic> && value['tag'] == 'proxy',
      );
      if (balancers.length != 1) return const [];
      final balancer = balancers.single as Map<String, dynamic>;
      final strategy = balancer['strategy'];
      if (strategy is! Map<String, dynamic> ||
          strategy['type'] != 'leastPing' ||
          balancer['selector'] is! List) {
        return const [];
      }
      final selectors = balancer['selector'] as List;
      final subjects = observatory['subjectSelector'] as List;
      final paths = <RuntimeObservationPath>[];
      for (var index = 0; index < entryNames.length; index++) {
        final tag = finalExitName == null
            ? 'app-entry-$index'
            : 'app-exit-$index';
        if (selectors.contains(tag) && subjects.contains(tag)) {
          paths.add(
            RuntimeObservationPath(
              tag: tag,
              entryName: entryNames[index],
              finalExitName: finalExitName,
            ),
          );
        }
      }
      return paths.length < 2 ? const [] : List.unmodifiable(paths);
    } on FormatException {
      return const [];
    }
  }
}

class RuntimePathObservation {
  final RuntimeObservationPath path;
  final RuntimePathAvailability availability;
  final int? delayMs;
  final int? lastTryTimeMs;
  final int? lastSeenTimeMs;

  const RuntimePathObservation({
    required this.path,
    this.availability = RuntimePathAvailability.unknown,
    this.delayMs,
    this.lastTryTimeMs,
    this.lastSeenTimeMs,
  });

  factory RuntimePathObservation.fromMetrics({
    required RuntimeObservationPath path,
    required XrayMetricsObservation? report,
    required int startedAtSeconds,
  }) {
    final tried = _timeMs(report?.lastTryTime);
    if (report == null ||
        report.outboundTag != path.tag ||
        tried == null ||
        report.lastTryTime! < startedAtSeconds ||
        (report.delay != null && report.delay! < 0)) {
      return RuntimePathObservation(path: path);
    }
    final available = report.alive ?? false;
    final lastSeen = report.lastSeenTime;
    return RuntimePathObservation(
      path: path,
      availability: available
          ? RuntimePathAvailability.available
          : RuntimePathAvailability.failed,
      delayMs: available ? report.delay ?? 0 : null,
      lastTryTimeMs: tried,
      lastSeenTimeMs: lastSeen != null && lastSeen >= startedAtSeconds
          ? _timeMs(lastSeen)
          : null,
    );
  }

  static int? _timeMs(int? seconds) =>
      seconds != null && seconds > 0 && seconds <= 8640000000000
      ? seconds * 1000
      : null;
}
