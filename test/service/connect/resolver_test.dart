import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';

void main() {
  test(
    'unknown selection kinds default while known IDs retain their type checks',
    () {
      expect(ServerSelection.fromJson({'kind': 'future'}).toJson(), {
        'kind': 'automatic',
      });
      expect(ServerSelection.fromJson({'kind': 'server', 'id': 7}).id, 7);
      expect(
        () => ServerSelection.fromJson({'kind': 'server', 'id': '7'}),
        throwsA(isA<TypeError>()),
      );
    },
  );

  test('successful cached delays rank first, then all non-success delays share an ID bucket', () async {
    final rows = [
      _row(8, delay: 0),
      _row(7, delay: 20),
      _row(6, delay: 20),
      _row(4, delay: PingDelayConstants.unknown),
      _row(1, delay: PingDelayConstants.error),
      _row(2, delay: PingDelayConstants.timeout),
      _row(3, delay: -1),
    ];
    final input = ConnectionSettings(
      smart: SmartRoutingSettings(entryCount: 3),
    );
    expect((await _oneShot(rows).resolve(input)).map((e) => e.id), [8, 6, 7]);
    expect(
      (await _oneShot(rows.skip(3).toList()).resolve(input)).map((e) => e.id),
      [1, 2, 3],
    );
    expect(
      (await _oneShot([rows[1], ...rows.skip(3)]).resolve(input))
          .map((e) => e.id),
      [7, 1, 2],
    );
    expect(
      (await _oneShot([rows[3]]).resolve(ConnectionSettings())).single.id,
      4,
    );
  });

  test('automatic, source, manual and fixed use distinct IDs and no delay admission', () async {
    final resolver = _oneShot([
      _row(1, delay: 60, source: 1),
      _row(2, delay: 20, source: 2),
      _row(3, delay: PingDelayConstants.unknown, source: 0),
      _row(4, type: 'raw'),
    ]);
    Future<List<int>> select(ServerSelection selection, int count) async =>
        (await resolver.resolve(
          ConnectionSettings(
            selection: selection,
            smart: SmartRoutingSettings(entryCount: count),
          ),
        )).map((e) => e.id).toList();
    expect(await select(const ServerSelection.automatic(), 3), [2, 1, 3]);
    expect(await select(const ServerSelection.source(1), 1), [1]);
    expect(await select(const ServerSelection.source(0), 1), [3]);
    expect(await select(const ServerSelection.server(3), 3), [3]);
  });

  test('All uses one, Custom uses slots, fixed uses one, Raw bypasses ordinary resolution', () async {
    final resolver = _oneShot([
      _row(1, delay: 30),
      _row(2, delay: 10),
      _row(3, delay: 20),
    ]);
    final smart = SmartRoutingSettings(entryCount: 3, finalExitId: 2);
    expect(
      (await resolver.resolve(
        ConnectionSettings(trafficMode: TrafficMode.allVpn, smart: smart),
      )).map((e) => e.id),
      [2],
    );
    expect(
      (await resolver.resolve(
        ConnectionSettings(trafficMode: TrafficMode.custom, smart: smart),
        custom: _custom(2),
      )).map((e) => e.id),
      [2, 3],
    );
    expect(
      (await resolver.resolve(
        ConnectionSettings(
          trafficMode: TrafficMode.custom,
          selection: const ServerSelection.server(1),
          smart: smart,
        ),
        custom: _custom(3),
      )).map((e) => e.id),
      [1],
    );
    expect(await resolver.resolve(ConnectionSettings(expert: true)), isEmpty);
  });

  test(
    'Smart validates and excludes the final exit independently of delay',
    () async {
      final resolver = _oneShot([
        _row(1, delay: PingDelayConstants.error),
        _row(2, delay: PingDelayConstants.unknown),
      ]);
      final result = await resolver.resolve(
        ConnectionSettings(smart: SmartRoutingSettings(finalExitId: 2)),
      );
      expect(result.single.id, 1);
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

  test(
    'bad JSON, invalid IDs and duplicates cannot satisfy structural count',
    () async {
      final resolver = _oneShot([
        _row(0),
        _row(-1),
        _row(1).copyWith(data: const Value('bad base64')),
        _row(1),
        _row(2, delay: PingDelayConstants.timeout),
      ]);
      expect((await resolver.resolve(ConnectionSettings())).single.id, 2);
      await expectLater(
        resolver.resolve(
          ConnectionSettings(smart: SmartRoutingSettings(entryCount: 2)),
        ),
        _fails(ConnectionResolutionFailure.insufficientCandidates),
      );
      await expectLater(
        resolver.resolve(
          ConnectionSettings(selection: const ServerSelection.source(99)),
        ),
        _fails(ConnectionResolutionFailure.selectionUnavailable),
      );
      await expectLater(
        resolver.resolve(ConnectionSettings(trafficMode: TrafficMode.custom)),
        _fails(ConnectionResolutionFailure.invalidSettings),
      );
    },
  );

  test('first rows are a snapshot; later measurements and row names do not replace it', () async {
    final rows = _Rows([
      _row(1, delay: PingDelayConstants.unknown),
      _row(2, delay: PingDelayConstants.unknown),
    ]);
    addTearDown(rows.close);
    final resolved = await ConnectionResolver(rows: rows.watch)
        .resolve(ConnectionSettings());
    expect(rows.listeners, 0);
    rows.update([_row(1, delay: 80, name: 'Changed'), _row(2, delay: 1)]);
    expect(resolved.single.id, 1);
    expect(resolved.single.name, 'Same name');
    expect(() => resolved.clear(), throwsUnsupportedError);
  });

  test(
    'cancellation closes a pending read and cannot become provider fallback',
    () async {
      final subscribed = Completer<void>(), cancel = Completer<void>();
      var closed = false;
      final rows = StreamController<List<CoreConfigData>>(
        onListen: subscribed.complete,
        onCancel: () {
          closed = true;
        },
      );
      addTearDown(rows.close);
      final resolving = ConnectionResolver(rows: () => rows.stream)
          .resolveTarget(ConnectionSettings(), cancelled: cancel.future);
      await subscribed.future;
      final expected = expectLater(
        resolving,
        _fails(ConnectionResolutionFailure.cancelled),
      );
      cancel.complete();
      await expected;
      expect(closed, isTrue);
    },
  );

  test('read exceptions and empty streams report readFailed', () async {
    for (final stream in [
      Stream<List<CoreConfigData>>.error(StateError('read')),
      const Stream<List<CoreConfigData>>.empty(),
    ]) {
      await expectLater(
        ConnectionResolver(rows: () => stream).resolve(ConnectionSettings()),
        _fails(ConnectionResolutionFailure.readFailed),
      );
    }
    await expectLater(
      ConnectionResolver(rows: () => throw StateError('read'))
          .resolve(ConnectionSettings()),
      _fails(ConnectionResolutionFailure.readFailed),
    );
  });

  test(
    'sufficient unmeasured or failed ordinary nodes win over a provider',
    () async {
      final target =
          await _oneShot([
            _profile(1),
            _row(2, delay: PingDelayConstants.unknown),
            _row(3, delay: PingDelayConstants.error),
          ]).resolveTarget(
            ConnectionSettings(smart: SmartRoutingSettings(entryCount: 2)),
          );
      expect(target.entries.map((e) => e.id), [2, 3]);
      expect(target.profile, isNull);
    },
  );

  test(
    'only a structural shortage uses the first readable same-scope provider',
    () async {
      final first = _profile(7);
      final resolver = _oneShot([
        _profile(2).copyWith(data: const Value('bad')),
        _profile(9),
        first,
        _row(20, delay: PingDelayConstants.error),
      ]);
      final target = await resolver.resolveTarget(
        ConnectionSettings(smart: SmartRoutingSettings(entryCount: 2)),
      );
      expect(target.entries, isEmpty);
      expect(target.profileRow, first);
      await expectLater(
        resolver.resolveTarget(
          ConnectionSettings(
            selection: const ServerSelection.source(0),
            smart: SmartRoutingSettings(entryCount: 2),
          ),
        ),
        _fails(ConnectionResolutionFailure.insufficientCandidates),
      );
      expect(
        (await resolver.resolveTarget(
          ConnectionSettings(selection: const ServerSelection.source(7)),
        )).profile?.id,
        7,
      );
    },
  );

  test(
    'fixed failed nodes remain fixed; fixed and Raw never acquire a provider',
    () async {
      final resolver = _oneShot([
        _profile(1),
        _row(2, delay: PingDelayConstants.error),
      ]);
      final fixed = await resolver.resolveTarget(
        ConnectionSettings(selection: const ServerSelection.server(2)),
      );
      expect(fixed.entries.single.id, 2);
      expect(fixed.profile, isNull);
      await expectLater(
        resolver.resolveTarget(
          ConnectionSettings(selection: const ServerSelection.server(99)),
        ),
        _fails(ConnectionResolutionFailure.selectionUnavailable),
      );
      final raw = await resolver.resolveTarget(
        ConnectionSettings(expert: true),
      );
      expect(raw.entries, isEmpty);
      expect(raw.profile, isNull);
    },
  );

  test('configuration, exit and read errors never retry a provider', () async {
    final rows = [_profile(1), _row(2, delay: PingDelayConstants.unknown)];
    await expectLater(
      _oneShot(rows)
          .resolveTarget(ConnectionSettings(trafficMode: TrafficMode.custom)),
      _fails(ConnectionResolutionFailure.invalidSettings),
    );
    await expectLater(
      _oneShot(rows).resolveTarget(
        ConnectionSettings(smart: SmartRoutingSettings(finalExitId: 99)),
      ),
      _fails(ConnectionResolutionFailure.finalExitUnavailable),
    );
    await expectLater(
      _oneShot([_profile(1).copyWith(data: const Value('bad')), _row(2)])
          .resolveTarget(
            ConnectionSettings(smart: SmartRoutingSettings(entryCount: 2)),
          ),
      _fails(ConnectionResolutionFailure.insufficientCandidates),
    );
  });
}

CoreConfigData _profile(int id, {int source = 7}) => _row(
  id,
  source: source,
  type: 'Remnawave',
  delay: PingDelayConstants.unknown,
);

ConnectionResolver _oneShot(List<CoreConfigData> rows) =>
    ConnectionResolver(rows: () => Stream.value(rows));

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
  String type = 'outbound',
  String name = 'Same name',
}) => CoreConfigData(
  manualSortOrder: 0,
  id: id,
  name: name,
  type: type,
  tags: 'socks',
  delay: delay,
  subId: source,
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
