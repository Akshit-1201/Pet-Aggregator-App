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
  final String id, ownerId, name, breed, ageLabel, sex, area;
  final Species species;
  final bool vaccinated;
  final Color accentColor;

  const PetProfile({
    required this.id, required this.ownerId, required this.name, required this.breed,
    required this.ageLabel, required this.sex, required this.area,
    required this.species, required this.vaccinated, required this.accentColor,
  });

  Map<String, dynamic> toMap() => {
        'ownerId': ownerId,
        'name': name,
        'breed': breed,
        'species': species.storageKey,
        'ageLabel': ageLabel,
        'sex': sex,
        'area': area,
        'vaccinated': vaccinated,
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
      );

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
