import '../models/review.dart';

abstract interface class ReviewRepository {
  /// Idempotent (keyed by bookingId): writes the review + aggregates the
  /// running-average rating + reviewCount onto the target.
  Future<void> submitReview(Review review);
  Stream<List<Review>> watchReviews(String targetId);
  Stream<Set<String>> watchMyReviewedBookingIds(String uid);
}
