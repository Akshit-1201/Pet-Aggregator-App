import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _pump(WidgetTester tester, {InMemorySwipeRepository? swipes}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('owner-b'))),
    swipeRepositoryProvider.overrideWithValue(swipes ?? InMemorySwipeRepository()),
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
