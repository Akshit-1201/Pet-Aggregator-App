enum ReviewTargetType {
  pro('pro'),
  homestay('homestay');

  final String storageKey;
  const ReviewTargetType(this.storageKey);

  static ReviewTargetType fromStorage(String key) =>
      ReviewTargetType.values.firstWhere((t) => t.storageKey == key, orElse: () => ReviewTargetType.pro);
}

class Review {
  final String id, targetId, targetName, authorId, authorName, bookingId, text;
  final ReviewTargetType targetType;
  final int stars, createdAt;

  const Review({
    this.id = '',
    required this.targetType,
    required this.targetId,
    required this.targetName,
    required this.authorId,
    required this.authorName,
    required this.bookingId,
    required this.stars,
    this.text = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'targetType': targetType.storageKey,
        'targetId': targetId,
        'targetName': targetName,
        'authorId': authorId,
        'authorName': authorName,
        'bookingId': bookingId,
        'stars': stars,
        'text': text,
        'createdAt': createdAt,
      };

  factory Review.fromMap(String id, Map<String, dynamic> m) => Review(
        id: id,
        targetType: ReviewTargetType.fromStorage((m['targetType'] ?? 'pro') as String),
        targetId: (m['targetId'] ?? '') as String,
        targetName: (m['targetName'] ?? '') as String,
        authorId: (m['authorId'] ?? '') as String,
        authorName: (m['authorName'] ?? '') as String,
        bookingId: (m['bookingId'] ?? '') as String,
        stars: (m['stars'] ?? 0) as int,
        text: (m['text'] ?? '') as String,
        createdAt: (m['createdAt'] ?? 0) as int,
      );
}

/// Lightweight payload passed to the Rate screen via `extra` (built from a
/// Booking or HomestayBooking row). Not persisted.
class ReviewTarget {
  final ReviewTargetType type;
  final String id, name, subtitle, bookingId;
  const ReviewTarget({
    required this.type, required this.id, required this.name,
    required this.subtitle, required this.bookingId,
  });
}
