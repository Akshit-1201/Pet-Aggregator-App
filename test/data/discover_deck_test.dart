import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('discoverDeckProvider excludes own pets and already-swiped pets', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('someone-else'))),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository([
        const Swipe(fromUid: 'uid_me@x.com', petId: 'p1', ownerId: 'someone-else', direction: SwipeDirection.pass),
      ])),
    ]);
    addTearDown(container.dispose);

    container.listen(swipedPetIdsProvider, (_, _) {}, fireImmediately: true);
    container.listen(discoverDeckProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();

    final deck = container.read(discoverDeckProvider).value!;
    expect(deck.any((p) => p.id == 'p1'), isFalse); // already swiped
    expect(deck, isNotEmpty); // p2, p3 remain
    expect(deck.every((p) => p.ownerId != 'uid_me@x.com'), isTrue);
  });
}
