enum SwipeDirection {
  woof('woof'),
  pass('pass');

  final String storageKey;
  const SwipeDirection(this.storageKey);

  static SwipeDirection fromStorage(String key) =>
      SwipeDirection.values.firstWhere((d) => d.storageKey == key, orElse: () => SwipeDirection.pass);
}

class Swipe {
  final String fromUid, petId, ownerId;
  final SwipeDirection direction;
  const Swipe({
    required this.fromUid, required this.petId, required this.ownerId, required this.direction,
  });

  String get id => '${fromUid}_$petId';

  Map<String, dynamic> toMap() => {
        'fromUid': fromUid,
        'petId': petId,
        'ownerId': ownerId,
        'direction': direction.storageKey,
      };
}
