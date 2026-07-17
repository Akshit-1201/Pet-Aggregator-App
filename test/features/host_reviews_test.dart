import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Host profile shows real reviews', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    const homestay = Homestay(uid: 'host1', homeName: "Meera's Home", hostName: 'Meera Iyer',
        area: 'Bandra West', about: 'Spacious 2BHK.', homeType: HomeType.apartment,
        ratePerNight: 900, rating: 5.0, reviewCount: 1);
    final reviews = InMemoryReviewRepository();
    await reviews.submitReview(Review(targetType: ReviewTargetType.homestay, targetId: 'host1',
        targetName: "Meera's Home", authorId: 'someone', authorName: 'Karan M.', bookingId: 'hb1',
        stars: 5, text: 'Bruno felt right at home.', createdAt: 1));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ], initialLocation: Routes.host, extra: homestay);
    await tester.pumpAndSettle();

    expect(find.text('Karan M.'), findsOneWidget);
    expect(find.textContaining('felt right at home'), findsOneWidget);
  });
}
