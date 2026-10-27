import 'dart:async';

import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';

enum ConnectionResolutionFailure {
  selectionUnavailable,
  insufficientCandidates,
  insufficientHealthyServers,
  finalExitUnavailable,
  selfReference,
  invalidSettings,
  cancelled,
  readFailed,
  probeFailed,
}

class ConnectionResolutionException implements Exception {
  final ConnectionResolutionFailure reason;
  final int requiredCount;
  final int availableCount;

  const ConnectionResolutionException(
    this.reason, {
    this.requiredCount = 0,
    this.availableCount = 0,
  });

  @override
  String toString() => 'Connection resolution failed: ${reason.name}';
}

/// One connection target: ordinary entries or one complete provider graph.
class ResolvedConnectionTarget {
  final List<ResolvedServer> entries;
  final ResolvedProfile? profile;
  final CoreConfigData? profileRow;

  ResolvedConnectionTarget.entries(Iterable<ResolvedServer> entries)
    : entries = List.unmodifiable(entries),
      profile = null,
      profileRow = null;

  ResolvedConnectionTarget.profile(CoreConfigData row)
    : entries = const [],
      profile = ResolvedProfile.fromRow(row),
      profileRow = row;
}

/// Resolves a committed selection to independent values, never a live session.
/// The rows stream must emit its current rows whenever it is subscribed to; it
/// may then watch batch commits. The final re-read also supports one-shot readers.
class ConnectionResolver {
  final Stream<List<CoreConfigData>> Function() _rows;
  final Future<void> Function(List<int>) _probe;

  ConnectionResolver({
    Stream<List<CoreConfigData>> Function()? rows,
    Future<void> Function(List<int>)? probe,
  }) : _rows = rows ?? _databaseRows,
       _probe = probe ?? PingService().pingConfigIds;

  static Stream<List<CoreConfigData>> _databaseRows() =>
      AppDatabase().coreConfigDao.watchServers();

  /// Cancellation ends only this wait. Already scheduled probes keep updating
  /// candidate caches and cannot change resolved inputs or a running VPN.
  Future<List<ResolvedServer>> resolve(
    ConnectionSettings settings, {
    RoutingConfiguration? custom,
    Future<void>? cancelled,
  }) async => (await _resolve(settings, custom, cancelled)).entries;

  /// Automatic and source selection prefer sufficient healthy ordinary nodes,
  /// then the first locally readable provider profile by ID within that scope.
  /// Profiles are complete graphs and never enter ordinary-node probing.
  Future<ResolvedConnectionTarget> resolveTarget(
    ConnectionSettings settings, {
    RoutingConfiguration? custom,
    Future<void>? cancelled,
  }) => _resolve(settings, custom, cancelled, allowProfiles: true);

