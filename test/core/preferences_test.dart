import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';
import 'package:onexray/service/settings/backup/service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  final storage = InMemorySharedPreferencesAsync.empty();
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = storage);
  setUp(() async => SharedPreferencesAsync().clear());

  test(
    'server display order persists independently and clears with local data',
    () async {
      final preferences = PreferencesKey();
      expect(await preferences.readServerSort(), isNull);
      await preferences.saveServerSort('name');
      expect(await preferences.readServerSort(), 'name');
      await preferences.clearUserDataPreferences();
      expect(await preferences.readServerSort(), isNull);
    },
  );

  test(
    'backup interval is independent of data updates and clears with local data',
    () async {
      final preferences = PreferencesKey();
      final backup = BackupPreferences();
      final updates = AutoUpdateState()
        ..geoDataInterval = AutoUpdateInterval.oneWeek;
      await updates.saveToPreferences();
      expect(await backup.interval(), AutoUpdateInterval.threeDays);

      await backup.saveInterval(AutoUpdateInterval.oneDay);
      await updates.readFromPreferences();
      expect(updates.geoDataInterval, AutoUpdateInterval.oneWeek);
      expect(await preferences.readBackupInterval(), 24);

      updates.geoDataInterval = AutoUpdateInterval.threeDays;
      await updates.saveToPreferences();
      expect(await BackupPreferences().interval(), AutoUpdateInterval.oneDay);
      await preferences.clearUserDataPreferences();
      expect(await preferences.readBackupInterval(), null);
      expect(await backup.interval(), AutoUpdateInterval.threeDays);
    },
  );

  test(
    'automatic updates persist only global switches and intervals',
    () async {
      const settings = {
        'subscriptionEnabled': false,
        'subscriptionInterval': 24,
        'geoDataEnabled': true,
        'geoDataInterval': 168,
      };
      final preferences = PreferencesKey();
      await preferences.saveAutoUpdate(settings);
      final state = AutoUpdateState();
      await state.readFromPreferences();
      await state.saveToPreferences();
      expect(await preferences.readAutoUpdate(), settings);
    },
  );

  test(
    'new product ignores legacy preferences without clearing platform state',
    () async {
      final storage = SharedPreferencesAsync();
      await storage.setBool('privacyAccepted04', true);
      await storage.setBool('firstRun03', false);
      await storage.setBool('connectOnAppLaunch', true);
      await storage.setInt('runningConfigId', 42);
      final preferences = PreferencesKey();
      expect(await preferences.readPrivacyAccepted(), isFalse);
      expect(await preferences.readFirstRun(), isTrue);
      expect(await preferences.readConnectOnAppLaunch(), isFalse);
      expect(await storage.getInt('runningConfigId'), 42);
      await preferences.savePrivacyAccepted(true);
      expect(await preferences.readPrivacyAccepted(), isTrue);
      expect(await storage.getBool('privacyAccepted04'), isTrue);
    },
  );
}
