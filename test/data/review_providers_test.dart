import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('reviewsProvider streams a target reviews; myReviewedBookingIdsProvider tracks mine', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final reviews = InMemoryReviewRepository();

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(reviewsProvider('pro1'), (_, _) {}, fireImmediately: true);
    container.listen(myReviewedBookingIdsProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();

    await reviews.submitReview(Review(targetType: ReviewTargetType.pro, targetId: 'pro1',
        targetName: 'Aarav', authorId: uid, authorName: 'Me', bookingId: 'b1', stars: 5, createdAt: 1));
    await pumpEventQueue();
    expect((container.read(reviewsProvider('pro1')).value ?? []).length, 1);
    expect(container.read(myReviewedBookingIdsProvider).value, {'b1'});
  });
}
