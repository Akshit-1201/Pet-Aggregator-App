import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('postsProvider streams created posts; commentsProvider streams a post\'s comments', () async {
    final repo = InMemoryPostRepository();
    final container = ProviderContainer(overrides: [postRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    container.listen(postsProvider, (_, _) {}, fireImmediately: true);
    final post = await repo.createPost(const Post(authorId: 'u1', authorName: 'Me',
        category: PostCategory.health, title: 'T', body: 'B', createdAt: 1000));
    await pumpEventQueue();
    expect((container.read(postsProvider).value ?? []).length, 1);

    container.listen(commentsProvider(post.id), (_, _) {}, fireImmediately: true);
    await repo.addComment(post.id, const Comment(authorId: 'u2', authorName: 'You', body: 'Hi', createdAt: 2000));
    await pumpEventQueue();
    expect((container.read(commentsProvider(post.id)).value ?? []).length, 1);
  });
}
