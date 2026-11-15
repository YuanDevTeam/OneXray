import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:onexray/core/proxy/system_proxy.dart';

/// GSettings user and effective values are both kept. Restoring a missing user
/// value uses reset(), so a default/administrator value is not made permanent.
final class GnomeSystemProxyAdapter implements SystemProxyAdapter {
  @override
  String get id => 'gnome-gsettings-user';

  @override
  Future<DesktopSystemProxyCapability> capability() => Isolate.run(() {
    try {
      final native = _GSettings();
      native.checkSession();
      final settings = native.open();
      try {
        settings.checkWritable();
        settings.read();
      } finally {
        settings.close();
      }
      return const DesktopSystemProxyCapability(supported: true);
    } catch (error) {
      return DesktopSystemProxyCapability(supported: false, reason: '$error');
    }
  });

  @override
  Future<SystemProxySnapshot> read() => Isolate.run(() {
    final native = _GSettings();
    native.checkSession();
    final settings = native.open();
    try {
      return settings.read();
    } finally {
      settings.close();
    }
  });

  @override
  SystemProxySnapshot forEndpoint(SystemProxySnapshot before, int port) {
    final native = _GSettings();
    final values = <String, Object>{
      'mode': 'manual',
      'use-same-proxy': false,
      'http.host': '127.0.0.1',
      'http.port': port,
      'http.use-authentication': false,
      'https.host': '127.0.0.1',
      'https.port': port,
      'ftp.host': '',
      'ftp.port': 0,
      'socks.host': '127.0.0.1',
      'socks.port': port,
    };
    return {
      for (final entry in values.entries)
        entry.key: {
          'effective': native.encode(entry.value),
          'user': native.encode(entry.value),
        },
    };
  }

  @override
  Future<void> write(SystemProxySnapshot snapshot) => Isolate.run(() {
    final native = _GSettings();
    native.checkSession();
    // delay() precedes get_child(): the children share the root's delayed group.
    final settings = native.open(delayed: true);
    try {
      settings.checkWritable();
      settings.write(snapshot);
    } finally {
      settings.close();
    }
  });

  @override
  bool referencesEndpoint(SystemProxySnapshot snapshot, int port) {
    Object? effective(String key) => (snapshot[key] as Map?)?['effective'];
    if (effective('mode') != "'manual'") return false;
    return ['http', 'https', 'socks'].any(
      (scheme) =>
          {
            "'127.0.0.1'",
            "'localhost'",
          }.contains('${effective('$scheme.host')}'.toLowerCase()) &&
          effective('$scheme.port') == '$port',
    );
  }

  @override
  bool restorationMatches(
    SystemProxySnapshot actual,
    SystemProxySnapshot before,
  ) =>
      actual.length == before.length &&
      before.keys.every((key) {
        final expected = before[key];
        final current = actual[key];
        return expected is Map &&
            current is Map &&
            expected.containsKey('user') &&
            current.containsKey('user') &&
            proxyValuesEqual(current['user'], expected['user']);
      });
}

const _proxyKeys = <String, List<String>>{
  '': ['mode', 'use-same-proxy'],
  'http': ['host', 'port', 'use-authentication'],
  'https': ['host', 'port'],
  'ftp': ['host', 'port'],
  'socks': ['host', 'port'],
};

final class _Settings {
  _Settings(this.native, this.objects);

  final _GSettings native;
  final Map<String, Pointer<Void>> objects;

  void checkWritable() {
    for (final entry in _proxyKeys.entries) {
      for (final key in entry.value) {
        using((arena) {
          if (native.isWritable(
                objects[entry.key]!,
                key.toNativeUtf8(allocator: arena),
              ) ==
              0) {
            throw StateError(
              'System proxy settings are managed by your organization.',
            );
          }
        });
      }
    }
  }

  SystemProxySnapshot read() {
    native.drainNotifications();
    return {
      for (final entry in _proxyKeys.entries)
        for (final key in entry.value)
          entry.key.isEmpty ? key : '${entry.key}.$key': using((arena) {
            final name = key.toNativeUtf8(allocator: arena);
            final effective = native.getValue(objects[entry.key]!, name);
            final user = native.getUserValue(objects[entry.key]!, name);
            if (effective == nullptr) {
              throw StateError('Unable to read system proxy settings.');
            }
            return {
              'effective': native.printOwned(effective),
              'user': user == nullptr ? null : native.printOwned(user),
            };
          }),
    };
  }

