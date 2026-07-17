// test/data/review_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import '../support/fakes.dart';

void main() {
  test('submitReview aggregates a running average, dedupes, and lists newest-first', () async {
    final repo = InMemoryReviewRepository();
    Review rev(String bookingId, int stars, int at) => Review(
        targetType: ReviewTargetType.pro, targetId: 'pro1', targetName: 'Aarav',
        authorId: 'me', authorName: 'Radhika', bookingId: bookingId, stars: stars, createdAt: at);

    await repo.submitReview(rev('b1', 5, 100));
    await repo.submitReview(rev('b2', 4, 200));
    expect(repo.aggregateFor('pro1').count, 2);
    expect(repo.aggregateFor('pro1').rating, 4.5); // (5 + 4) / 2

    // Re-submitting the same booking is a no-op.
    await repo.submitReview(rev('b1', 1, 300));
    expect(repo.aggregateFor('pro1').count, 2);

    final list = await repo.watchReviews('pro1').first;
    expect(list.map((r) => r.bookingId).toList(), ['b2', 'b1']); // newest first
    expect((await repo.watchMyReviewedBookingIds('me').first), {'b1', 'b2'});
  });
}
