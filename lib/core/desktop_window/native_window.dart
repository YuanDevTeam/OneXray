import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:nativeapi/nativeapi.dart' show Window, WindowManager;
import 'package:win32/win32.dart' as win32;

/// Resolves this app's main window without showing or activating it.
Window? resolveDesktopWindow() {
  if (Platform.isWindows) return _windowsMainWindow();
  if (Platform.isMacOS || Platform.isLinux) {
    return WindowManager.instance.getCurrent();
  }
  return null;
}

Window? _windowsMainWindow() => using((arena) {
  // Nativeapi's Windows getCurrent uses thread-local GetActiveWindow, which
  // cannot resolve a hidden Flutter runner from the Dart isolate's thread.
  final currentProcess = win32.GetCurrentProcessId();
  final processId = arena<Uint32>();
  const classNameCapacity = 256;
  final className = win32.PWSTR(arena<Uint16>(classNameCapacity).cast());
  Pointer<Void> found = nullptr;
  final callback = NativeCallable<win32.WNDENUMPROC>.isolateLocal((
    Pointer windowPointer,
    int _,
  ) {
    final handle = win32.HWND(windowPointer);
    final threadId = win32.GetWindowThreadProcessId(handle, processId);
    if (threadId == 0 || processId.value != currentProcess) return win32.TRUE;
    final length = win32.GetClassName(
      handle,
      className,
      classNameCapacity,
    ).value;
    if (length == 0 ||
        className.toDartString(length: length) !=
            'FLUTTER_RUNNER_WIN32_WINDOW') {
      return win32.TRUE;
    }
    found = windowPointer.cast<Void>();
    return win32.FALSE;
  }, exceptionalReturn: win32.FALSE);
  try {
    // EnumWindows includes hidden top-level windows. A false result is normal
    // when the callback stops after finding the process-owned Flutter window.
    win32.EnumWindows(callback.nativeFunction, const win32.LPARAM(0));
  } finally {
    callback.close();
  }
  return found == nullptr ? null : Window.createWithNativeWindow(found);
});
