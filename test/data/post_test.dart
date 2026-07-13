import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/post.dart';

void main() {
  test('PostCategory round-trips with label/emoji', () {
    expect(PostCategory.lostFound.label, 'Lost & Found');
    expect(PostCategory.fromStorage('training'), PostCategory.training);
    expect(PostCategory.fromStorage('nonsense'), PostCategory.health); // safe default
  });

  test('Post toMap omits id, keeps createdAt/replyCount; fromMap restores', () {
    const p = Post(authorId: 'u1', authorName: 'Radhika', category: PostCategory.health,
        title: 'Vet in Bandra?', body: 'Bruno needs boosters.', createdAt: 1234);
    final m = p.toMap();
    expect(m.containsKey('id'), isFalse);
    expect(m['category'], 'health');
    expect(m['createdAt'], 1234);
    expect(m['replyCount'], 0);
    final back = Post.fromMap('post1', m);
    expect(back.id, 'post1');
    expect(back.title, 'Vet in Bandra?');
    expect(back.category, PostCategory.health);
  });

  test('Comment round-trips', () {
    const c = Comment(authorId: 'u2', authorName: 'Pali', body: 'Dr. Sequeira is great', createdAt: 99);
    final back = Comment.fromMap('c1', c.toMap());
    expect(back.id, 'c1');
    expect(back.body, 'Dr. Sequeira is great');
    expect(back.createdAt, 99);
  });

  test('timeAgo buckets', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    expect(Post.timeAgo(0), 'just now');
    expect(Post.timeAgo(now - 30 * 1000), 'just now');
    expect(Post.timeAgo(now - 5 * 60 * 1000), '5m');
    expect(Post.timeAgo(now - 3 * 3600 * 1000), '3h');
    expect(Post.timeAgo(now - 2 * 86400 * 1000), '2d');
  });
}
