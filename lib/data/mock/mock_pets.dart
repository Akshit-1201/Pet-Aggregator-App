import 'package:flutter/material.dart';
import '../models/pet_profile.dart';

const List<PetProfile> mockPets = [
  PetProfile(name: 'Bruno', breed: 'Labrador', ageLabel: '2 yrs',
      distanceLabel: '0.4 km · Bandra West', species: Species.dog,
      vaccinated: true, accentColor: Color(0xFFF0871E)),
  PetProfile(name: 'Mochi', breed: 'Persian cat', ageLabel: '1 yr',
      distanceLabel: '0.9 km · Khar', species: Species.cat,
      vaccinated: true, accentColor: Color(0xFFEC8FB0)),
  PetProfile(name: 'Simba', breed: 'Beagle', ageLabel: '3 yrs',
      distanceLabel: '0.7 km · Bandra West', species: Species.dog,
      vaccinated: true, accentColor: Color(0xFF6B8DE0)),
  PetProfile(name: 'Coco', breed: 'Indie', ageLabel: '4 yrs',
      distanceLabel: '1.2 km · Santacruz', species: Species.dog,
      vaccinated: false, accentColor: Color(0xFFB79BE8)),
];
