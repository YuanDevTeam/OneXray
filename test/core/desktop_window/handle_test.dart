import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/desktop_window/handle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('onexray/desktop_window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('requests the runner main window handle unchanged', () async {
    MethodCall? requested;
    const handle = 0x123456789;
    messenger.setMockMethodCallHandler(channel, (call) async {
      requested = call;
      return handle;
    });

    expect(await DesktopWindowHandle.read(), handle);
    expect(requested?.method, 'getMainWindowHandle');
    expect(requested?.arguments, isNull);
  });

  for (final handle in <int?>[null, 0, -1]) {
    test('rejects an unavailable runner handle ($handle)', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => handle);

      await expectLater(DesktopWindowHandle.read(), throwsStateError);
    });
  }

  test('propagates a native runner error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'window_unavailable', message: 'No window');
    });

    await expectLater(
      DesktopWindowHandle.read(),
      throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'window_unavailable')
            .having((error) => error.message, 'message', 'No window'),
      ),
    );
  });
}
