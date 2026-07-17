import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the host + New host (unverified); shows Request to book',
      (tester) async {
    const h = Homestay(uid: 'h1', homeName: "Meera's Home", hostName: 'Meera Iyer',
        area: 'Bandra West', about: 'Spacious 2BHK with a fenced balcony.',
        homeType: HomeType.apartment, ratePerNight: 900,
        amenities: [Amenity.nearPark, Amenity.residentDog]);
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    ], initialLocation: Routes.host, extra: h);
    await tester.pumpAndSettle();
    expect(find.text("Meera's Home"), findsOneWidget);
    expect(find.textContaining('Meera Iyer'), findsOneWidget);
    expect(find.text('Spacious 2BHK with a fenced balcony.'), findsOneWidget);
    expect(find.textContaining('New host'), findsOneWidget); // unverified
    expect(find.textContaining('Apartment'), findsOneWidget); // homeType chip
    expect(find.textContaining('Near park'), findsOneWidget); // amenity chip
    expect(find.text('Request to book'), findsOneWidget); // now wired; see homestay_request_screen_test.dart
  });

  testWidgets('a verified host shows the Verified host badge', (tester) async {
    const h = Homestay(uid: 'h2', homeName: 'Anjali Stays', hostName: 'Anjali Rao',
        area: 'Pali Hill', about: 'x', homeType: HomeType.villa, ratePerNight: 1100,
        verified: true);
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    ], initialLocation: Routes.host, extra: h);
    await tester.pumpAndSettle();
    expect(find.text('Pawgo Verified host'), findsOneWidget);
    expect(find.textContaining('New host'), findsNothing);
  });
}
