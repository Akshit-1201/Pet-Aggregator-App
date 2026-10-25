import 'availability.dart';

enum ServiceType {
  walker('walker', 'Dog Walker', '🦮', 'walk', 'walk'),
  sitter('sitter', 'Pet Sitter', '🏠', 'visit', 'look after'),
  groomer('groomer', 'Groomer', '✂️', 'session', 'groom'),
  trainer('trainer', 'Trainer', '🎾', 'session', 'train'),
  behaviourist('behaviourist', 'Pet Behaviourist', '🧠', 'consult', 'assess');

  /// [verb] is what the pro does to the pet: "Aarav will **walk** Bruno".
  final String storageKey, label, emoji, unit, verb;
  const ServiceType(this.storageKey, this.label, this.emoji, this.unit, this.verb);

  static ServiceType fromStorage(String key) =>
      ServiceType.values.firstWhere((s) => s.storageKey == key, orElse: () => ServiceType.walker);
}

/// What a behaviourist works on. A fixed list rather than free text, so the
/// tags on a listing never need moderating.
enum Specialty {
  anxiety('anxiety', 'Anxiety'),
  aggression('aggression', 'Aggression'),
  reactivity('reactivity', 'Reactivity'),
  separation('separation', 'Separation'),
  puppies('puppies', 'Puppies'),
  cats('cats', 'Cats'),
  rescue('rescue', 'Rescue pets');

  final String storageKey, label;
  const Specialty(this.storageKey, this.label);

  /// Maps stored keys to specialties, silently dropping any unknown keys.
  static List<Specialty> fromStorageList(List<dynamic> keys) {
    final byKey = {for (final s in Specialty.values) s.storageKey: s};
    return keys.map((k) => byKey[k]).whereType<Specialty>().toList();
  }
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

  /// Only meaningful for [ServiceType.behaviourist] — see [shownSpecialties].
  final List<Specialty> specialties;

  const Pro({
    required this.uid, required this.name, required this.area, required this.bio,
    required this.serviceType, required this.rate, required this.experienceYears,
    this.verified = false, this.rating = 0, this.reviewCount = 0,
    this.availability = Availability.defaults, this.specialties = const [],
  });

  String get unit => serviceType.unit;

  /// Specialty tags to display and save. Empty for every other service type,
  /// so a pro who switches away from Behaviourist doesn't keep the tags.
  List<Specialty> get shownSpecialties =>
      serviceType == ServiceType.behaviourist ? specialties : const [];

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
        'specialties': shownSpecialties.map((s) => s.storageKey).toList(),
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
        specialties: Specialty.fromStorageList((m['specialties'] ?? const []) as List),
      );
}
