import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';

void main() {
  test('PetProfile holds its fields', () {
    const p = PetProfile(name: 'Bruno', breed: 'Labrador', ageLabel: '2 yrs',
        distanceLabel: '0.4 km', species: Species.dog, vaccinated: true,
        accentColor: Color(0xFFF59E2E));
    expect(p.name, 'Bruno');
    expect(p.species, Species.dog);
  });

  test('Role label is human readable', () {
    expect(Role.petParent.label, 'Pet Parent');
    expect(Role.homestayHost.label, 'Homestay Host');
  });
}
