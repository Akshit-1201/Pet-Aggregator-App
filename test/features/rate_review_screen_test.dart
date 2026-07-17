import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('rating + submit writes a review and shows the notice', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final reviews = InMemoryReviewRepository();
    const target = ReviewTarget(type: ReviewTargetType.pro, id: 'pro1', name: 'Aarav Sharma',
        subtitle: 'Dog walk · Tue 15 Jul', bookingId: 'bk1');

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ], initialLocation: Routes.rate, extra: target);
    await tester.pumpAndSettle();

    expect(find.text('Aarav Sharma'), findsOneWidget);
    await tester.tap(find.text('⭐').at(4)); // 5th star
    await tester.pump();
    await tester.tap(find.text('Submit review'));
    await tester.pumpAndSettle();

    final list = await reviews.watchReviews('pro1').first;
    expect(list.single.stars, 5);
    expect(list.single.bookingId, 'bk1');
    expect(reviews.aggregateFor('pro1').rating, 5.0);
    expect(find.textContaining('review is live'), findsOneWidget);
  });
}
