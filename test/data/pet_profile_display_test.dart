import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';

// Real pet docs carry empty strings for fields the owner skipped (and, before
// the cold-read fix, an empty `area` on every pet created after 2026-07-11).
// Naive '$breed · $area' interpolation rendered those as a dangling "· " or a
// lone "·", which is what made the Discover list look broken.
void main() {
  group('detailLine', () {
    test('joins the non-empty parts only', () {
      expect(PetProfile.detailLine(['Labrador', 'Bandra West']), 'Labrador · Bandra West');
    });

    test('drops an empty trailing part instead of leaving a dangling separator', () {
      expect(PetProfile.detailLine(['Labrador', '']), 'Labrador');
    });

    test('drops an empty leading part', () {
      expect(PetProfile.detailLine(['', 'Bandra West']), 'Bandra West');
    });

    test('all-empty yields an empty string, never a bare separator', () {
      expect(PetProfile.detailLine(['', '', '']), '');
    });

    test('ignores whitespace-only parts', () {
      expect(PetProfile.detailLine(['Labrador', '   ', '2 yrs']), 'Labrador · 2 yrs');
    });
  });

  group('displayName', () {
    PetProfile pet(String name) => PetProfile(
        id: 'p1', ownerId: 'o', name: name, breed: '', ageLabel: '', sex: '',
        area: '', species: Species.dog, vaccinated: false,
        accentColor: PetProfile.accentFor(name));

    test('falls back for an empty name so a row is never blank', () {
      expect(pet('').displayName, 'Unnamed pet');
      expect(pet('   ').displayName, 'Unnamed pet');
    });

    test('uses the real name when present', () {
      expect(pet('Bruno').displayName, 'Bruno');
    });
  });
}
