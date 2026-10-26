import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/apple_widget/service.dart';
import 'package:onexray/service/shared/menu/short_cut/service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cold intent is consumed once and suppresses launch auto-connect',
    () async {
      final events = StreamController<void>.broadcast(sync: true);
      addTearDown(events.close);
      var suppressed = 0;
      final shortcuts = ShortCutService.forTesting(
        suppressAutoConnect: () => suppressed++,
      );
      final pending = <String>['stopVpn'];
      final actions = <ShortCutAction>[];
      final service = AppleWidgetService.forTesting(
        events: events.stream,
        takeAction: () async => pending.isEmpty ? null : pending.removeAt(0),
        setLanguage: (_) async {},
        receive: shortcuts.receive,
      );
      addTearDown(service.dispose);
      await service.initialize();
      expect(suppressed, 1);
      expect(actions, isEmpty);
      shortcuts.attach((action) async => actions.add(action));
      await pumpEventQueue();
      expect(actions, [ShortCutAction.stopVpn]);
      await service.initialize();
      events.add(null);
      await pumpEventQueue();
      expect(actions, [ShortCutAction.stopVpn]);
    },
  );

  test(
    'stop is delivered while a foreground start remains in progress',
    () async {
      final events = StreamController<void>.broadcast(sync: true);
      addTearDown(events.close);
      final starting = Completer<void>();
      final actions = <ShortCutAction>[];
      final shortcuts = ShortCutService.forTesting(suppressAutoConnect: () {});
      shortcuts.attach((action) async {
        actions.add(action);
        if (action == ShortCutAction.startVpn) await starting.future;
      });
      final pending = <String>[];
      final service = AppleWidgetService.forTesting(
        events: events.stream,
        takeAction: () async => pending.isEmpty ? null : pending.removeAt(0),
        setLanguage: (_) async {},
        receive: shortcuts.receive,
      );
      addTearDown(service.dispose);
      await service.initialize();
      pending.add('startVpn');
      events.add(null);
      await pumpEventQueue();
      pending.add('stopVpn');
      events.add(null);
      await pumpEventQueue();
      expect(actions, [ShortCutAction.startVpn, ShortCutAction.stopVpn]);
      starting.complete();
      await pumpEventQueue();
    },
  );

  test('an event during an empty native read is not lost', () async {
    final events = StreamController<void>.broadcast(sync: true);
    addTearDown(events.close);
    final firstRead = Completer<String?>();
    var reads = 0;
    final received = <String>[];
    final service = AppleWidgetService.forTesting(
      events: events.stream,
      takeAction: () async => switch (reads++) {
        0 => firstRead.future,
        1 => 'stopVpn',
        _ => null,
      },
      setLanguage: (_) async {},
      receive: (action) async => received.add(action),
    );
    addTearDown(service.dispose);
    final ready = service.initialize();
    events.add(null);
    firstRead.complete(null);
    await ready;
    expect(received, ['stopVpn']);
  });

  test(
    'widget URL only opens the connection page and rejects control URLs',
    () async {
      final events = StreamController<void>.broadcast();
      addTearDown(events.close);
      final received = <String>[];
      final service = AppleWidgetService.forTesting(
        events: events.stream,
        takeAction: () async => null,
        setLanguage: (_) async {},
        receive: (action) async => received.add(action),
      );
      expect(
        service.receiveOpenUri(Uri.parse('onexray://widget/connect')),
        isTrue,
      );
      for (final text in [
        'onexray://widget/startVpn',
        'onexray://widget/stopVpn',
        'onexray://widget/connect?action=startVpn',
        'onexray://widget/connect?',
        'onexray://widget/connect#',
        'onexray://user@widget/connect',
        'onexray://widget:80/connect',
        'https://widget/connect',
        'onexray://onexray.com/config/add',
      ]) {
        expect(service.receiveOpenUri(Uri.parse(text)), isFalse, reason: text);
      }
      await pumpEventQueue();
      expect(received, ['openConnect']);
    },
  );

  test('native input is restricted and language is sent separately', () async {
    final events = StreamController<void>.broadcast();
    addTearDown(events.close);
    final pending = <String>['updateSubscriptions', 'stopVpn'];
    final actions = <String>[];
    final languages = <String>[];
    final service = AppleWidgetService.forTesting(
      events: events.stream,
      takeAction: () async => pending.isEmpty ? null : pending.removeAt(0),
      setLanguage: (language) async => languages.add(language),
      receive: (action) async => actions.add(action),
    );
    addTearDown(service.dispose);
    await service.initialize();
    await service.setLanguage('zh_Hant');
    binding.platformDispatcher.localeTestValue = const Locale('ru');
    addTearDown(binding.platformDispatcher.clearLocaleTestValue);
    await service.setLanguage('system');
    expect(actions, ['stopVpn']);
    expect(languages, ['zh-Hant', 'ru']);
  });

  test(
    'resume recovers a pending intent and disposed service stops reading',
    () async {
      final events = StreamController<void>.broadcast(sync: true);
      addTearDown(events.close);
      final pending = <String>[];
      final actions = <String>[];
      final service = AppleWidgetService.forTesting(
        events: events.stream,
        takeAction: () async => pending.isEmpty ? null : pending.removeAt(0),
        setLanguage: (_) async {},
        receive: (action) async => actions.add(action),
      );
      await service.initialize();
      pending.add('stopVpn');
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(actions, ['stopVpn']);
      service.dispose();
      pending.add('startVpn');
      events.add(null);
      await pumpEventQueue();
      expect(actions, ['stopVpn']);
      expect(pending, ['startVpn']);
    },
  );

  test('other platforms never call the Apple bridge', () async {
    final events = StreamController<void>.broadcast();
    addTearDown(events.close);
    final service = AppleWidgetService.forTesting(
      enabled: false,
      events: events.stream,
      takeAction: () async => throw StateError('No Apple bridge'),
      setLanguage: (_) async => throw StateError('No Apple bridge'),
      receive: (_) async => throw StateError('No Apple actions'),
    );
    await service.initialize();
    await service.setLanguage('en');
    expect(
      service.receiveOpenUri(Uri.parse('onexray://widget/connect')),
      isFalse,
    );
    service.dispose();
  });
}
