import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/pigeon/model_reader.dart';
import 'package:onexray/core/pigeon/model_writer.dart';

import '../../support/test_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('native startup input storage', () {
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.onexray.BridgeHostApi.getTunFilesDir',
      BridgeHostApi.pigeonChannelCodec,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory directory;

    setUp(() async {
      directory = await createTestDirectory('start-request-storage-');
      messenger.setMockDecodedMessageHandler(
        channel,
        (_) async => [directory.path],
      );
      await AppHostApi().initTunFilesDir();
    });
    tearDown(() async {
      messenger.setMockDecodedMessageHandler(channel, null);
      await directory.delete(recursive: true);
    });

    StartVpnRequest request(String mode) => StartVpnRequest(
      null,
      mode == 'proxy' ? '10808' : '18080',
      '18081',
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest('{"outbounds":[{"protocol":"freedom"}]}')
              .toJson(),
        ).toJson(),
      ),
      captureMode: mode,
      metadataJson: jsonEncode({'fixture': mode}),
    );

    for (final first in ['tun', 'proxy']) {
      test(
        'writing ${first == 'tun' ? 'proxy' : 'TUN'} preserves the other startup input byte-for-byte',
        () async {
          final firstRequest = request(first);
          await firstRequest.writeToStartFile();
          final firstFile = File(
            first == 'tun'
                ? VpnConstants.startPath
                : VpnConstants.proxyStartPath,
          );
          final original = await firstFile.readAsBytes();
          final secondRequest = request(first == 'tun' ? 'proxy' : 'tun');

          await secondRequest.writeToStartFile();

          expect(await firstFile.readAsBytes(), original);
          expect(
            await StartVpnRequestReader.readFromStartFile().then(
              (value) => value.captureMode,
            ),
            'tun',
          );
          expect(
            StartVpnRequest.fromJson(
              jsonDecode(
                await File(VpnConstants.proxyStartPath).readAsString(),
              ),
            ).captureMode,
            'proxy',
          );
          expect(
            directory
                .listSync(recursive: true)
                .whereType<File>()
                .map((file) => file.uri.pathSegments.last),
            unorderedEquals(['start.json', 'proxy-start.json']),
          );
        },
      );
    }

    test('a legacy TUN input survives proxy startup and remains independently readable', () async {
      final old = request('tun').toJson()
        ..remove('captureMode')
        ..remove('autoSetSystemProxy');
      final oldBytes = utf8.encode(
        '${const JsonEncoder.withIndent(' ').convert(old)}\n',
      );
      final tunFile = File(VpnConstants.startPath);
      await tunFile.parent.create(recursive: true);
      await tunFile.writeAsBytes(oldBytes);

      await request('proxy').writeToStartFile();

      final restored = await StartVpnRequestReader.readFromStartFile();
      expect(restored.captureMode, 'tun');
      expect(restored.coreInvokeText, old['coreInvokeText']);
      expect(await tunFile.readAsBytes(), oldBytes);
    });

    test('an old proxy request in the VPN file is rejected without rewriting either snapshot', () async {
      final misplaced = request('proxy').toJson();
      final file = File(VpnConstants.startPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(misplaced));
      await request('proxy').writeToStartFile();
      final original = await file.readAsBytes();
      final proxyBytes = await File(VpnConstants.proxyStartPath).readAsBytes();

      await expectLater(
        StartVpnRequestReader.readFromStartFile(),
        throwsFormatException,
      );

      expect(await file.readAsBytes(), original);
      expect(await File(VpnConstants.proxyStartPath).readAsBytes(), proxyBytes);
    });

    test('an unknown mode cannot overwrite either startup input', () async {
      await request('tun').writeToStartFile();
      await request('proxy').writeToStartFile();
      final tunBytes = await File(VpnConstants.startPath).readAsBytes();
      final proxyBytes = await File(VpnConstants.proxyStartPath).readAsBytes();

      await expectLater(
        request('unknown').writeToStartFile(),
        throwsFormatException,
      );

      expect(await File(VpnConstants.startPath).readAsBytes(), tunBytes);
      expect(await File(VpnConstants.proxyStartPath).readAsBytes(), proxyBytes);
    });
  }, skip: !Platform.isMacOS);
}
