import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/menu/settings/service.dart';

void main() {
  test(
    'unready and modal requests only show the window and are not replayed',
    () async {
      final commands = StreamController<void>.broadcast(sync: true);
      var shown = 0;
      var opened = 0;
      var allowed = false;
      final owner = Object();
      final service = MacOSSettingsMenuService.forTesting(
        commands: commands.stream,
        showMainWindow: () async {
          shown++;
        },
      )..initialize();
      addTearDown(commands.close);
      addTearDown(service.dispose);

      await service.receive();
      service.attach(
        owner: owner,
        canNavigate: () => allowed,
        openSettings: () => opened++,
      );
      await pumpEventQueue();
      expect(shown, 1);
      expect(opened, 0);
      await service.receive();
      allowed = true;
      await pumpEventQueue();
      expect(shown, 2);
      expect(opened, 0);
      commands.add(null);
      await pumpEventQueue();
      expect(shown, 3);
      expect(opened, 1);
      service.detach(owner);
      await service.receive();
      expect(shown, 4);
      expect(opened, 1);
    },
  );

  for (final change in ['detach', 'replace', 'modal']) {
    test('window focus completion cannot navigate after $change', () async {
      final commands = StreamController<void>.broadcast(sync: true);
      final focused = Completer<void>();
      var shown = 0;
      var opened = 0;
      var allowed = true;
      final owner = Object();
      final service = MacOSSettingsMenuService.forTesting(
        commands: commands.stream,
        showMainWindow: () {
          shown++;
          return focused.future;
        },
      )..initialize();
      addTearDown(commands.close);
      addTearDown(service.dispose);
      service.attach(
        owner: owner,
        canNavigate: () => allowed,
        openSettings: () => opened++,
      );
      final opening = service.receive();
      await service.receive();
      expect(shown, 1);
      switch (change) {
        case 'detach':
          service.detach(owner);
        case 'replace':
          service.attach(
            owner: Object(),
            canNavigate: () => true,
            openSettings: () => opened++,
          );
        case 'modal':
          allowed = false;
      }
      focused.complete();
      await opening;
      expect(opened, 0);
    });
  }

  test(
    'a modal closing during window focus does not revive its request',
    () async {
      final commands = StreamController<void>.broadcast(sync: true);
      final focused = Completer<void>();
      var allowed = false;
      var opened = 0;
      final service = MacOSSettingsMenuService.forTesting(
        commands: commands.stream,
        showMainWindow: () => focused.future,
      )..initialize();
      addTearDown(commands.close);
      addTearDown(service.dispose);
      service.attach(
        owner: Object(),
        canNavigate: () => allowed,
        openSettings: () => opened++,
      );
      final opening = service.receive();
      allowed = true;
      focused.complete();
      await opening;
      expect(opened, 0);
      await service.receive();
      expect(opened, 1);
    },
  );

  test(
    'unsupported hosts do not listen or perform a window operation',
    () async {
      final commands = StreamController<void>.broadcast(sync: true);
      final service = MacOSSettingsMenuService.forTesting(
        commands: commands.stream,
        showMainWindow: () async => fail('Unsupported platform'),
        supported: false,
      )..initialize();
      addTearDown(commands.close);
      addTearDown(service.dispose);
      service.attach(
        owner: Object(),
        canNavigate: () => true,
        openSettings: () => fail('Unsupported platform'),
      );
      expect(commands.hasListener, isFalse);
      commands.add(null);
      await service.receive();
    },
  );
}
