import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('notificationsProvider surfaces a review; Mark all read clears unread', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final reviews = InMemoryReviewRepository();
    await reviews.submitReview(Review(targetType: ReviewTargetType.pro, targetId: uid,
        targetName: 'Radhika', authorId: 'k', authorName: 'Karan', bookingId: 'b1', stars: 5,
        text: 'great', createdAt: DateTime.now().millisecondsSinceEpoch));

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(notificationsProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();

    expect(container.read(notificationsProvider).length, 1);
    expect(container.read(hasUnreadNotificationsProvider), isTrue);

    await users.markNotificationsSeen(uid);
    await pumpEventQueue();
    expect(container.read(hasUnreadNotificationsProvider), isFalse); // seenAt now >= review time
  });
}
