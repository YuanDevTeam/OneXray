import 'package:onexray/core/backup/model.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/settings.dart';

/// Portable VPN preferences stay inside their source operating system's key.
/// Physical interface names and unrelated platform drafts stay on the device.
final class BackupPlatformSettings {
  const BackupPlatformSettings(this.platform);

  final ConnectionPlatform platform;

  Map<String, dynamic> capture(PlatformPolicy policy) => {
    platform.name: _project(policy.toJson(), _schema),
  };

  void validate(BackupDocument document) {
    final selected = _read(document);
    if (selected != null) PlatformPolicy.fromJson(selected);
  }

  PlatformPolicy restore(BackupDocument document, PlatformPolicy original) {
    final selected = _read(document);
    if (selected == null) return original;
    return PlatformPolicy.fromJson(_merge(original.toJson(), selected));
  }

  Map<String, dynamic> get _schema {
    final schema = PlatformPolicy.defaults().toJson()
      ..remove('xrayOutboundInterfaceName');
    final section = switch (platform) {
      ConnectionPlatform.android => 'android',
      ConnectionPlatform.ios || ConnectionPlatform.macos => 'apple',
      ConnectionPlatform.windows => 'windows',
      ConnectionPlatform.linux => null,
    };
    for (final name in ['android', 'apple', 'windows']) {
      if (name != section) schema.remove(name);
    }
    return schema;
  }

  Map<String, dynamic>? _read(BackupDocument document) {
    final sections = document.platformSettings;
    if (sections == null || !sections.containsKey(platform.name)) return null;
    final selected = sections[platform.name];
    if (selected is! Map) {
      throw const FormatException('Invalid backup platform settings');
    }
    // Unknown fields remain forward compatible. Known values keep their type
    // so the existing PlatformPolicy parser owns validation and normalization.
    return _project(selected, _schema);
  }

  static Map<String, dynamic> _project(
    Map value,
    Map<String, dynamic> schema,
  ) => {
    for (final key in schema.keys)
      if (value.containsKey(key))
        key: schema[key] is Map<String, dynamic> && value[key] is Map
            ? _project(value[key] as Map, schema[key] as Map<String, dynamic>)
            : value[key],
  };

  static Map<String, dynamic> _merge(
    Map<String, dynamic> original,
    Map<String, dynamic> patch,
  ) => {
    ...original,
    for (final entry in patch.entries)
      entry.key:
          original[entry.key] is Map<String, dynamic> &&
              entry.value is Map<String, dynamic>
          ? _merge(
              original[entry.key] as Map<String, dynamic>,
              entry.value as Map<String, dynamic>,
            )
          : entry.value,
  };
}
