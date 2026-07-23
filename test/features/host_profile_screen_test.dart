import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/widgets/pg_page_dots.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/homestay/home_gallery.dart';
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

  // A bare PageView looked like a single photo, so the extra photos went unseen.
  testWidgets('multiple photos show a counter + dots and open a full-screen viewer',
      (tester) async {
    const h = Homestay(uid: 'h3', homeName: 'Photo Home', hostName: 'Meera Iyer',
        area: 'Bandra West', about: 'x', homeType: HomeType.apartment, ratePerNight: 900,
        photoUrls: ['https://x.test/1.jpg', 'https://x.test/2.jpg', 'https://x.test/3.jpg']);
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    ], initialLocation: Routes.host, extra: h);
    await tester.pumpAndSettle();

    expect(find.text('1/3'), findsOneWidget);                     // counter
    expect(find.byType(PgPageDots), findsOneWidget);              // swipe affordance
    expect(find.byType(PhotoViewerScreen), findsNothing);

    await tester.tap(find.byKey(const Key('gallery-photo-0')));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewerScreen), findsOneWidget);       // full-screen viewer
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-photo-viewer')));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewerScreen), findsNothing);
  });

  testWidgets('a single photo shows no counter (nothing to swipe to)', (tester) async {
    const h = Homestay(uid: 'h4', homeName: 'One Photo', hostName: 'Meera Iyer',
        area: 'Bandra West', about: 'x', homeType: HomeType.apartment, ratePerNight: 900,
        photoUrls: ['https://x.test/only.jpg']);
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    ], initialLocation: Routes.host, extra: h);
    await tester.pumpAndSettle();
    expect(find.byType(PgPageDots), findsNothing);
    expect(find.text('1/1'), findsNothing);
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
