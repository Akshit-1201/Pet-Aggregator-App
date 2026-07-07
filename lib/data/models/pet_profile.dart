import 'package:flutter/material.dart';

enum Species { dog, cat, other }

class PetProfile {
  final String name, breed, ageLabel, distanceLabel;
  final Species species;
  final bool vaccinated;
  final Color accentColor;
  const PetProfile({
    required this.name, required this.breed, required this.ageLabel,
    required this.distanceLabel, required this.species,
    required this.vaccinated, required this.accentColor,
  });
}
