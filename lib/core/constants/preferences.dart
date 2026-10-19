import 'package:onexray/core/tools/json.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesKey {
  final _prefs = SharedPreferencesAsync();
  // New product settings deliberately do not inherit the retired UI's choices.
  // System VPN authorization is maintained by the platform, not these keys.
  static const _namespace = 'app2.';

  static final PreferencesKey _singleton = PreferencesKey._internal();

  factory PreferencesKey() => _singleton;

  PreferencesKey._internal();

  static const _privacyAccepted = "${_namespace}privacyAccepted";

  Future<bool> readPrivacyAccepted() async {
    final value = await _prefs.getBool(_privacyAccepted);
    if (value == null) {
      return false;
    }
    return value;
  }

  Future<void> savePrivacyAccepted(bool value) async {
    await _prefs.setBool(_privacyAccepted, value);
  }

  static const _firstRun = "${_namespace}firstRun";

  Future<bool> readFirstRun() async {
    final value = await _prefs.getBool(_firstRun);
    if (value == null) {
      return true;
    }
    return value;
  }

  Future<void> saveFirstRun(bool value) async {
    await _prefs.setBool(_firstRun, value);
  }

  static const _appUpdateLastCheckTimestamp =
      "${_namespace}appUpdateLastCheckTimestamp";

  Future<DateTime?> readAppUpdateLastCheckTimestamp() async {
    final value = await _prefs.getInt(_appUpdateLastCheckTimestamp);
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }

  Future<void> saveAppUpdateLastCheckTimestamp(DateTime date) async {
    final timestamp = date.millisecondsSinceEpoch ~/ 1000;
    await _prefs.setInt(_appUpdateLastCheckTimestamp, timestamp);
  }

  static const _appUpdateSkippedVersion =
      "${_namespace}appUpdateSkippedVersion";

  Future<String?> readAppUpdateSkippedVersion() async {
    return _prefs.getString(_appUpdateSkippedVersion);
  }

  Future<void> saveAppUpdateSkippedVersion(String value) async {
    await _prefs.setString(_appUpdateSkippedVersion, value);
  }

  static const _pingState = "${_namespace}pingState";

  Future<Map<String, dynamic>?> readPingState() async {
    final value = await _prefs.getString(_pingState);
    if (value != null) {
      return JsonTool.decodeBase64ToJson(value);
    }
    return null;
  }

  Future<void> savePingState(Map<String, dynamic> value) async {
    final text = JsonTool.encodeJsonToBase64(value);
    await _prefs.setString(_pingState, text);
  }

  static const _hideDockIcon = "${_namespace}hideIconInDock";

  Future<bool> readHideDockIcon() async {
    final value = await _prefs.getBool(_hideDockIcon);
    if (value == null) {
      return false;
    }
    return value;
  }

  Future<void> saveHideDockIcon(bool value) async {
    await _prefs.setBool(_hideDockIcon, value);
  }

  static const _desktopStartHidden = "${_namespace}desktopStartHidden";

  Future<bool> readDesktopStartHidden() async {
    return await _prefs.getBool(_desktopStartHidden) ?? false;
  }

  Future<void> saveDesktopStartHidden(bool value) async {
    await _prefs.setBool(_desktopStartHidden, value);
  }

  static const _connectOnAppLaunch = "${_namespace}connectOnAppLaunch";

  Future<bool> readConnectOnAppLaunch() async {
    return await _prefs.getBool(_connectOnAppLaunch) ?? false;
  }

  Future<void> saveConnectOnAppLaunch(bool value) async {
    await _prefs.setBool(_connectOnAppLaunch, value);
  }

  static const _autoUpdate = "${_namespace}autoUpdate";

  Future<Map<String, dynamic>?> readAutoUpdate() async {
    final value = await _prefs.getString(_autoUpdate);
    if (value != null) {
      return JsonTool.decodeBase64ToJson(value);
    }
    return null;
  }

  Future<void> saveAutoUpdate(Map<String, dynamic> value) async {
    final text = JsonTool.encodeJsonToBase64(value);
    await _prefs.setString(_autoUpdate, text);
  }

  static const _backup = '${_namespace}backup';
  static const _localApi = '${_namespace}localApi';
  static const _automaticBackup = '${_namespace}automaticBackup';
  static const _backupInterval = '${_namespace}backupInterval';

  Future<Map<String, dynamic>?> readLocalApi() async {
    final value = await _prefs.getString(_localApi);
    return value == null
        ? null
        : JsonTool.decoder.convert(value) as Map<String, dynamic>;
  }

  Future<void> saveLocalApi(Map<String, dynamic> value) =>
      _prefs.setString(_localApi, JsonTool.encoder.convert(value));

  Future<Map<String, dynamic>?> readBackup() async {
    final value = await _prefs.getString(_backup);
    return value == null ? null : JsonTool.decodeBase64ToJson(value);
  }

  Future<void> saveBackup(Map<String, dynamic> value) =>
      _prefs.setString(_backup, JsonTool.encodeJsonToBase64(value));

  Future<bool> readAutomaticBackup() async =>
      await _prefs.getBool(_automaticBackup) ?? true;

  Future<void> saveAutomaticBackup(bool value) =>
      _prefs.setBool(_automaticBackup, value);

  Future<int?> readBackupInterval() => _prefs.getInt(_backupInterval);

  Future<void> saveBackupInterval(int hours) =>
      _prefs.setInt(_backupInterval, hours);

  static const _themeCode = "${_namespace}themeCode";

  Future<String?> readThemeCode() async {
    return _prefs.getString(_themeCode);
  }

  Future<void> saveThemeCode(String value) async {
    await _prefs.setString(_themeCode, value);
  }

  static const _languageCode = "${_namespace}languageCode";

  Future<String?> readLanguageCode() async {
    return _prefs.getString(_languageCode);
  }

  Future<void> saveLanguageCode(String value) async {
    await _prefs.setString(_languageCode, value);
  }

  static const _serverSort = '${_namespace}serverSort';

  Future<String?> readServerSort() => _prefs.getString(_serverSort);

  Future<void> saveServerSort(String value) =>
      _prefs.setString(_serverSort, value);

  Future<void> clearUserDataPreferences() async {
    await Future.wait([
      _prefs.remove('app2.runningConfigId'),
      _prefs.remove('app2.lastConfigId'),
      _prefs.remove('app2.vpnStartTimestamp'),
      _prefs.remove(_appUpdateLastCheckTimestamp),
      _prefs.remove(_appUpdateSkippedVersion),
      _prefs.remove(_pingState),
      _prefs.remove(_autoUpdate),
      _prefs.remove(_backup),
      _prefs.remove(_localApi),
      _prefs.remove(_automaticBackup),
      _prefs.remove(_backupInterval),
      _prefs.remove(_serverSort),
      _prefs.remove('app2.xraySettingId'),
      _prefs.remove(_desktopStartHidden),
      _prefs.remove(_connectOnAppLaunch),
    ]);
  }
}
