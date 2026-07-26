import 'package:flutter/material.dart';

enum Species {
  dog('dog'),
  cat('cat'),
  other('other');

  final String storageKey;
  const Species(this.storageKey);

  static Species fromStorage(String key) =>
      Species.values.firstWhere((s) => s.storageKey == key, orElse: () => Species.dog);
}

class PetProfile {
  /// A pet profile has to actually show the animal: at least [minPhotos], at
  /// most [maxPhotos]. Same shape as `Homestay`, so the setup screens behave
  /// identically.
  static const int minPhotos = 3;
  static const int maxPhotos = 5;

  final String id, ownerId, name, breed, ageLabel, sex, area;
  final Species species;
  final bool vaccinated;
  final Color accentColor;

  final List<String> photoUrls;

  /// The single image used wherever one thumbnail stands for the pet — rows,
  /// the swipe deck, map sheets. Derived so every existing call site kept
  /// working when pets went from one photo to a gallery.
  String get photoUrl => photoUrls.isEmpty ? '' : photoUrls.first;

  /// The owner's display name, captured when the pet is created.
  ///
  /// Denormalised because `users/{uid}` is readable **only by its owner** — the
  /// screens that show "whose pet is this" cannot read the profile doc, and were
  /// silently falling back to "Pet parent" everywhere. Same trade-off the app
  /// already makes for `chat.names`, `post.authorName` and `booking.proName`: a
  /// later rename does not propagate, which is preferable to making every
  /// user's email readable by every signed-in user.
  final String ownerName;

  const PetProfile({
    required this.id, required this.ownerId, required this.name, required this.breed,
    required this.ageLabel, required this.sex, required this.area,
    required this.species, required this.vaccinated, required this.accentColor,
    this.photoUrls = const [], this.ownerName = '',
  });

  /// Joins [parts] with ' · ', skipping blanks. Pet docs legitimately carry
  /// empty fields (a skipped breed, or an area lost to the old cold-read bug),
  /// and naive interpolation rendered those as a dangling separator.
  static String detailLine(List<String> parts) =>
      parts.where((p) => p.trim().isNotEmpty).join(' · ');

  /// Never render an empty title — some legacy docs have no name at all.
  String get displayName => name.trim().isEmpty ? 'Unnamed pet' : name;

  Map<String, dynamic> toMap() => {
        'ownerId': ownerId,
        'name': name,
        'breed': breed,
        'species': species.storageKey,
        'ageLabel': ageLabel,
        'sex': sex,
        'area': area,
        'vaccinated': vaccinated,
        'photoUrls': photoUrls,
        // Still written for anything reading the old single-photo field.
        'photoUrl': photoUrl,
        'ownerName': ownerName,
      };

  factory PetProfile.fromMap(String id, Map<String, dynamic> m) => PetProfile(
        id: id,
        ownerId: (m['ownerId'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        breed: (m['breed'] ?? '') as String,
        ageLabel: (m['ageLabel'] ?? '') as String,
        sex: (m['sex'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        species: Species.fromStorage((m['species'] ?? 'dog') as String),
        vaccinated: (m['vaccinated'] ?? false) as bool,
        accentColor: accentFor((m['name'] ?? '') as String),
        // Falls back to the legacy single `photoUrl` so pets created before the
        // gallery still render their one image instead of a placeholder.
        photoUrls: _photosFrom(m),
        ownerName: (m['ownerName'] ?? '') as String,
      );

  static List<String> _photosFrom(Map<String, dynamic> m) {
    final list = (m['photoUrls'] as List?)
        ?.whereType<String>()
        .where((u) => u.isNotEmpty)
        .toList();
    if (list != null && list.isNotEmpty) return list;
    final legacy = (m['photoUrl'] ?? '') as String;
    return legacy.isEmpty ? const [] : [legacy];
  }

  static const _accents = [
    Color(0xFFF0871E), Color(0xFFEC8FB0), Color(0xFF6B8DE0),
    Color(0xFFB79BE8), Color(0xFF2FB479),
  ];

  static Color accentFor(String seed) {
    if (seed.isEmpty) return _accents[0];
    final sum = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    return _accents[sum % _accents.length];
  }
}
