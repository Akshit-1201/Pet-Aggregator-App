import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('another user\'s pet renders fields + Send a Woof records a woof', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(const UserProfile(uid: 'owner1', name: 'Karan Mehta',
        email: 'k@x.com', area: 'Bandra West', role: Role.petParent));
    final swipes = InMemorySwipeRepository();
    // ownerName lives on the pet: users/{uid} is owner-read-only, so resolving
    // it through userByIdProvider silently rendered a bare em dash on device.
    const pet = PetProfile(id: 'pet1', ownerId: 'owner1', name: 'Bruno', breed: 'Labrador',
        ageLabel: '2 yrs', sex: 'male', area: 'Bandra West', species: Species.dog,
        vaccinated: true, accentColor: Color(0xFFF0871E), ownerName: 'Karan Mehta');

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      swipeRepositoryProvider.overrideWithValue(swipes),
    ], initialLocation: Routes.petProfile, extra: pet);
    await tester.pumpAndSettle();

    expect(find.text('Bruno'), findsWidgets);
    expect(find.textContaining('Labrador'), findsOneWidget);
    expect(find.textContaining('Vaccinated'), findsWidgets);
    expect(find.textContaining('Karan Mehta'), findsOneWidget); // owner card

    await tester.tap(find.text('Send a Woof 👋'));
    await tester.pumpAndSettle();
    expect(await swipes.watchSwipedPetIds(auth.currentUser!.uid).first, contains('pet1'));
  });

  testWidgets('own pet hides the woof button', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pet = PetProfile(id: 'pet1', ownerId: auth.currentUser!.uid, name: 'Bruno',
        breed: 'Labrador', ageLabel: '2 yrs', sex: 'male', area: 'Bandra West',
        species: Species.dog, vaccinated: true, accentColor: const Color(0xFFF0871E));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
    ], initialLocation: Routes.petProfile, extra: pet);
    await tester.pumpAndSettle();
    expect(find.text('Send a Woof 👋'), findsNothing);
  });
}
