import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/features/community/post_live_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the post-live celebration + actions', (tester) async {
    const p = Post(id: 'p1', authorId: 'u1', authorName: 'Radhika', category: PostCategory.health,
        title: 'Vet in Bandra?', body: 'x', createdAt: 1000);
    await pumpPg(tester, const PostLiveScreen(post: p));
    expect(find.text('Your post is live! 🎉'), findsOneWidget);
    expect(find.text('View my post'), findsOneWidget);
    expect(find.text('Back to community'), findsOneWidget);
  });
}
