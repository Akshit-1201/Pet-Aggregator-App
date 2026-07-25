import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/community/community_feed_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _p1 = Post(id: 'p1', authorId: 'a', authorName: 'Dev', category: PostCategory.health,
    title: 'Vet in Bandra?', body: 'x', createdAt: 2000, replyCount: 3);
const _p2 = Post(id: 'p2', authorId: 'b', authorName: 'Kim', category: PostCategory.training,
    title: 'Puppy classes?', body: 'y', createdAt: 1000);

void main() {
  testWidgets('lists live posts; category filter narrows the list', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      postRepositoryProvider.overrideWithValue(InMemoryPostRepository([_p1, _p2])),
    ], providesPostRepository: true, initialLocation: Routes.community);
    await tester.pumpAndSettle();

    // Scoped to the screen itself: the persistent bottom nav also has a
    // 'Community' tab label, so an unscoped find.text('Community') would
    // match both.
    expect(find.descendant(of: find.byType(CommunityFeedScreen), matching: find.text('Community')),
        findsOneWidget);
    expect(find.text('Vet in Bandra?'), findsOneWidget);
    expect(find.text('Puppy classes?'), findsOneWidget);

    await tester.tap(find.text('🎓 Training'));
    await tester.pumpAndSettle();
    expect(find.text('Vet in Bandra?'), findsNothing);
    expect(find.text('Puppy classes?'), findsOneWidget);
  });

  testWidgets('the + FAB opens New post', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      postRepositoryProvider.overrideWithValue(InMemoryPostRepository()),
    ], providesPostRepository: true, initialLocation: Routes.community);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('New post'), findsOneWidget);
  });
}
