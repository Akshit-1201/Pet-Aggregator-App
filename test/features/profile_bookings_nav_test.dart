import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('the Profile Bookings stat opens My Bookings', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.profile);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();
    expect(find.text('My Bookings'), findsOneWidget);
  });

  // The menu rows were placeholders ("coming soon") until on-device QA caught
  // that tapping "My bookings" did nothing — the stat above was the only way in.
  testWidgets('the Profile "My bookings" row opens My Bookings', (tester) async {
    await _pumpProfile(tester);

    await tester.tap(find.text('My bookings'));
    await tester.pumpAndSettle();
    expect(find.text('My Bookings'), findsOneWidget);
  });

  // The Received tab only exists for someone who actually has a listing
  // (MyBookingsScreen forces tab 0 otherwise), so this seeds a host.
  testWidgets('the Profile "Bookings received" row opens the Received tab for a host',
      (tester) async {
    await _pumpProfile(tester, homestays: [
      const Homestay(uid: 'uid_me@x.com', homeName: 'My Home', hostName: 'Me',
          area: 'Khar', about: 'x', homeType: HomeType.apartment, ratePerNight: 900),
    ]);

    await tester.tap(find.text('Bookings received'));
    await tester.pumpAndSettle();
    // Received's empty state is distinct from tab 0's, so it pins the right tab.
    expect(find.text('No bookings for your listing yet.'), findsOneWidget);
  });

  // Reported by the client: for a pet parent "My bookings" and "My homestays"
  // opened the same list. Without a listing there is nothing "received", so
  // the second row must not appear at all.
  testWidgets('a pet parent sees one bookings row, not a duplicate', (tester) async {
    await _pumpProfile(tester);
    expect(find.text('My bookings'), findsOneWidget);
    expect(find.text('Bookings received'), findsNothing);
    expect(find.text('My homestays'), findsNothing);
  });
}

Future<void> _pumpProfile(WidgetTester tester, {List<Homestay>? homestays}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
    homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
    proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository(homestays)),
  ], initialLocation: Routes.profile);
  await tester.pumpAndSettle();
}
