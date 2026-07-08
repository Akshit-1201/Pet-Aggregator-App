import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';

void main() {
  test('Role/Species round-trip through storage keys', () {
    expect(Role.homestayHost.storageKey, 'homestayHost');
    expect(Role.fromStorage('servicePro'), Role.servicePro);
    expect(Role.fromStorage('garbage'), Role.petParent); // safe default
    expect(Species.cat.storageKey, 'cat');
    expect(Species.fromStorage('dog'), Species.dog);
  });

  test('UserProfile toMap omits uid/createdAt and fromMap restores', () {
    const u = UserProfile(
        uid: 'u1', name: 'Radhika', email: 'r@x.com', area: 'Khar', role: Role.petParent);
    final m = u.toMap();
    expect(m.containsKey('uid'), isFalse);
    expect(m.containsKey('createdAt'), isFalse);
    expect(m['role'], 'petParent');
    final back = UserProfile.fromMap('u1', m);
    expect(back.name, 'Radhika');
    expect(back.area, 'Khar');
    expect(back.role, Role.petParent);
  });

  test('PetProfile toMap/fromMap round-trip; accent is derived', () {
    const p = PetProfile(
        id: 'p1', ownerId: 'u1', name: 'Bruno', breed: 'Labrador', ageLabel: '2 yrs',
        sex: 'male', area: 'Bandra West', species: Species.dog, vaccinated: true,
        accentColor: Color(0xFF000000));
    final m = p.toMap();
    expect(m.containsKey('id'), isFalse);
    expect(m['species'], 'dog');
    final back = PetProfile.fromMap('p1', m);
    expect(back.name, 'Bruno');
    expect(back.ownerId, 'u1');
    expect(back.species, Species.dog);
    expect(back.accentColor, PetProfile.accentFor('Bruno')); // derived, not stored
  });
}