  void write(SystemProxySnapshot snapshot) {
    final keys = [
      for (final entry in _proxyKeys.entries)
        for (final key in entry.value)
          (
            object: entry.key,
            key: key,
            full: entry.key.isEmpty ? key : '${entry.key}.$key',
          ),
    ];
    if (snapshot.length != keys.length ||
        keys.any((key) => !snapshot.containsKey(key.full))) {
      throw const FormatException('Invalid GNOME proxy recovery values');
    }
    // mode is the final staged field; apply and sync are followed by host readback.
    keys.sort(
      (a, b) => a.full == 'mode'
          ? 1
          : b.full == 'mode'
          ? -1
          : a.full.compareTo(b.full),
    );
    try {
      for (final key in keys) {
        final record = snapshot[key.full];
        if (record is! Map || !record.containsKey('user')) {
          throw const FormatException('Invalid GNOME proxy recovery value');
        }
        using((arena) {
          final name = key.key.toNativeUtf8(allocator: arena);
          final saved = record['user'];
          if (saved == null) {
            native.reset(objects[key.object]!, name);
          } else {
            if (saved is! String) {
              throw const FormatException('Invalid GNOME user value');
            }
            final variant = native.parse(saved);
            try {
              if (native.setValue(objects[key.object]!, name, variant) == 0) {
                throw StateError('Unable to write system proxy settings.');
              }
            } finally {
              native.variantUnref(variant);
            }
          }
        });
      }
      native.apply(objects['']!);
      native.sync();
    } catch (_) {
      native.revert(objects['']!);
      rethrow;
    }
  }

  void close() {
    for (final object in objects.values.toList().reversed) {
      native.unref(object);
    }
  }
}

final class _GSettings {
  final _gio = DynamicLibrary.open('libgio-2.0.so.0');
  final _glib = DynamicLibrary.open('libglib-2.0.so.0');
  final _objects = DynamicLibrary.open('libgobject-2.0.so.0');

