enum HomeType {
  apartment('apartment', 'Apartment', '🏡'),
  house('house', 'House', '🏠'),
  villa('villa', 'Villa', '🏘️');

  final String storageKey, label, emoji;
  const HomeType(this.storageKey, this.label, this.emoji);

  static HomeType fromStorage(String key) =>
      HomeType.values.firstWhere((t) => t.storageKey == key, orElse: () => HomeType.apartment);
}

enum Amenity {
  nearPark('nearPark', 'Near park', '🌳'),
  fencedBalcony('fencedBalcony', 'Fenced balcony', '🪴'),
  residentDog('residentDog', 'Resident dog', '🐕'),
  wfhHost('wfhHost', 'WFH host', '💻'),
  airConditioned('airConditioned', 'Air-conditioned', '❄️'),
  dailyWalks('dailyWalks', 'Daily walks', '🦮');

  final String storageKey, label, emoji;
  const Amenity(this.storageKey, this.label, this.emoji);

  static Amenity fromStorage(String key) =>
      Amenity.values.firstWhere((a) => a.storageKey == key, orElse: () => Amenity.nearPark);

  /// Maps stored keys to amenities, silently dropping any unknown keys.
  static List<Amenity> fromStorageList(List<dynamic> keys) {
    final byKey = {for (final a in Amenity.values) a.storageKey: a};
    return keys.map((k) => byKey[k as String]).whereType<Amenity>().toList();
  }
}

class Homestay {
  /// A listing must show the place: at least [minPhotos], at most [maxPhotos].
  static const int minPhotos = 3;
  static const int maxPhotos = 5;

  final String uid, homeName, hostName, area, about;
  final HomeType homeType;
  final int ratePerNight, reviewCount;
  final List<Amenity> amenities;
  final List<String> photoUrls;
  final bool verified;
  final double rating;

  const Homestay({
    required this.uid, required this.homeName, required this.hostName,
    required this.area, required this.about, required this.homeType,
    required this.ratePerNight, this.amenities = const [], this.photoUrls = const [],
    this.verified = false, this.rating = 0, this.reviewCount = 0,
  });

  /// The image used wherever a single thumbnail represents the home.
  String get coverPhoto => photoUrls.isEmpty ? '' : photoUrls.first;

  Map<String, dynamic> toMap() => {
        'ownerId': uid,
        'homeName': homeName,
        'hostName': hostName,
        'area': area,
        'about': about,
        'homeType': homeType.storageKey,
        'ratePerNight': ratePerNight,
        'amenities': amenities.map((a) => a.storageKey).toList(),
        'photoUrls': photoUrls,
        'verified': verified,
        'rating': rating,
        'reviewCount': reviewCount,
      };

  factory Homestay.fromMap(String uid, Map<String, dynamic> m) => Homestay(
        uid: uid,
        homeName: (m['homeName'] ?? '') as String,
        hostName: (m['hostName'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        about: (m['about'] ?? '') as String,
        homeType: HomeType.fromStorage((m['homeType'] ?? 'apartment') as String),
        ratePerNight: (m['ratePerNight'] ?? 0) as int,
        amenities: Amenity.fromStorageList((m['amenities'] ?? const []) as List),
        photoUrls: ((m['photoUrls'] ?? const []) as List).whereType<String>().toList(),
        verified: (m['verified'] ?? false) as bool,
        rating: ((m['rating'] ?? 0) as num).toDouble(),
        reviewCount: (m['reviewCount'] ?? 0) as int,
      );
}
