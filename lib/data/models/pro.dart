import 'availability.dart';

enum ServiceType {
  walker('walker', 'Dog Walker', '🦮', 'walk', 'walk'),
  sitter('sitter', 'Pet Sitter', '🏠', 'visit', 'look after'),
  groomer('groomer', 'Groomer', '✂️', 'session', 'groom'),
  trainer('trainer', 'Trainer', '🎾', 'session', 'train');

  /// [verb] is what the pro does to the pet: "Aarav will **walk** Bruno".
  final String storageKey, label, emoji, unit, verb;
  const ServiceType(this.storageKey, this.label, this.emoji, this.unit, this.verb);

  static ServiceType fromStorage(String key) =>
      ServiceType.values.firstWhere((s) => s.storageKey == key, orElse: () => ServiceType.walker);
}

class Pro {
  final String uid, name, area, bio;
  final ServiceType serviceType;
  final int rate, experienceYears, reviewCount;
  final double rating;
  final bool verified;

  /// Weekly bookable hours + slot length. Listings saved before time slots
  /// existed have none and get [Availability.defaults].
  final Availability availability;

  const Pro({
    required this.uid, required this.name, required this.area, required this.bio,
    required this.serviceType, required this.rate, required this.experienceYears,
    this.verified = false, this.rating = 0, this.reviewCount = 0,
    this.availability = Availability.defaults,
  });

  String get unit => serviceType.unit;

  /// The pro's own editable listing fields — deliberately **excludes**
  /// `verified`, `rating` and `reviewCount`. Those are server-owned: the rating
  /// pair is recomputed by the `onReviewCreated` Function and `verified` is
  /// granted out-of-band by staff, so a pro cannot award themselves a trust
  /// badge or inflate their own score. `firestore.rules` rejects any client
  /// write that touches them, and the repository writes with `merge: true`, so
  /// leaving them out here preserves whatever the server already stored.
  Map<String, dynamic> toMap() => {
        'ownerId': uid,
        'name': name,
        'area': area,
        'bio': bio,
        'serviceType': serviceType.storageKey,
        'rate': rate,
        'experienceYears': experienceYears,
        'availability': availability.toMap(),
      };

  factory Pro.fromMap(String uid, Map<String, dynamic> m) => Pro(
        uid: uid,
        name: (m['name'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        bio: (m['bio'] ?? '') as String,
        serviceType: ServiceType.fromStorage((m['serviceType'] ?? 'walker') as String),
        rate: (m['rate'] ?? 0) as int,
        experienceYears: (m['experienceYears'] ?? 0) as int,
        verified: (m['verified'] ?? false) as bool,
        rating: ((m['rating'] ?? 0) as num).toDouble(),
        reviewCount: (m['reviewCount'] ?? 0) as int,
        availability: Availability.fromMap(m['availability']),
      );
}
