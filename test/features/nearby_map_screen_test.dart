import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/discovery/nearby_map_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  Future<InMemoryProRepository> seededPros() async {
    final r = InMemoryProRepository();
    await r.upsertPro(const Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Juhu', bio: 'b',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 4));
    return r;
  }

  const meera = Homestay(uid: 'h1', homeName: "Meera's Home", hostName: 'Meera Iyer',
      area: 'Worli', about: 'a', homeType: HomeType.apartment, ratePerNight: 900);

  Future<void> pump(WidgetTester tester, {required InMemoryProRepository pros}) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('owner-b'))),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      proRepositoryProvider.overrideWithValue(pros),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository([meera])),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      mapViewBuilderProvider.overrideWithValue((cam, markers) => const SizedBox.expand()),
    ], initialLocation: Routes.nearby);
    await tester.pumpAndSettle();
  }

  testWidgets('pets layer lists nearby pets; a row opens the Pet profile', (tester) async {
    await pump(tester, pros: await seededPros());
    expect(find.textContaining('pets nearby'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);

    await tester.tap(find.text('Bruno'));
    await tester.pumpAndSettle();
    expect(find.text('Send a Woof 👋'), findsOneWidget); // Pet-profile screen
  });

  testWidgets('chips switch to pros and homestays layers', (tester) async {
    await pump(tester, pros: await seededPros());

    // The chip strip is a horizontally-scrollable single row (6 chips, some
    // multi-word) — on the 420-wide test surface the later chips start out
    // scrolled past the right edge, so each is scrolled into view before
    // it's tapped (mirrors what a real finger-scroll would do on device).
    await tester.ensureVisible(find.text('🧑 Pros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🧑 Pros'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pros nearby'), findsOneWidget);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Bruno'), findsNothing);

    await tester.ensureVisible(find.text('🏡 Homestays'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🏡 Homestays'));
    await tester.pumpAndSettle();
    expect(find.textContaining('homestays nearby'), findsOneWidget);
    expect(find.text("Meera's Home"), findsOneWidget);

    await tester.ensureVisible(find.text('🐱 Cats'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🐱 Cats'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pets nearby'), findsOneWidget);
    expect(find.text('Mochi'), findsOneWidget);   // the cat fixture
    expect(find.text('Bruno'), findsNothing);     // dogs filtered out
  });
}
