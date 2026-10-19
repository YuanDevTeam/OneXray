enum ServerSortOrder {
  defaultOrder('default'),
  name('name'),
  delay('delay');

  const ServerSortOrder(this.preferenceValue);

  final String preferenceValue;

  static ServerSortOrder fromString(String? value) => values.firstWhere(
    (order) => order.preferenceValue == value,
    orElse: () => defaultOrder,
  );
}
