enum ServiceType {
  walker('walker', 'Dog Walker', '🦮', 'walk'),
  sitter('sitter', 'Pet Sitter', '🏠', 'visit'),
  groomer('groomer', 'Groomer', '✂️', 'session'),
  trainer('trainer', 'Trainer', '🎾', 'session');

  final String storageKey, label, emoji, unit;
  const ServiceType(this.storageKey, this.label, this.emoji, this.unit);

  static ServiceType fromStorage(String key) =>
      ServiceType.values.firstWhere((s) => s.storageKey == key, orElse: () => ServiceType.walker);
}

class Pro {
  final String uid, name, area, bio;
  final ServiceType serviceType;
  final int rate, experienceYears, reviewCount;
  final double rating;

  const Pro({
    required this.uid, required this.name, required this.area, required this.bio,
    required this.serviceType, required this.rate, required this.experienceYears,
    this.rating = 0, this.reviewCount = 0,
  });

  String get unit => serviceType.unit;

  Map<String, dynamic> toMap() => {
        'ownerId': uid,
        'name': name,
        'area': area,
        'bio': bio,
        'serviceType': serviceType.storageKey,
        'rate': rate,
        'experienceYears': experienceYears,
        'rating': rating,
        'reviewCount': reviewCount,
      };

  factory Pro.fromMap(String uid, Map<String, dynamic> m) => Pro(
        uid: uid,
        name: (m['name'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        bio: (m['bio'] ?? '') as String,
        serviceType: ServiceType.fromStorage((m['serviceType'] ?? 'walker') as String),
        rate: (m['rate'] ?? 0) as int,
        experienceYears: (m['experienceYears'] ?? 0) as int,
        rating: ((m['rating'] ?? 0) as num).toDouble(),
        reviewCount: (m['reviewCount'] ?? 0) as int,
      );
}
