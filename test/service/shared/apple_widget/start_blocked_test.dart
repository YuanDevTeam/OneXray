import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/advanced/tunnel/android/automation/service.dart';

void main() {
  test(
    'maintenance blocks and resumes the iOS native saved-start gate',
    () async {
      final apple = _AppleApi();
      final android = _AndroidApi();
      final service = AndroidAutomationService(
        api: android,
        supported: false,
        appleApi: apple,
        supportedIOS: true,
      );
      await service.setStartBlocked(true);
      await service.setStartBlocked(false);
      await service.clear();
      expect(apple.blocked, [true, false]);
      expect(android.blocked, isEmpty);
      expect(android.clears, 0);
    },
  );

  test(
    'Android maintenance keeps its existing bridge and authorization',
    () async {
      final apple = _AppleApi();
      final android = _AndroidApi();
      final service = AndroidAutomationService(
        api: android,
        supported: true,
        appleApi: apple,
        supportedIOS: false,
      );
      await service.setStartBlocked(true);
      await service.setStartBlocked(false);
      await service.clear();
      expect(android.blocked, [true, false]);
      expect(android.clears, 1);
      expect(apple.blocked, isEmpty);
    },
  );
}

class _AppleApi extends AppleWidgetHostApi {
  final blocked = <bool>[];

  @override
  Future<void> setStartBlocked(bool value) async => blocked.add(value);
}

class _AndroidApi extends AndroidAutomationHostApi {
  final blocked = <bool>[];
  var clears = 0;

  @override
  Future<void> setStartBlocked(bool value) async => blocked.add(value);

  @override
  Future<void> clear() async => clears++;
}
