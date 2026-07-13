import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('posting writes a post and shows Post-live', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Radhika',
        email: 'me@x.com', area: 'Bandra West', role: Role.petParent));
    final repo = InMemoryPostRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      postRepositoryProvider.overrideWithValue(repo),
    ], initialLocation: Routes.newPost);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Best paw balm?');
    await tester.enterText(find.byType(TextField).at(1), 'Monsoon is rough.');
    await tester.tap(find.text('Post to community'));
    await tester.pumpAndSettle();

    final posts = await repo.watchPosts().first;
    expect(posts.single.title, 'Best paw balm?');
    expect(posts.single.authorName, 'Radhika');
    expect(find.text('Your post is live! 🎉'), findsOneWidget);
  });

  testWidgets('empty title is blocked', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final repo = InMemoryPostRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      postRepositoryProvider.overrideWithValue(repo),
    ], initialLocation: Routes.newPost);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post to community'));
    await tester.pumpAndSettle();
    expect(await repo.watchPosts().first, isEmpty);
    expect(find.text('Add a title.'), findsOneWidget);
  });
}
