import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
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
}
