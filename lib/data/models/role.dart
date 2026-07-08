enum Role {
  petParent('Pet Parent', 'petParent'),
  servicePro('Service Professional', 'servicePro'),
  homestayHost('Homestay Host', 'homestayHost');

  final String label;
  final String storageKey;
  const Role(this.label, this.storageKey);

  static Role fromStorage(String key) =>
      Role.values.firstWhere((r) => r.storageKey == key, orElse: () => Role.petParent);
}
