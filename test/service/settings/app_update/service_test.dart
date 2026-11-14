import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  const editionChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.onexray.BridgeHostApi.useSystemExtension',
    BridgeHostApi.pigeonChannelCodec,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const releaseUrl =
      'https://github.com/YuanDevTeam/OneXray/releases/tag/v26.11.6';
  const appStoreUrl = 'https://apps.apple.com/us/app/onexray/id6745748773';
  const googlePlayUrl =
      'https://play.google.com/store/apps/details?id=net.yuandev.onexray';
  const microsoftStoreUrl = 'https://apps.microsoft.com/detail/9NJ0MVHW215D';
  late _ReleaseResponse response;
  late NetClient client;
  late List<String> launched;
  late bool launchSucceeded;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'OneXray',
      packageName: 'net.yuandev.onexray',
      version: '26.11.5',
      buildNumber: '1',
      buildSignature: '',
    );
    final bus = AppEventBus();
    addTearDown(bus.close);
    response = _ReleaseResponse({
      'tag_name': 'v26.11.6',
      'body': 'Release notes from GitHub',
      'html_url': releaseUrl,
    });
    final dio = Dio()..httpClientAdapter = response;
    addTearDown(dio.close);
    client = NetClient.forTesting(dio);
    launched = [];
    launchSucceeded = true;
    messenger.setMockMethodCallHandler(launcherChannel, (call) async {
      expect(call.method, 'launch');
      launched.add((call.arguments as Map)['url'] as String);
      return launchSucceeded;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(launcherChannel, null),
    );
  });

  for (final (name, operatingSystem, systemExtension, destination, url) in [
    ('iOS', 'ios', false, AppUpdateDestination.appStore, appStoreUrl),
    (
      'macOS ordinary edition',
      'macos',
      false,
      AppUpdateDestination.appStore,
      appStoreUrl,
    ),
    (
      'Android',
      'android',
      false,
      AppUpdateDestination.googlePlay,
      googlePlayUrl,
    ),
    (
      'Windows EXE and MSIX',
      'windows',
      false,
      AppUpdateDestination.microsoftStore,
      microsoftStoreUrl,
    ),
    ('macOS SE', 'macos', true, AppUpdateDestination.githubRelease, releaseUrl),
    ('Linux', 'linux', false, AppUpdateDestination.githubRelease, releaseUrl),
  ]) {
    test(
      '$name discovers GitHub releases and opens its update target',
      () async {
        var editionChecks = 0;
        final service = AppUpdateService.forTesting(
          client: client,
          operatingSystem: operatingSystem,
          useSystemExtension: () async {
            editionChecks++;
            return systemExtension;
          },
        );

        final result = await service.checkForUpdate();

        expect(result.status, AppUpdateCheckStatus.available);
        final info = result.updateInfo!;
        expect(info.currentVersion, '26.11.5');
        expect(info.latestVersion, '26.11.6');
        expect(info.releaseNotes, 'Release notes from GitHub');
        expect(info.releaseUri, Uri.parse(releaseUrl));
        expect(info.destination, destination);
        expect(info.updateUri, Uri.parse(url));
        expect(editionChecks, operatingSystem == 'macos' ? 1 : 0);
        expect(response.requests.single.method, 'GET');
        expect(
          response.requests.single.uri.toString(),
          'https://api.github.com/repos/YuanDevTeam/OneXray/releases/latest',
        );
        expect(launched, isEmpty);

        await service.openUpdate(info);

        expect(launched, [url]);
      },
    );
  }

  for (final systemExtension in [false, true]) {
    test(
      'macOS native edition probe selects ${systemExtension ? 'GitHub' : 'App Store'}',
      () async {
        var editionChecks = 0;
        messenger.setMockDecodedMessageHandler(editionChannel, (_) async {
          editionChecks++;
          return [systemExtension];
        });
        addTearDown(
          () => messenger.setMockDecodedMessageHandler(editionChannel, null),
        );
        final service = AppUpdateService.forTesting(
          client: client,
          operatingSystem: 'macos',
        );

        final result = await service.checkForUpdate();
        expect(result.status, AppUpdateCheckStatus.available);
        expect(editionChecks, 1);
        await service.openUpdate(result.updateInfo!);
        expect(launched, [systemExtension ? releaseUrl : appStoreUrl]);
      },
      skip: !Platform.isMacOS,
    );
  }

  test(
    'an up-to-date version does not resolve or open an update target',
    () async {
      response.release['tag_name'] = 'v26.11.5';
      final service = AppUpdateService.forTesting(
        client: client,
        operatingSystem: 'macos',
        useSystemExtension: () async => throw StateError('No update to open'),
      );

      final result = await service.checkForUpdate();

      expect(result.status, AppUpdateCheckStatus.upToDate);
      expect(result.updateInfo, isNull);
      expect(launched, isEmpty);
    },
  );

  test(
    'GitHub fallback remains available when the release omits its URL',
    () async {
      response.release.remove('html_url');
      final service = AppUpdateService.forTesting(
        client: client,
        operatingSystem: 'linux',
      );

      final result = await service.checkForUpdate();

      expect(result.status, AppUpdateCheckStatus.available);
      await service.openUpdate(result.updateInfo!);
      expect(launched, [
        'https://github.com/YuanDevTeam/OneXray/releases/latest',
      ]);
    },
  );

  test(
    'a rejected Microsoft Store launch reports an opening failure',
    () async {
      launchSucceeded = false;
      final service = AppUpdateService.forTesting(
        client: client,
        operatingSystem: 'windows',
      );
      final result = await service.checkForUpdate();
      expect(result.status, AppUpdateCheckStatus.available);

      await expectLater(
        service.openUpdate(result.updateInfo!),
        throwsA(isA<StateError>()),
      );

      expect(launched, [microsoftStoreUrl]);
    },
  );
}

class _ReleaseResponse implements HttpClientAdapter {
  final Map<String, dynamic> release;
  final requests = <RequestOptions>[];

  _ReleaseResponse(this.release);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(release),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
