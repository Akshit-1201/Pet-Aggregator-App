import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/discovery/nearby_map_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _pump(WidgetTester tester,
    {InMemorySwipeRepository? swipes, List<Override> extraOverrides = const []}) async {
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
