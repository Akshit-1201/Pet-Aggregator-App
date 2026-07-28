import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/discovery/nearby_map_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

/// Task 9 converted three `go` call sites that navigate *deeper* into the app
/// to `push`, so the destination lands on top of a real stack and back can
/// pop off it. `go` replaces the whole stack, so back from a screen reached
/// that way exits the app or lands somewhere wrong. Each test below opens the
/// pushed screen from its real entry point, fires a system back, and asserts
/// the parent screen (not just "some screen") is showing — the guard against
/// a future "tidy-up" silently turning the `push` back into a `go`.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('back from the map returns to Discover', (t) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(t, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('owner-b'))),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      // GoogleMap is a platform view that cannot render under flutter_test.
      mapViewBuilderProvider.overrideWithValue((cam, markers) => const SizedBox.expand()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.discover);
    await t.pumpAndSettle();

    // "Discover" alone also matches the bottom-nav tab label, so the Discover
    // screen's own subtitle (not shown anywhere else) is the unambiguous marker.
    expect(find.text('Pets near you'), findsOneWidget);
    await t.tap(find.textContaining('Map view'));
    await t.pumpAndSettle();
    expect(find.textContaining('pets nearby'), findsOneWidget); // the map's sheet

    await _systemBack(t);

    expect(find.text('Pets near you'), findsOneWidget);
    expect(find.textContaining('pets nearby'), findsNothing);
  });

  testWidgets('back from the map returns to Home', (t) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(
        uid: auth.currentUser!.uid, name: 'Radhika Nair', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));

    await pumpPgApp(t, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('someone-else'))),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
      // GoogleMap is a platform view that cannot render under flutter_test.
      mapViewBuilderProvider.overrideWithValue((cam, markers) => const SizedBox.expand()),
    ], initialLocation: Routes.home);
    await t.pumpAndSettle();

    expect(find.text('Hey Radhika 👋'), findsOneWidget);
    await t.tap(find.text('See map →'));
    await t.pumpAndSettle();
    expect(find.textContaining('pets nearby'), findsOneWidget); // the map's sheet

    await _systemBack(t);

    expect(find.text('Hey Radhika 👋'), findsOneWidget);
    expect(find.textContaining('pets nearby'), findsNothing);
  });

  testWidgets('back from pro-setup returns to Services', (t) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com',
        area: 'Khar', role: Role.servicePro));

    await pumpPgApp(t, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      // No listing yet, so the "Set up your services" banner renders.
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    ], initialLocation: Routes.services);
    await t.pumpAndSettle();

    expect(find.text('Services near you'), findsOneWidget);
    await t.tap(find.text('Set up your services'));
    await t.pumpAndSettle();
    expect(find.text('Offer your services'), findsOneWidget); // Pro-setup screen

    await _systemBack(t);

    expect(find.text('Services near you'), findsOneWidget);
    expect(find.text('Offer your services'), findsNothing);
  });
}
