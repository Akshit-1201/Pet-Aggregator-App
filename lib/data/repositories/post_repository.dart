import '../models/post.dart';

abstract interface class PostRepository {
  Future<Post> createPost(Post post);
  Stream<List<Post>> watchPosts();
  Future<void> addComment(String postId, Comment comment);
  Stream<List<Comment>> watchComments(String postId);
}
