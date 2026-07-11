import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import '../support/fakes.dart';

void main() {
  test('Swipe id is deterministic and toMap carries direction key', () {
    const s = Swipe(fromUid: 'A', petId: 'p1', ownerId: 'B', direction: SwipeDirection.woof);
    expect(s.id, 'A_p1');
    expect(s.toMap()['direction'], 'woof');
    expect(SwipeDirection.fromStorage('pass'), SwipeDirection.pass);
  });

  test('InMemorySwipeRepository records, streams ids, detects reciprocity', () async {
    final repo = InMemorySwipeRepository();
    await repo.recordSwipe(const Swipe(fromUid: 'me', petId: 'p1', ownerId: 'B', direction: SwipeDirection.woof));
    final ids = await repo.watchSwipedPetIds('me').first;
    expect(ids, {'p1'});

    // No reciprocity yet: B has not woofed one of my pets.
    expect(await repo.hasReciprocalWoof(otherUid: 'B', myUid: 'me'), isFalse);
    // B woofs my pet -> reciprocity from my perspective.
    await repo.recordSwipe(const Swipe(fromUid: 'B', petId: 'myPet', ownerId: 'me', direction: SwipeDirection.woof));
    expect(await repo.hasReciprocalWoof(otherUid: 'B', myUid: 'me'), isTrue);
  });
}
