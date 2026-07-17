import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Pro profile shows real reviews + a rating badge', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    const pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 4, rating: 5.0, reviewCount: 1);
    final reviews = InMemoryReviewRepository();
    await reviews.submitReview(Review(targetType: ReviewTargetType.pro, targetId: 'pro1',
        targetName: 'Aarav Sharma', authorId: 'someone', authorName: 'Neha S.', bookingId: 'b1',
        stars: 5, text: 'So gentle with Bruno!', createdAt: 1));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ], initialLocation: Routes.servicePro, extra: pro);
    await tester.pumpAndSettle();

    expect(find.text('Neha S.'), findsOneWidget);
    expect(find.textContaining('So gentle'), findsOneWidget);
    expect(find.textContaining('1 reviews'), findsOneWidget); // badge (reviewCount == 1)
  });
}
