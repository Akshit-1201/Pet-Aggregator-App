import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the OP + comments; sending a reply adds a comment', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Radhika',
        email: 'me@x.com', area: 'Bandra West', role: Role.petParent));
    const post = Post(id: 'post1', authorId: 'op', authorName: 'Dev', category: PostCategory.health,
        title: 'Best vet in Bandra?', body: 'Bruno needs boosters.', createdAt: 1000);
    final repo = InMemoryPostRepository([post]);
    await repo.addComment('post1', const Comment(authorId: 'x', authorName: 'Pali',
        body: 'Dr. Sequeira is great', createdAt: 10));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      postRepositoryProvider.overrideWithValue(repo),
    ], initialLocation: Routes.thread, extra: post);
    await tester.pumpAndSettle();

    expect(find.text('Best vet in Bandra?'), findsOneWidget);
    expect(find.textContaining('Dr. Sequeira'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Try Happy Tails clinic');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    final comments = await repo.watchComments('post1').first;
    expect(comments.length, 2);
    expect(comments.last.body, 'Try Happy Tails clinic');
    expect(comments.last.authorName, 'Radhika');
    expect(find.textContaining('Happy Tails'), findsOneWidget);
  });

  testWidgets('back from a go-entered thread lands on Community (no crash)', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    const post = Post(id: 'post1', authorId: 'op', authorName: 'Dev', category: PostCategory.health,
        title: 'Vet in Bandra?', body: 'b', createdAt: 1000);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      postRepositoryProvider.overrideWithValue(InMemoryPostRepository([post])),
    ], initialLocation: Routes.thread, extra: post);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('Add a reply…'), findsNothing);          // left the thread, no exception
    expect(find.text('Mumbai pet parents'), findsOneWidget);  // landed on the Community feed
  });
}
