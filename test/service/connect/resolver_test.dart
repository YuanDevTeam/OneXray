import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';

void main() {
  test(
    'unknown selection kinds use the default while known fields are checked',
    () {
      for (final kind in ['region', 'futureSelection']) {
        final selection = ServerSelection.fromJson({
          'kind': kind,
          'region': 'SG',
        });
        expect(selection.toJson(), {'kind': 'automatic'});
      }
      expect(ServerSelection.fromJson({'kind': 'server', 'id': 7}).id, 7);
      expect(
        () => ServerSelection.fromJson({'kind': 'server', 'id': '7'}),
        throwsA(isA<TypeError>()),
      );
    },
  );
  test(
    'automatic, source and fixed selections retain distinct same-name IDs',
    () async {
      final rows = [
        _row(1, delay: 60, source: 1, region: 'US'),
        _row(2, delay: 20, source: 2, region: 'US'),
        _row(3, delay: 0, source: 0, region: 'CN'),
        _row(4, delay: 1, type: 'raw'),
      ];
      final resolver = _oneShot(rows);
      Future<List<int>> selected(ServerSelection selection, int count) async =>
          (await resolver.resolve(
            ConnectionSettings(
              selection: selection,
              smart: SmartRoutingSettings(entryCount: count),
            ),
          )).map((node) => node.id).toList();
      expect(await selected(const ServerSelection.automatic(), 2), [3, 2]);
      expect(await selected(const ServerSelection.source(1), 1), [1]);
      expect(await selected(const ServerSelection.source(0), 1), [3]);
      expect(await selected(const ServerSelection.server(2), 3), [2]);
    },
  );

  test(
    'All VPN is one node and Custom uses slots without inheriting Smart exit',
    () async {
      final resolver = _oneShot([
        _row(1, delay: 30),
        _row(2, delay: 10),
        _row(3, delay: 20),
      ]);
      final smart = SmartRoutingSettings(entryCount: 3, finalExitId: 2);
      final allVpn = await resolver.resolve(
        ConnectionSettings(trafficMode: TrafficMode.allVpn, smart: smart),
      );
      expect(allVpn.map((node) => node.id), [2]);
      final custom = await resolver.resolve(
        ConnectionSettings(trafficMode: TrafficMode.custom, smart: smart),
        custom: _custom(2),
      );
      expect(custom.map((node) => node.id), [2, 3]);
      final fixed = await resolver.resolve(
        ConnectionSettings(
          trafficMode: TrafficMode.custom,
          selection: const ServerSelection.server(1),
          smart: smart,
        ),
        custom: _custom(3),
      );
      expect(fixed.map((node) => node.id), [1]);
      expect(await resolver.resolve(ConnectionSettings(expert: true)), isEmpty);
    },
  );

  test(
    'Smart excludes the final exit, rejects a self-loop and missing exit',
    () async {
      final resolver = _oneShot([
        _row(1, delay: 20),
        _row(2, delay: 1),
        _row(3, delay: 10),
      ]);
      final result = await resolver.resolve(
        ConnectionSettings(
          smart: SmartRoutingSettings(entryCount: 2, finalExitId: 2),
        ),
      );
      expect(result.map((node) => node.id), [3, 1]);
      await expectLater(
        resolver.resolve(
          ConnectionSettings(
            selection: const ServerSelection.server(2),
            smart: SmartRoutingSettings(finalExitId: 2),
          ),
        ),
        _fails(ConnectionResolutionFailure.selfReference),
      );
      await expectLater(
        resolver.resolve(
          ConnectionSettings(smart: SmartRoutingSettings(finalExitId: 9)),
        ),
        _fails(ConnectionResolutionFailure.finalExitUnavailable),
      );
    },
  );

  test('missing scope and too few candidates fail without changing selection or probing', () async {
    final selection = const ServerSelection.source(99);
    final resolver = _oneShot([_row(1)]);
    await expectLater(
      resolver.resolve(ConnectionSettings(selection: selection)),
      _fails(ConnectionResolutionFailure.selectionUnavailable),
    );
    expect(selection.id, 99);
    await expectLater(
      resolver.resolve(
        ConnectionSettings(smart: SmartRoutingSettings(entryCount: 2)),
      ),
      _fails(ConnectionResolutionFailure.insufficientCandidates),
    );
    await expectLater(
      _oneShot([]).resolve(ConnectionSettings()),
      _fails(ConnectionResolutionFailure.selectionUnavailable),
    );
    await expectLater(
      resolver.resolve(ConnectionSettings(trafficMode: TrafficMode.custom)),
      _fails(ConnectionResolutionFailure.invalidSettings),
    );
  });

  test(
    'only successful delays qualify; unknown candidates are probed once',
    () async {
      var rows = [
        _row(1, delay: PingDelayConstants.unknown),
        _row(2, delay: PingDelayConstants.unknown),
        _row(3, delay: PingDelayConstants.error),
        _row(4, delay: PingDelayConstants.timeout),
        _row(5, delay: -1),
      ];
      final probes = <List<int>>[];
      final resolver = ConnectionResolver(
        rows: () => Stream.value(rows),
        probe: (ids) async {
          probes.add(ids);
          rows = [
            _row(1, delay: 50),
            _row(2, delay: PingDelayConstants.error),
            ...rows.skip(2),
          ];
        },
      );
      final result = await resolver.resolve(ConnectionSettings());
      expect(probes, [
        [1, 2],
      ]);
      expect(result.single.id, 1);
    },
  );

  test(
    'fully failed or unrepairable candidates do not trigger an endless retry',
    () async {
      await expectLater(
        _oneShot([
          _row(1, delay: PingDelayConstants.error),
          _row(2, delay: PingDelayConstants.timeout),
        ]).resolve(ConnectionSettings()),
        _fails(ConnectionResolutionFailure.insufficientHealthyServers),
      );
      var probes = 0;
      final resolver = ConnectionResolver(
        rows: () => Stream.value([_row(1, delay: PingDelayConstants.unknown)]),
        probe: (_) async {
          probes++;
        },
      );
      await expectLater(
        resolver.resolve(ConnectionSettings()),
        _fails(ConnectionResolutionFailure.insufficientHealthyServers),
      );
      expect(probes, 1);
      await expectLater(
        _oneShot([_row(1).copyWith(data: const Value('not base64'))])
            .resolve(ConnectionSettings()),
        _fails(ConnectionResolutionFailure.selectionUnavailable),
      );
    },
  );

  test('a watched batch resolves early and later updates cannot mutate the snapshot', () async {
    final rows = _Rows([
      _row(1, delay: PingDelayConstants.unknown),
      _row(2, delay: PingDelayConstants.unknown),
    ]);
    addTearDown(rows.close);
    final started = Completer<void>();
    final remaining = Completer<void>();
    addTearDown(() {
      if (!remaining.isCompleted) remaining.complete();
    });
    final resolver = ConnectionResolver(
      rows: rows.watch,
      probe: (_) {
        started.complete();
        return remaining.future;
      },
    );
    final resolving = resolver.resolve(ConnectionSettings());
    await started.future;
    rows.update([
      _row(1, delay: 30),
      _row(2, delay: PingDelayConstants.unknown),
    ]);
    final snapshots = await resolving;
    expect(remaining.isCompleted, isFalse);
    expect(rows.listeners, 0);
    rows.update([_row(1, delay: 80, name: 'Changed'), _row(2, delay: 1)]);
    remaining.complete();
    expect(snapshots.single.id, 1);
    expect(snapshots.single.name, 'Same name');
    snapshots.single.outbound['tag'] = 'Changed copy';
    expect(snapshots.single.name, 'Same name');
    expect(() => snapshots.clear(), throwsUnsupportedError);
  });

  test(
    'cancellation releases the watch without cancelling background probing',
    () async {
      final rows = _Rows([_row(1, delay: PingDelayConstants.unknown)]);
      addTearDown(rows.close);
      final started = Completer<void>();
      final remaining = Completer<void>();
      addTearDown(() {
        if (!remaining.isCompleted) remaining.complete();
      });
      final cancel = Completer<void>();
      final resolver = ConnectionResolver(
        rows: rows.watch,
        probe: (_) {
          started.complete();
          return remaining.future;
        },
      );
      final resolving = resolver.resolve(
        ConnectionSettings(),
        cancelled: cancel.future,
      );
      await started.future;
      final expected = expectLater(
        resolving,
        _fails(ConnectionResolutionFailure.cancelled),
      );
      cancel.complete();
      await expected;
      expect(rows.listeners, 0);
      expect(remaining.isCompleted, isFalse);
      remaining.complete();
    },
  );

  test(
    'read and probe failures are structured and close their watches',
    () async {
      await expectLater(
        ConnectionResolver(rows: () => Stream.error(StateError('read')))
            .resolve(ConnectionSettings()),
        _fails(ConnectionResolutionFailure.readFailed),
      );
      final rows = _Rows([_row(1, delay: PingDelayConstants.unknown)]);
      addTearDown(rows.close);
      await expectLater(
        ConnectionResolver(
          rows: rows.watch,
          probe: (_) => Future.error(StateError('probe')),
        ).resolve(ConnectionSettings()),
        _fails(ConnectionResolutionFailure.probeFailed),
      );
      expect(rows.listeners, 0);
    },
  );
}

