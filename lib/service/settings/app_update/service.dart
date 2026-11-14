import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppUpdateCheckStatus { available, upToDate, failed }

enum AppUpdateDestination {
  appStore,
  googlePlay,
  microsoftStore,
  githubRelease,
}

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final Uri releaseUri;
  final Uri updateUri;
  final AppUpdateDestination destination;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.releaseUri,
    required this.updateUri,
    required this.destination,
  });
}

class AppUpdateCheckResult {
  final AppUpdateCheckStatus status;
  final AppUpdateInfo? updateInfo;
  final Object? error;

  const AppUpdateCheckResult._(this.status, this.updateInfo, [this.error]);

  const AppUpdateCheckResult.available(AppUpdateInfo updateInfo)
    : this._(AppUpdateCheckStatus.available, updateInfo);

  const AppUpdateCheckResult.upToDate()
    : this._(AppUpdateCheckStatus.upToDate, null);

  const AppUpdateCheckResult.failed([Object? error])
    : this._(AppUpdateCheckStatus.failed, null, error);
}

class AppUpdateService {
  static final AppUpdateService _singleton = AppUpdateService._internal();

  factory AppUpdateService() => _singleton;

  AppUpdateService._internal()
    : _client = NetClient(),
      _operatingSystem = Platform.operatingSystem,
      _useSystemExtension = AppHostApi().useSystemExtension;

  @visibleForTesting
  AppUpdateService.forTesting({
    required this._client,
    required this._operatingSystem,
    Future<bool> Function()? useSystemExtension,
  }) : _useSystemExtension =
           useSystemExtension ?? AppHostApi().useSystemExtension;

  final NetClient _client;
  final String _operatingSystem;
  final Future<bool> Function() _useSystemExtension;

  static const _githubLatestReleaseApi =
      "https://api.github.com/repos/YuanDevTeam/OneXray/releases/latest";
  static const _githubLatestReleaseUrl =
      "https://github.com/YuanDevTeam/OneXray/releases/latest";
  static const _appStoreUrl =
      "https://apps.apple.com/us/app/onexray/id6745748773";
  static const _googlePlayUrl =
      "https://play.google.com/store/apps/details?id=net.yuandev.onexray";
  static const _microsoftStoreUrl =
      "https://apps.microsoft.com/detail/9NJ0MVHW215D";
  static const _automaticCheckInterval = Duration(days: 1);

  Future<AppUpdateCheckResult> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = _parseVersion(packageInfo.version);
      if (currentVersion == null) {
        ygLogger(
          "checkForUpdate invalid current version: ${packageInfo.version}",
        );
        return const AppUpdateCheckResult.failed();
      }

      final releaseJson = await AppEventBus.instance.trackDownload(
        () => _client.getJson(_githubLatestReleaseApi),
      );
      if (releaseJson == null) {
        return const AppUpdateCheckResult.failed();
      }

      final release = _GitHubRelease.fromJson(releaseJson);
      if (release == null) {
        ygLogger("checkForUpdate invalid release json");
        return const AppUpdateCheckResult.failed();
      }

      final latestVersion = _parseVersion(release.tagName);
      if (latestVersion == null) {
        ygLogger("checkForUpdate invalid release tag: ${release.tagName}");
        return const AppUpdateCheckResult.failed();
      }

      if (latestVersion.compareTo(currentVersion) > 0) {
        final updateUri = await _resolveUpdateUri(release.releaseUri);
        return AppUpdateCheckResult.available(
          AppUpdateInfo(
            currentVersion: packageInfo.version,
            latestVersion: latestVersion.toString(),
            releaseNotes: release.body,
            releaseUri: release.releaseUri,
            updateUri: updateUri.item1,
            destination: updateUri.item2,
          ),
        );
      }
      return const AppUpdateCheckResult.upToDate();
    } catch (e) {
      ygLogger("checkForUpdate error: $e");
      return AppUpdateCheckResult.failed(e);
    }
  }

  Future<bool> shouldRunAutomaticCheck() async {
    final lastCheck = await PreferencesKey().readAppUpdateLastCheckTimestamp();
    if (lastCheck == null) {
      return true;
    }
    return DateTime.now().difference(lastCheck) >= _automaticCheckInterval;
  }

  Future<void> recordAutomaticCheck() async {
    await PreferencesKey().saveAppUpdateLastCheckTimestamp(DateTime.now());
  }

  Future<bool> shouldShowAutomaticReminder(AppUpdateInfo updateInfo) async {
    final skippedVersion = await PreferencesKey().readAppUpdateSkippedVersion();
    return skippedVersion != updateInfo.latestVersion;
  }

  Future<void> skipVersion(AppUpdateInfo updateInfo) async {
    await PreferencesKey().saveAppUpdateSkippedVersion(
      updateInfo.latestVersion,
    );
  }

  Future<void> openUpdate(AppUpdateInfo updateInfo) async {
    if (!await launchUrl(updateInfo.updateUri)) {
      throw StateError('Could not open update page');
    }
  }

  Future<({Uri item1, AppUpdateDestination item2})> _resolveUpdateUri(
    Uri releaseUri,
  ) async {
    if (_operatingSystem == 'ios') {
      return (
        item1: Uri.parse(_appStoreUrl),
        item2: AppUpdateDestination.appStore,
      );
    }
    if (_operatingSystem == 'android') {
      return (
        item1: Uri.parse(_googlePlayUrl),
        item2: AppUpdateDestination.googlePlay,
      );
    }
    if (_operatingSystem == 'windows') {
      return (
        item1: Uri.parse(_microsoftStoreUrl),
        item2: AppUpdateDestination.microsoftStore,
      );
    }
    if (_operatingSystem == 'macos') {
      final useSystemExtension = await _useSystemExtension();
      if (!useSystemExtension) {
        return (
          item1: Uri.parse(_appStoreUrl),
          item2: AppUpdateDestination.appStore,
        );
      }
    }
    return (item1: releaseUri, item2: AppUpdateDestination.githubRelease);
  }

  Version? _parseVersion(String value) {
    var text = value.trim();
    if (text.startsWith("v") || text.startsWith("V")) {
      text = text.substring(1);
    }
    try {
      return Version.parse(text);
    } catch (_) {
      return null;
    }
  }
}

class _GitHubRelease {
  final String tagName;
  final String body;
  final Uri releaseUri;

  const _GitHubRelease({
    required this.tagName,
    required this.body,
    required this.releaseUri,
  });

  static _GitHubRelease? fromJson(Map<String, dynamic> json) {
    final tagName = json["tag_name"];
    if (tagName is! String || tagName.isEmpty) {
      return null;
    }
    final htmlUrl = json["html_url"];
    final releaseUri = htmlUrl is String && htmlUrl.isNotEmpty
        ? Uri.tryParse(htmlUrl)
        : Uri.tryParse(AppUpdateService._githubLatestReleaseUrl);
    if (releaseUri == null) {
      return null;
    }
    final body = json["body"];
    return _GitHubRelease(
      tagName: tagName,
      body: body is String ? body : "",
      releaseUri: releaseUri,
    );
  }
}
