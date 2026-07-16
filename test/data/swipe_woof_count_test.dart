import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import '../support/fakes.dart';

void main() {
  test('watchMyWoofCount counts only my woof swipes', () async {
    final repo = InMemorySwipeRepository();
    expect(await repo.watchMyWoofCount('me').first, 0);
    await repo.recordSwipe(const Swipe(fromUid: 'me', petId: 'p1', ownerId: 'o1', direction: SwipeDirection.woof));
    await repo.recordSwipe(const Swipe(fromUid: 'me', petId: 'p2', ownerId: 'o2', direction: SwipeDirection.pass));
    await repo.recordSwipe(const Swipe(fromUid: 'other', petId: 'p3', ownerId: 'o3', direction: SwipeDirection.woof));
    expect(await repo.watchMyWoofCount('me').first, 1);
  });
}
