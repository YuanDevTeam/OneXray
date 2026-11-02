import 'package:flutter/services.dart';

/// The runner owns the outer Flutter window, including before its first show.
abstract final class DesktopWindowHandle {
  static const _channel = MethodChannel('onexray/desktop_window');

  static Future<int> read() async {
    final handle = await _channel.invokeMethod<int>('getMainWindowHandle');
    if (handle == null || handle <= 0) {
      throw StateError('The desktop runner did not provide a main window.');
    }
    return handle;
  }
}
