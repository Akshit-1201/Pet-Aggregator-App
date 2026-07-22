import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Finish writes a pet owned by the current user and goes Home', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pets = InMemoryPetRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(pets),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.createPet);

    expect(find.text('Add your pet'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Bruno');   // Pet name
    await tester.enterText(find.byType(TextField).at(1), 'Labrador');// Breed
    await tester.enterText(find.byType(TextField).at(2), '2 yrs');   // Age
    await tester.tap(find.text('Finish & explore Pawgo'));
    await tester.pumpAndSettle();

    final mine = await pets.watchMyPets(auth.currentUser!.uid).first;
    expect(mine.single.name, 'Bruno');
    expect(mine.single.ownerId, auth.currentUser!.uid);
    expect(find.text('Home'), findsWidgets); // Home shell
  });

  // Regression: the screen cold-read currentUserProfileProvider for the area,
  // which is still AsyncLoading when you land here straight from onboarding —
  // so it silently saved area:''. 7 of 9 real pet docs had a blank area.
  testWidgets('Finish saves the area even when the profile has not warmed yet',
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(
        uid: uid, name: 'Radhika', email: 'me@x.com', area: 'Bandra West', role: Role.petParent));
    final pets = InMemoryPetRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(pets),
      userRepositoryProvider.overrideWithValue(users),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
      // Landing directly on Create Pet means nothing has listened to the
      // profile provider yet — exactly the onboarding path that broke.
    ], initialLocation: Routes.createPet);

    await tester.enterText(find.byType(TextField).at(0), 'Bruno');
    await tester.enterText(find.byType(TextField).at(1), 'Labrador');
    await tester.enterText(find.byType(TextField).at(2), '2 yrs');
    await tester.tap(find.text('Finish & explore Pawgo'));
    await tester.pumpAndSettle();

    final mine = await pets.watchMyPets(uid).first;
    expect(mine.single.area, 'Bandra West');
  });
}
