import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/review.dart';

void main() {
  test('ReviewTargetType wire round-trips', () {
    expect(ReviewTargetType.pro.storageKey, 'pro');
    expect(ReviewTargetType.fromStorage('homestay'), ReviewTargetType.homestay);
    expect(ReviewTargetType.fromStorage('nonsense'), ReviewTargetType.pro); // fallback
  });

  test('Review round-trips through the map', () {
    const r = Review(id: 'b1', targetType: ReviewTargetType.homestay, targetId: 'host1',
        targetName: "Meera's Home", authorId: 'me', authorName: 'Radhika', bookingId: 'b1',
        stars: 5, text: 'Lovely stay', createdAt: 42);
    final back = Review.fromMap('b1', r.toMap());
    expect(back.targetType, ReviewTargetType.homestay);
    expect(back.targetId, 'host1');
    expect(back.stars, 5);
    expect(back.text, 'Lovely stay');
    expect(back.bookingId, 'b1');
    expect(back.createdAt, 42);
  });
}
