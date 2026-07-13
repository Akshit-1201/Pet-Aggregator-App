import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import '../support/fakes.dart';

Post _post(int createdAt, String title) => Post(authorId: 'u1', authorName: 'Me',
    category: PostCategory.health, title: title, body: 'b', createdAt: createdAt);

void main() {
  test('createPost returns a post with an id and lists newest-first', () async {
    final repo = InMemoryPostRepository();
    expect(await repo.watchPosts().first, isEmpty);
    final older = await repo.createPost(_post(1000, 'Older'));
    final newer = await repo.createPost(_post(2000, 'Newer'));
    expect(older.id, isNotEmpty);
    final list = await repo.watchPosts().first;
    expect(list.map((p) => p.title).toList(), ['Newer', 'Older']); // desc by createdAt
    expect(newer.title, 'Newer');
  });

  test('addComment emits in watchComments (oldest-first) and increments replyCount', () async {
    final repo = InMemoryPostRepository();
    final post = await repo.createPost(_post(1000, 'T'));
    expect(await repo.watchComments(post.id).first, isEmpty);
    await repo.addComment(post.id, const Comment(authorId: 'a', authorName: 'A', body: 'first', createdAt: 10));
    await repo.addComment(post.id, const Comment(authorId: 'b', authorName: 'B', body: 'second', createdAt: 20));
    final comments = await repo.watchComments(post.id).first;
    expect(comments.map((c) => c.body).toList(), ['first', 'second']);
    final updated = (await repo.watchPosts().first).firstWhere((p) => p.id == post.id);
    expect(updated.replyCount, 2);
  });
}
