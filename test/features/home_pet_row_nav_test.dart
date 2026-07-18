import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('tapping a Home pet row opens Pet-profile', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pets = InMemoryPetRepository([PetProfile(id: 'p9', ownerId: 'other', name: 'Mochi',
        breed: 'Persian cat', ageLabel: '1 yr', sex: 'female', area: 'Khar', species: Species.cat,
        vaccinated: true, accentColor: PetProfile.accentFor('Mochi'))]);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(pets),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();
    expect(find.text('Mochi'), findsOneWidget);
    await tester.tap(find.text('Mochi'));
    await tester.pumpAndSettle();
    expect(find.text('Pet parent'), findsOneWidget); // Pet-profile owner card
  });
}