  late final sourceDefault = _gio
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'g_settings_schema_source_get_default',
      );
  late final lookup = _gio
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Int32),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int)
      >('g_settings_schema_source_lookup');
  late final schemaHasKey = _gio
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)
      >('g_settings_schema_has_key');
  late final schemaUnref = _gio
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_settings_schema_unref');
  late final create = _gio
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Utf8>)
      >('g_settings_new_full');
  late final child = _gio
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
      >('g_settings_get_child');
  late final getValue = _gio
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
      >('g_settings_get_value');
  late final getUserValue = _gio
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
      >('g_settings_get_user_value');
  late final isWritable = _gio
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)
      >('g_settings_is_writable');
  late final setValue = _gio
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>),
        int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>)
      >('g_settings_set_value');
  late final reset = _gio
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Utf8>),
        void Function(Pointer<Void>, Pointer<Utf8>)
      >('g_settings_reset');
  late final delay = _gio
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_settings_delay');
  late final apply = _gio
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_settings_apply');
  late final revert = _gio
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_settings_revert');
  late final sync = _gio.lookupFunction<Void Function(), void Function()>(
    'g_settings_sync',
  );
  late final backend = _gio
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'g_settings_backend_get_default',
      );
  late final sessionBus = _gio
      .lookupFunction<
        Pointer<Void> Function(Int32, Pointer<Void>, Pointer<Pointer<Void>>),
        Pointer<Void> Function(int, Pointer<Void>, Pointer<Pointer<Void>>)
      >('g_bus_get_sync');
  late final typeName = _objects
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)
      >('g_type_name_from_instance');
  late final unref = _objects
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_object_unref');
  late final variantUnref = _glib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_variant_unref');
  late final variantSink = _glib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('g_variant_ref_sink');
  late final variantPrint = _glib
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Int32),
        Pointer<Utf8> Function(Pointer<Void>, int)
      >('g_variant_print');
  late final variantParse = _glib
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Pointer<Utf8>>,
          Pointer<Pointer<Void>>,
        ),
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Pointer<Utf8>>,
          Pointer<Pointer<Void>>,
        )
      >('g_variant_parse');
  late final variantString = _glib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Utf8>)
      >('g_variant_new_string');
  late final variantInt = _glib
      .lookupFunction<
        Pointer<Void> Function(Int32),
        Pointer<Void> Function(int)
      >('g_variant_new_int32');
  late final variantBool = _glib
      .lookupFunction<
        Pointer<Void> Function(Int32),
        Pointer<Void> Function(int)
      >('g_variant_new_boolean');
  late final free = _glib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_free');
  late final errorFree = _glib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_error_free');
  late final iterate = _glib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('g_main_context_iteration');

  void checkSession() {
    final desktops = (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '')
        .toLowerCase()
        .split(':');
    final selectedBackend = Platform.environment['GSETTINGS_BACKEND'];
    if (!desktops.contains('gnome') ||
        desktops.contains('kde') ||
        (Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isEmpty ||
        (selectedBackend != null && selectedBackend != 'dconf')) {
      throw StateError('Automatic system proxy requires a GNOME user session.');
    }
    final uid = DynamicLibrary.open('libc.so.6')
        .lookupFunction<Uint32 Function(), int Function()>('geteuid')();
    if (uid == 0) {
      throw StateError(
        'Automatic system proxy requires the logged-in desktop user.',
      );
    }
    using((arena) {
      final error = arena<Pointer<Void>>();
      final bus = sessionBus(2, nullptr, error); // G_BUS_TYPE_SESSION
      if (error.value != nullptr) errorFree(error.value);
      if (bus == nullptr) {
        throw StateError('The GNOME user session bus is unavailable.');
      }
      unref(bus);
    });
    final object = backend();
    if (object == nullptr) {
      throw StateError('The desktop settings backend is unavailable.');
    }
    try {
      // The memory/keyfile fallbacks can report writable without affecting GNOME.
      if (typeName(object).toDartString() != 'DConfSettingsBackend') {
        throw StateError('The GNOME desktop dconf backend is unavailable.');
      }
    } finally {
      unref(object);
    }
  }

  _Settings open({bool delayed = false}) {
    final source = sourceDefault();
    if (source == nullptr) {
      throw StateError('GNOME proxy schemas are unavailable.');
    }
    final values = <String, Pointer<Void>>{};
    try {
      for (final entry in _proxyKeys.entries) {
        using((arena) {
          final id =
              'org.gnome.system.proxy${entry.key.isEmpty ? '' : '.${entry.key}'}';
          final schema = lookup(source, id.toNativeUtf8(allocator: arena), 1);
          if (schema == nullptr) {
            throw StateError('GNOME proxy schema is unavailable: $id');
          }
          try {
            for (final key in entry.value) {
              if (schemaHasKey(schema, key.toNativeUtf8(allocator: arena)) ==
                  0) {
                throw StateError('GNOME proxy setting is unavailable: $key');
              }
            }
            if (entry.key.isEmpty) {
              values[''] = create(schema, nullptr, nullptr);
              if (values[''] == nullptr) {
                throw StateError('Unable to open GNOME proxy settings.');
              }
              if (delayed) delay(values['']!);
            } else {
              values[entry.key] = child(
                values['']!,
                entry.key.toNativeUtf8(allocator: arena),
              );
              if (values[entry.key] == nullptr) {
                throw StateError('Unable to open GNOME proxy child settings.');
              }
            }
          } finally {
            schemaUnref(schema);
          }
        });
      }
      return _Settings(this, values);
    } catch (_) {
      for (final value in values.values) {
        if (value != nullptr) unref(value);
      }
      rethrow;
    }
  }

  String printOwned(Pointer<Void> variant) {
    final text = variantPrint(variant, 1);
    try {
      return text.toDartString();
    } finally {
      free(text.cast());
      variantUnref(variant);
    }
  }

  String encode(Object value) => using((arena) {
    final variant = switch (value) {
      String() => variantString(value.toNativeUtf8(allocator: arena)),
      int() => variantInt(value),
      bool() => variantBool(value ? 1 : 0),
      _ => throw const FormatException('Unsupported GNOME proxy value'),
    };
    return printOwned(variantSink(variant));
  });

  Pointer<Void> parse(String source) => using((arena) {
    final error = arena<Pointer<Void>>();
    final variant = variantParse(
      nullptr,
      source.toNativeUtf8(allocator: arena),
      nullptr,
      nullptr,
      error,
    );
    if (error.value != nullptr) errorFree(error.value);
    if (variant == nullptr) {
      throw const FormatException('Invalid GNOME proxy value');
    }
    return variantSink(variant);
  });

  void drainNotifications() {
    for (var count = 0; count < 100 && iterate(nullptr, 0) != 0; count++) {}
  }
}