  Future<ResolvedConnectionTarget> _resolve(
    ConnectionSettings settings,
    RoutingConfiguration? custom,
    Future<void>? cancelled, {
    bool allowProfiles = false,
  }) async {
    if (settings.expert) return ResolvedConnectionTarget.entries(const []);
    if (settings.trafficMode == TrafficMode.custom && custom == null) {
      throw const ConnectionResolutionException(
        ConnectionResolutionFailure.invalidSettings,
      );
    }
    final required = settings.requiredEntries(
      customEntryCount: custom?.entryCount,
    );
    if (settings.selection.kind == SelectionKind.server &&
        settings.selection.id == settings.finalExitId) {
      throw const ConnectionResolutionException(
        ConnectionResolutionFailure.selfReference,
      );
    }

    final result = Completer<ResolvedConnectionTarget>();
    StreamSubscription<List<CoreConfigData>>? subscription;
    var probeStarted = false;

    void fail(ConnectionResolutionFailure reason, [int available = 0]) {
      if (!result.isCompleted) {
        result.completeError(
          ConnectionResolutionException(
            reason,
            requiredCount: required,
            availableCount: available,
          ),
        );
      }
    }

    late void Function({required bool finalRead}) listen;

    Future<void> probeAndReread(List<int> ids) async {
      try {
        await _probe(ids);
        if (result.isCompleted) return;
        await subscription?.cancel();
        if (result.isCompleted) return;
        // A Drift watch reload may trail the write Future. Read fresh rows after
        // the queue drains instead of declaring failure from its previous event.
        listen(finalRead: true);
      } catch (_) {
        fail(ConnectionResolutionFailure.probeFailed);
      }
    }

    void consider(List<CoreConfigData> rows, {required bool finalRead}) {
      if (result.isCompleted) return;

      void unavailable(
        ConnectionResolutionFailure reason, [
        int available = 0,
      ]) {
        if (allowProfiles && settings.selection.kind != SelectionKind.server) {
          final profiles =
              rows
                  .where(
                    (row) =>
                        row.type == CoreConfigType.Remnawave.name &&
                        _inScope(row, settings.selection),
                  )
                  .toList()
                ..sort((a, b) => a.id.compareTo(b.id));
          for (final row in profiles) {
            try {
              result.complete(ResolvedConnectionTarget.profile(row));
              return;
            } on FormatException {
              // Imported profiles were validated on save. Skip unreadable
              // retained rows without attempting runtime validation or retries.
            }
          }
        }
        fail(reason, available);
      }

      final seen = <int>{};
      final candidates = <({CoreConfigData row, ResolvedServer server})>[];
      for (final row in rows) {
        if (row.type != 'outbound' ||
            row.id <= 0 ||
            row.id == settings.finalExitId ||
            !_inScope(row, settings.selection) ||
            !seen.add(row.id)) {
          continue;
        }
        try {
          candidates.add((row: row, server: ResolvedServer.fromRow(row)));
        } on FormatException {
          // Retained malformed legacy data is repairable, not a connectable node.
        }
      }
      if (candidates.isEmpty) {
        unavailable(ConnectionResolutionFailure.selectionUnavailable);
        return;
      }
      if (candidates.length < required) {
        unavailable(
          ConnectionResolutionFailure.insufficientCandidates,
          candidates.length,
        );
        return;
      }
      if (settings.finalExitId != null) {
        final exits = rows.where(
          (row) => row.id == settings.finalExitId && row.type == 'outbound',
        );
        try {
          if (exits.isEmpty) {
            throw const FormatException('Final exit is missing');
          }
          ResolvedServer.fromRow(exits.first);
        } on FormatException {
          fail(ConnectionResolutionFailure.finalExitUnavailable);
          return;
        }
      }
      final successful =
          candidates
              .where(
                (candidate) =>
                    PingDelayConstants.isSuccessful(candidate.row.delay),
              )
              .toList()
            ..sort((a, b) {
              final delay = a.row.delay.compareTo(b.row.delay);
              return delay == 0 ? a.row.id.compareTo(b.row.id) : delay;
            });
      if (successful.length >= required) {
        result.complete(
          ResolvedConnectionTarget.entries(
            successful.take(required).map((candidate) => candidate.server),
          ),
        );
        return;
      }
      if (finalRead) {
        unavailable(
          ConnectionResolutionFailure.insufficientHealthyServers,
          successful.length,
        );
        return;
      }
      if (probeStarted) return;
      final unmeasured = candidates
          .where((candidate) => PingService.isUnmeasured(candidate.row))
          .map((candidate) => candidate.row.id)
          .toList();
      if (unmeasured.isEmpty) {
        unavailable(
          ConnectionResolutionFailure.insufficientHealthyServers,
          successful.length,
        );
        return;
      }
      probeStarted = true;
      unawaited(probeAndReread(unmeasured));
    }

    listen = ({required bool finalRead}) {
      var emitted = false;
      try {
        subscription = _rows().listen(
          (rows) {
            emitted = true;
            consider(rows, finalRead: finalRead);
          },
          onError: (Object _, StackTrace _) {
            fail(ConnectionResolutionFailure.readFailed);
          },
          onDone: () {
            if (!emitted) fail(ConnectionResolutionFailure.readFailed);
          },
        );
      } catch (_) {
        fail(ConnectionResolutionFailure.readFailed);
      }
    };
    if (cancelled != null) {
      unawaited(
        cancelled.then(
          (_) {
            fail(ConnectionResolutionFailure.cancelled);
          },
          onError: (Object _, StackTrace _) {
            fail(ConnectionResolutionFailure.cancelled);
          },
        ),
      );
    }
    listen(finalRead: false);
    try {
      return await result.future;
    } finally {
      await subscription?.cancel();
    }
  }

  static bool _inScope(CoreConfigData row, ServerSelection selection) =>
      switch (selection.kind) {
        SelectionKind.automatic => true,
        SelectionKind.source => row.subId == selection.id,
        SelectionKind.server => row.id == selection.id,
      };
}