ConnectionResolver _oneShot(List<CoreConfigData> rows) => ConnectionResolver(
  rows: () => Stream.value(rows),
  probe: (_) async {
    fail('This selection must not probe');
  },
);

Matcher _fails(ConnectionResolutionFailure reason) => throwsA(
  isA<ConnectionResolutionException>().having(
    (error) => error.reason,
    'reason',
    reason,
  ),
);

CoreConfigData _row(
  int id, {
  int delay = 10,
  int source = 0,
  String region = 'US',
  String type = 'outbound',
  String name = 'Same name',
}) => CoreConfigData(
  id: id,
  name: name,
  type: type,
  tags: 'socks',
  delay: delay,
  subId: source,
  countryCode: region,
  favorite: false,
  data: base64Encode(
    utf8.encode(
      jsonEncode({
        'outbounds': [
          {
            'tag': name,
            'protocol': 'socks',
            'settings': {'address': '127.0.0.1', 'port': 1080},
          },
        ],
      }),
    ),
  ),
);

RoutingProfileState _custom(int count) =>
    RoutingProfileState(name: 'Custom', entryCount: count);

class _Rows {
  List<CoreConfigData> current;
  final changes = StreamController<List<CoreConfigData>>.broadcast();
  var listeners = 0;
  _Rows(this.current);

  Stream<List<CoreConfigData>> watch() => Stream.multi((output) {
    listeners++;
    final subscription = changes.stream.listen(
      output.add,
      onDone: output.close,
    );
    output.onCancel = () async {
      listeners--;
      await subscription.cancel();
    };
    output.add(current);
  });

  void update(List<CoreConfigData> rows) {
    current = rows;
    changes.add(rows);
  }

  Future<void> close() => changes.close();
}
