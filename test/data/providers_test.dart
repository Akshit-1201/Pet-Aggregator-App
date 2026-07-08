import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('nearbyPetsProvider streams pets excluding the signed-in user', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid == uid_me@x.com

    final seed = [
      ...fixturePets('someone-else'),
      PetProfile(id: 'mine', ownerId: 'uid_me@x.com', name: 'MyDog', breed: 'Mix',
          ageLabel: '1 yr', sex: 'male', area: 'Bandra West', species: Species.dog,
          vaccinated: true, accentColor: PetProfile.accentFor('MyDog')),
    ];

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(seed)),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ]);
    addTearDown(container.dispose);

    // Keep providers alive and let the auth + pet streams settle.
    container.listen(authStateProvider, (_, __) {}, fireImmediately: true);
    container.listen(nearbyPetsProvider, (_, __) {}, fireImmediately: true);
    await pumpEventQueue();

    final async = container.read(nearbyPetsProvider);
    expect(async.hasValue, isTrue);
    final pets = async.value!;
    expect(pets, isNotEmpty);
    expect(pets.any((p) => p.name == 'MyDog'), isFalse); // own pet excluded
    expect(pets.every((p) => p.ownerId != 'uid_me@x.com'), isTrue);
  });
}
