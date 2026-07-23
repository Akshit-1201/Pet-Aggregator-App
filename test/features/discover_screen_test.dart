import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/data/repositories/swipe_repository.dart';
import 'package:pet_aggregator_app/features/discovery/nearby_map_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

/// A swipe repository whose writes/reads never settle until [gate] completes —
/// stands in for a slow network so a test can assert the UI does not wait on it.
class _BlockingSwipeRepository implements SwipeRepository {
  final Future<void> gate;
  final InMemorySwipeRepository _inner = InMemorySwipeRepository();
  _BlockingSwipeRepository(this.gate);

  @override
  Future<void> recordSwipe(Swipe swipe) async {
    await gate;
    return _inner.recordSwipe(swipe);
  }

  @override
  Future<bool> hasReciprocalWoof({required String otherUid, required String myUid}) async {
    await gate;
    return _inner.hasReciprocalWoof(otherUid: otherUid, myUid: myUid);
  }

  @override
  Stream<Set<String>> watchSwipedPetIds(String uid) => _inner.watchSwipedPetIds(uid);

  @override
  Stream<int> watchMyWoofCount(String uid) => _inner.watchMyWoofCount(uid);
}

Future<void> _pump(WidgetTester tester,
    {SwipeRepository? swipes, List<Override> extraOverrides = const []}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('owner-b'))),
    swipeRepositoryProvider.overrideWithValue(swipes ?? InMemorySwipeRepository()),
    ...extraOverrides,
  ], initialLocation: Routes.discover);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the first nearby pet', (tester) async {
    await _pump(tester);
    expect(find.text('Bruno'), findsOneWidget);
  });

  // Regression: the deck used to be seeded ONLY from ref.listen, which fires on a
  // change (loading→data) and never delivers the current value. When the provider
  // is already resolved at first build (warm providers, or the State recreated
  // after the deck resolved once) there is no transition, _deck stayed null, and
  // the screen buffered on a spinner forever. Seeding from the watched value fixes it.
  testWidgets('renders the deck when the provider already has a value at first build',
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pets = fixturePets('owner-b'); // Bruno, Mochi, …
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(pets)),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      // Already-resolved before the screen builds → ref.listen sees no transition.
      discoverDeckProvider.overrideWithValue(AsyncData<List<PetProfile>>(pets)),
    ], initialLocation: Routes.discover);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Bruno'), findsOneWidget);
  });

  testWidgets('Woof (no reciprocity) advances to the next pet', (tester) async {
    final swipes = InMemorySwipeRepository();
    await _pump(tester, swipes: swipes);
    await tester.tap(find.byKey(const Key('discover-woof')));
    await tester.pumpAndSettle();
    expect(find.text('Bruno'), findsNothing);
    expect(find.text('Mochi'), findsOneWidget);
    final ids = await swipes.watchSwipedPetIds('uid_me@x.com').first;
    expect(ids.contains('p1'), isTrue); // Bruno recorded
  });

  // Regression: _onWoof used to await recordSwipe + hasReciprocalWoof BEFORE
  // advancing, so the swiped card sat animated off-screen and the user stared at
  // the empty placeholder ("blank white card") until the network replied.
  testWidgets('a Woof advances to the next pet without waiting for the network',
      (tester) async {
    final gate = Completer<void>();
    await _pump(tester, swipes: _BlockingSwipeRepository(gate.future));
    expect(find.text('Bruno'), findsOneWidget);

    await tester.tap(find.byKey(const Key('discover-woof')));
    await tester.pump(); // network call still pending — must not block the deck
    expect(find.text('Bruno'), findsNothing);
    expect(find.text('Mochi'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  // The chip opened the map all along but was mislabelled "Filters".
  testWidgets('the header chip is labelled Map view and opens the map', (tester) async {
    await _pump(tester, extraOverrides: [
      // GoogleMap is a platform view that cannot render under flutter_test.
      mapViewBuilderProvider.overrideWithValue((cam, markers) => const SizedBox.expand()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ]);
    expect(find.textContaining('Filters'), findsNothing);
    expect(find.textContaining('Map view'), findsOneWidget);

    await tester.tap(find.textContaining('Map view'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pets nearby'), findsOneWidget); // the map's sheet
  });

  testWidgets('Woof with a reciprocal woof shows the match screen', (tester) async {
    final swipes = InMemorySwipeRepository([
      const Swipe(fromUid: 'owner-b', petId: 'my-pet', ownerId: 'uid_me@x.com', direction: SwipeDirection.woof),
    ]);
    await _pump(tester, swipes: swipes);
    await tester.tap(find.byKey(const Key('discover-woof')));
    await tester.pumpAndSettle();
    expect(find.text("It's a Woof match! 🎉"), findsOneWidget);
  });
}
