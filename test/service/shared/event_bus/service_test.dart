import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/service/servers/sort.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  final storage = _Preferences();
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = storage);
  setUp(() async {
    storage.failSortWrite = false;
    storage.sortWriteStarted = null;
    storage.sortWriteGate = null;
    await SharedPreferencesAsync().clear();
  });

  test('display order loads known values and defaults without rewriting unknown values', () async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    final preferences = PreferencesKey();
    for (final (value, expected) in [
      (null, ServerSortOrder.defaultOrder),
      ('future', ServerSortOrder.defaultOrder),
      ('default', ServerSortOrder.defaultOrder),
      ('name', ServerSortOrder.name),
      ('delay', ServerSortOrder.delay),
    ]) {
      await SharedPreferencesAsync().clear();
      if (value != null) await preferences.saveServerSort(value);
      await bus.asyncInitTheme();
      expect(bus.state.serverSort, expected);
      expect(await preferences.readServerSort(), value);
    }
  });

  test('display order is published only after persistence and reloads after restart', () async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    storage.sortWriteStarted = Completer<void>();
    final gate = storage.sortWriteGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final saving = bus.setServerSort(ServerSortOrder.name);
    await storage.sortWriteStarted!.future;
    expect(bus.state.serverSort, ServerSortOrder.defaultOrder);
    expect(await PreferencesKey().readServerSort(), isNull);
    gate.complete();
    await saving;
    expect(bus.state.serverSort, ServerSortOrder.name);
    expect(await PreferencesKey().readServerSort(), 'name');

    final restarted = AppEventBus();
    addTearDown(restarted.close);
    await restarted.asyncInitTheme();
    expect(restarted.state.serverSort, ServerSortOrder.name);
  });

  test(
    'failed display order save leaves the previous preference active',
    () async {
      final bus = AppEventBus();
      addTearDown(bus.close);
      await bus.setServerSort(ServerSortOrder.name);
      storage.failSortWrite = true;
      await expectLater(
        bus.setServerSort(ServerSortOrder.delay),
        throwsStateError,
      );
      expect(bus.state.serverSort, ServerSortOrder.name);
      expect(await PreferencesKey().readServerSort(), 'name');
    },
  );

  test('clearing local preferences resets the active display order', () async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    await bus.setServerSort(ServerSortOrder.delay);
    await PreferencesKey().clearUserDataPreferences();
    bus.resetServerSort();
    expect(bus.state.serverSort, ServerSortOrder.defaultOrder);
    expect(await PreferencesKey().readServerSort(), isNull);
  });

  test(
    'downloads remain active until concurrent tasks finish, including errors',
    () async {
      final bus = AppEventBus();
      addTearDown(bus.close);
      final first = Completer<void>();
      final second = Completer<void>();
      final values = <bool>[];
      final subscription = bus.stream.listen(
        (state) => values.add(state.downloading),
      );
      addTearDown(subscription.cancel);

      final a = bus.trackDownload(() => first.future);
      final b = bus.trackDownload(() => second.future);
      final failure = expectLater(b, throwsStateError);
      expect(bus.state.downloading, isTrue);
      first.complete();
      await a;
      expect(bus.state.downloading, isTrue);
      second.completeError(StateError('Download failed'));
      await failure;
      expect(bus.state.downloading, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(values, [true, false]);
    },
  );
}

final class _Preferences extends InMemorySharedPreferencesAsync {
  _Preferences() : super.empty();

  bool failSortWrite = false;
  Completer<void>? sortWriteStarted;
  Completer<void>? sortWriteGate;

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {
    if (key == 'app2.serverSort') {
      final started = sortWriteStarted;
      if (started != null && !started.isCompleted) {
        started.complete();
      }
      final gate = sortWriteGate;
      if (gate != null) await gate.future;
      if (failSortWrite) throw StateError('Preference storage unavailable');
    }
    return super.setString(key, value, options);
  }
}
