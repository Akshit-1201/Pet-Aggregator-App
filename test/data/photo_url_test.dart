// test/data/photo_url_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import '../support/fakes.dart';

void main() {
  test('PetProfile.photoUrl round-trips and defaults to empty', () {
    final pet = PetProfile(id: 'p1', ownerId: 'u1', name: 'Bruno', breed: 'Labrador',
        ageLabel: '2 yrs', sex: 'male', area: 'Bandra West', species: Species.dog,
        vaccinated: true, accentColor: PetProfile.accentFor('Bruno'),
        photoUrl: 'https://x/pet.jpg');
    expect(PetProfile.fromMap('p1', pet.toMap()).photoUrl, 'https://x/pet.jpg');
    expect(PetProfile.fromMap('p1', const {}).photoUrl, '');
  });

  test('UserProfile.photoUrl round-trips + copyWith', () {
    const u = UserProfile(uid: 'me', name: 'Radhika', email: 'r@x.com', area: 'Bandra',
        role: Role.petParent, photoUrl: 'https://x/me.jpg');
    expect(UserProfile.fromMap('me', u.toMap()).photoUrl, 'https://x/me.jpg');
    expect(UserProfile.fromMap('me', const {}).photoUrl, '');
    expect(u.copyWith(photoUrl: 'https://x/new.jpg').photoUrl, 'https://x/new.jpg');
    expect(u.copyWith(area: 'Khar').photoUrl, 'https://x/me.jpg'); // preserved
  });

  test('setPhotoUrl persists + re-emits', () async {
    final repo = InMemoryUserRepository();
    await repo.createUser(const UserProfile(uid: 'me', name: 'R', email: 'e', area: 'a',
        role: Role.petParent));
    expect((await repo.watchUser('me').first)!.photoUrl, '');
    await repo.setPhotoUrl('me', 'https://x/me.jpg');
    expect((await repo.watchUser('me').first)!.photoUrl, 'https://x/me.jpg');
  });
}
