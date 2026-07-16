import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _pumpProfile(WidgetTester tester, FakeAuthRepository auth) async {
  final uid = auth.currentUser!.uid;
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(uid: uid, name: 'Radhika Nair', email: 'me@x.com',
      area: 'Bandra West', role: Role.petParent));
  final pets = InMemoryPetRepository([PetProfile(id: 'p1', ownerId: uid, name: 'Bruno',
      breed: 'Labrador', ageLabel: '2 yrs', sex: 'male', area: 'Bandra West',
      species: Species.dog, vaccinated: true, accentColor: PetProfile.accentFor('Bruno'))]);
  final swipes = InMemorySwipeRepository();
  await swipes.recordSwipe(Swipe(fromUid: uid, petId: 'x', ownerId: 'o', direction: SwipeDirection.woof));
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    petRepositoryProvider.overrideWithValue(pets),
    swipeRepositoryProvider.overrideWithValue(swipes),
    bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
  ], initialLocation: Routes.profile);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders name/role/area, own pet + real stats; Sign out signs out', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await _pumpProfile(tester, auth);
    expect(find.text('Radhika Nair'), findsOneWidget);
    expect(find.textContaining('Pet Parent · Bandra West'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Woofs'), findsOneWidget); // stat label
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.currentUser, isNull);
  });

  testWidgets('tapping the own-pet card opens Pet-profile', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await _pumpProfile(tester, auth);
    await tester.tap(find.text('Bruno'));
    await tester.pumpAndSettle();
    expect(find.text('Pet parent'), findsOneWidget); // owner card is unique to Pet-profile
  });
}
