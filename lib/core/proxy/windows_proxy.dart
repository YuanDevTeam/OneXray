import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:onexray/core/proxy/system_proxy.dart';

/// WinINet's default/LAN per-connection settings. No registry setting writes.
final class WindowsSystemProxyAdapter implements SystemProxyAdapter {
  @override
  String get id => 'windows-wininet-user';

  @override
  Future<DesktopSystemProxyCapability> capability() => Isolate.run(() {
    try {
      _WinInet().checkPolicy();
      _WinInet().read();
      return const DesktopSystemProxyCapability(supported: true);
    } catch (error) {
      return DesktopSystemProxyCapability(supported: false, reason: '$error');
    }
  });

  @override
  Future<SystemProxySnapshot> read() => Isolate.run(() => _WinInet().read());

  @override
  SystemProxySnapshot forEndpoint(SystemProxySnapshot before, int port) => {
    ...before,
    'flags': 3, // DIRECT | PROXY; saved PAC/discovery flags are restored later.
    'server': 'http=127.0.0.1:$port;https=127.0.0.1:$port',
  };

  @override
  Future<void> write(SystemProxySnapshot snapshot) => Isolate.run(() {
    final native = _WinInet();
    native.checkPolicy();
    native.write(snapshot);
  });

  @override
  bool referencesEndpoint(SystemProxySnapshot snapshot, int port) {
    if (((snapshot['flags'] as int) & 2) == 0) return false;
    final server = snapshot['server'] as String;
    return server.split(';').any((entry) {
      final endpoint = entry.trim().split('=').last.trim().toLowerCase();
      return endpoint == '127.0.0.1:$port' || endpoint == 'localhost:$port';
    });
  }

  @override
  bool restorationMatches(
    SystemProxySnapshot actual,
    SystemProxySnapshot before,
  ) => proxyValuesEqual(actual, before);
}

final class _PerConnectionValue extends Union {
  @Uint32()
  external int number;
  external Pointer<Utf16> text;
  @Uint64()
  external int fileTime;
}

final class _PerConnectionOption extends Struct {
  @Uint32()
  external int option;
  external _PerConnectionValue value;
}

final class _PerConnectionList extends Struct {
  @Uint32()
  external int size;
  external Pointer<Utf16> connection;
  @Uint32()
  external int count;
  @Uint32()
  external int optionError;
  external Pointer<_PerConnectionOption> options;
}

final class _WinInet {
  final _internet = DynamicLibrary.open('wininet.dll');
  final _kernel = DynamicLibrary.open('kernel32.dll');
  final _registry = DynamicLibrary.open('advapi32.dll');

  late final _query = _internet
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Pointer<Uint32>),
        int Function(Pointer<Void>, int, Pointer<Void>, Pointer<Uint32>)
      >('InternetQueryOptionW');
  late final _set = _internet
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Uint32),
        int Function(Pointer<Void>, int, Pointer<Void>, int)
      >('InternetSetOptionW');
  late final _free = _kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('GlobalFree');
  late final _lastError = _kernel
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
  late final _getRegistry = _registry
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
          Pointer<Uint32>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          int,
          Pointer<Uint32>,
          Pointer<Void>,
          Pointer<Uint32>,
        )
      >('RegGetValueW');

  Never _failed(String operation, [int? error]) =>
      throw StateError('$operation failed (${error ?? _lastError()}).');

  int? _policy(int hive, String path, String key) => using((arena) {
    final data = arena<Uint32>();
    final length = arena<Uint32>()..value = sizeOf<Uint32>();
    final result = _getRegistry(
      Pointer<Void>.fromAddress(hive),
      path.toNativeUtf16(allocator: arena),
      key.toNativeUtf16(allocator: arena),
      0x10,
      nullptr,
      data.cast(),
      length,
    );
    if (result == 2 || result == 3) return null; // no configured policy
    if (result != 0) _failed('Read system proxy policy', result);
    return data.value;
  });

  void checkPolicy() {
    const machine = 0xffffffff80000002;
    const user = 0xffffffff80000001;
    const internet =
        r'Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings';
    const panel =
        r'Software\Policies\Microsoft\Internet Explorer\Control Panel';
    if (_policy(machine, internet, 'ProxySettingsPerUser') == 0 ||
        _policy(user, panel, 'Proxy') == 1 ||
        _policy(machine, panel, 'Proxy') == 1) {
      throw StateError(
        'System proxy settings are managed by your organization.',
      );
    }
  }

  SystemProxySnapshot read() {
    // FLAGS_UI is the documented read preference on Windows 7 and later.
    try {
      return _read(10);
    } on StateError {
      return _read(1);
    }
  }

  SystemProxySnapshot _read(int flagsOption) {
    final options = calloc<_PerConnectionOption>(4);
    final list = calloc<_PerConnectionList>();
    final length = calloc<Uint32>()..value = sizeOf<_PerConnectionList>();
    try {
      for (var index = 0; index < 4; index++) {
        options[index].option = index == 0 ? flagsOption : index + 1;
      }
      list.ref
        ..size = sizeOf<_PerConnectionList>()
        ..connection = nullptr
        ..count = 4
        ..options = options;
      if (_query(nullptr, 75, list.cast(), length) == 0) {
        _failed('Read system proxy');
      }
      if (list.ref.optionError != 0) {
        _failed('Read system proxy option', list.ref.optionError);
      }
      String readString(int index) => options[index].value.text == nullptr
          ? ''
          : options[index].value.text.toDartString();
      return {
        'flags': options[0].value.number,
        'server': readString(1),
        'bypass': readString(2),
        'autoConfigUrl': readString(3),
      };
    } finally {
      for (var index = 1; index < 4; index++) {
        final value = options[index].value.text;
        if (value != nullptr) _free(value.cast());
      }
      calloc.free(length);
      calloc.free(list);
      calloc.free(options);
    }
  }

  void write(SystemProxySnapshot snapshot) => using((arena) {
    final options = arena<_PerConnectionOption>(4);
    for (var index = 0; index < 4; index++) {
      options[index].option = index + 1;
    }
    options[0].value.number = snapshot['flags'] as int;
    options[1].value.text = (snapshot['server'] as String).toNativeUtf16(
      allocator: arena,
    );
    options[2].value.text = (snapshot['bypass'] as String).toNativeUtf16(
      allocator: arena,
    );
    options[3].value.text = (snapshot['autoConfigUrl'] as String).toNativeUtf16(
      allocator: arena,
    );
    final list = arena<_PerConnectionList>();
    list.ref
      ..size = sizeOf<_PerConnectionList>()
      ..connection = nullptr
      ..count = 4
      ..options = options;
    if (_set(nullptr, 75, list.cast(), sizeOf<_PerConnectionList>()) == 0) {
      _failed('Set system proxy');
    }
    if (list.ref.optionError != 0) {
      _failed('Set system proxy option', list.ref.optionError);
    }
    for (final notification in [39, 37]) {
      if (_set(nullptr, notification, nullptr, 0) == 0) {
        _failed('Refresh system proxy');
      }
    }
  });
}
