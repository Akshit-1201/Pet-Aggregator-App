// Google Play's UGC policy requires an in-app report path, an in-app block path,
// and account deletion. These cover the behaviour rather than the plumbing:
// a block has to actually hide the person, and deletion has to be gated.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/report.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('blocking hides that person from the community feed, unblocking restores them', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final myUid = auth.currentUser!.uid;
    final blocks = InMemoryBlockRepository();
    final posts = InMemoryPostRepository();

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      blockRepositoryProvider.overrideWithValue(blocks),
      postRepositoryProvider.overrideWithValue(posts),
    ]);
    addTearDown(container.dispose);
    container.listen(postsProvider, (_, _) {}, fireImmediately: true);

    await posts.createPost(const Post(authorId: 'troll', authorName: 'Troll',
        category: PostCategory.health, title: 'Nonsense', body: 'x', createdAt: 2));
    await posts.createPost(const Post(authorId: 'friend', authorName: 'Friend',
        category: PostCategory.health, title: 'Real question', body: 'y', createdAt: 1));
    await pumpEventQueue();
    expect((container.read(postsProvider).value ?? []).length, 2);

    await blocks.block(myUid, 'troll');
    await pumpEventQueue();
    expect((container.read(postsProvider).value ?? []).map((p) => p.authorId), ['friend']);

    await blocks.unblock(myUid, 'troll');
    await pumpEventQueue();
    expect((container.read(postsProvider).value ?? []).length, 2);
  });

  test('blocking hides that person from the services marketplace', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final blocks = InMemoryBlockRepository();
    final pros = InMemoryProRepository();

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      blockRepositoryProvider.overrideWithValue(blocks),
      proRepositoryProvider.overrideWithValue(pros),
    ]);
    addTearDown(container.dispose);
    container.listen(prosProvider, (_, _) {}, fireImmediately: true);

    await pros.upsertPro(const Pro(uid: 'troll', name: 'Troll', area: 'Bandra',
        bio: '', serviceType: ServiceType.walker, rate: 200, experienceYears: 1));
    await pros.upsertPro(const Pro(uid: 'good', name: 'Aarav', area: 'Bandra',
        bio: '', serviceType: ServiceType.walker, rate: 250, experienceYears: 4));
    await pumpEventQueue();
    expect((container.read(prosProvider).value ?? []).length, 2);

    await blocks.block(auth.currentUser!.uid, 'troll');
    await pumpEventQueue();
    expect((container.read(prosProvider).value ?? []).map((p) => p.uid), ['good']);
  });

  test('a report carries enough context for a moderator to act', () async {
    final reports = InMemoryReportRepository();
    await reports.submitReport(Report(
      reporterId: 'me', targetType: ReportTargetType.comment, targetId: 'c1',
      contextId: 'post1', targetOwnerId: 'troll',
      reason: ReportReason.harassment, createdAt: 5));

    final r = reports.reports.single;
    // contextId is what lets a moderator find a nested comment without a
    // collection-group scan.
    expect(r.contextId, 'post1');
    expect(r.targetOwnerId, 'troll');
    // Clients may only ever file an open report; the admin panel owns the rest.
    expect(r.toMap()['status'], 'open');
  });

  test('deleting an account requires the correct password', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');

    await expectLater(
        () => auth.reauthenticate('wrong-password'),
        throwsA(isA<AuthFailure>()
            .having((e) => e.type, 'type', AuthFailureType.invalidCredentials)));
    expect(auth.deleted, isFalse);

    await auth.reauthenticate('secret1');
    await auth.deleteAccount();
    expect(auth.deleted, isTrue);
    // Deletion signs out, which is what drives the router back to onboarding.
    expect(auth.currentUser, isNull);
  });
}
