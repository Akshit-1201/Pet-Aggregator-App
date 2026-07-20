import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _meera = Homestay(uid: 'h1', homeName: "Meera's Home", hostName: 'Meera Iyer',
    area: 'Bandra West', about: 'x', homeType: HomeType.apartment, ratePerNight: 900);

PetProfile _bruno(String ownerId) => PetProfile(id: 'p1', ownerId: ownerId, name: 'Bruno',
    breed: 'Labrador', ageLabel: '2 yrs', sex: 'male', area: 'Bandra West',
    species: Species.dog, vaccinated: true, accentColor: PetProfile.accentFor('Bruno'));

void main() {
  testWidgets('default 3-night range prices correctly; Send writes a requested booking', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final bookings = InMemoryHomestayBookingRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository([_bruno(auth.currentUser!.uid)])),
      homestayBookingRepositoryProvider.overrideWithValue(bookings),
    ], initialLocation: Routes.hostRequest, extra: _meera);
    await tester.pumpAndSettle();

    expect(find.textContaining('2700'), findsWidgets); // 900 * 3 nights
    expect(find.textContaining('2850'), findsWidgets); // + 150 fee
    expect(find.text('Bruno'), findsOneWidget);

    await tester.tap(find.textContaining('Send request to Meera'));
    await tester.pumpAndSettle();

    final mine = await bookings.watchMyHomestayBookings(auth.currentUser!.uid).first;
    expect(mine.single.petName, 'Bruno');
    expect(mine.single.nights, 3);
    expect(mine.single.total, 2850);
    expect(mine.single.status, 'requested');
    expect(find.text('Request sent! 🎉'), findsOneWidget); // navigated to Host-accepted
  });

  testWidgets('empty pets shows the Add a pet CTA instead of Send', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final bookings = InMemoryHomestayBookingRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(bookings),
    ], initialLocation: Routes.hostRequest, extra: _meera);
    await tester.pumpAndSettle();
    expect(find.text('Add a pet to book'), findsOneWidget);
    expect(find.text('Add a pet'), findsOneWidget);
    expect(find.textContaining('Send request to Meera'), findsNothing);
    expect(await bookings.watchMyHomestayBookings(auth.currentUser!.uid).first, isEmpty);
  });

  testWidgets('Host profile Request-to-book opens the Request screen', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    ], initialLocation: Routes.host, extra: _meera);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request to book'));
    await tester.pumpAndSettle();
    expect(find.text('Request booking'), findsOneWidget);
  });
}
