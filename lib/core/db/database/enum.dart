import 'package:collection/collection.dart';

enum CoreConfigType {
  outbound("outbound"),
  raw("raw"),
  // ignore: constant_identifier_names
  Remnawave("Remnawave");

  const CoreConfigType(this.name);

  final String name;

  @override
  String toString() => name;

  static CoreConfigType? fromString(String name) =>
      CoreConfigType.values.firstWhereOrNull((value) => value.name == name);
}

enum SubscriptionPanel {
  generic,
  remnawave;

  static SubscriptionPanel? fromString(String value) =>
      values.firstWhereOrNull((panel) => panel.name == value);
}

enum SubscriptionMode {
  appManaged,
  providerManaged;

  static SubscriptionMode? fromString(String value) =>
      values.firstWhereOrNull((mode) => mode.name == value);
}
