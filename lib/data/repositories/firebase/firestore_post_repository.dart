import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/post.dart';
import '../post_repository.dart';

class FirestorePostRepository implements PostRepository {
  final FirebaseFirestore _db;
  FirestorePostRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('posts');

  @override
  Future<Post> createPost(Post post) async {
    final ref = await _col.add(post.toMap());
    return Post.fromMap(ref.id, post.toMap());
  }

  @override
  Stream<List<Post>> watchPosts() => _col
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Post.fromMap(d.id, d.data())).toList());

  @override
  Future<void> addComment(String postId, Comment comment) async {
    await _col.doc(postId).collection('comments').add(comment.toMap());
    await _col.doc(postId).update({'replyCount': FieldValue.increment(1)});
  }

  @override
  Stream<List<Comment>> watchComments(String postId) => _col
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt')
      .snapshots()
      .map((snap) => snap.docs.map((d) => Comment.fromMap(d.id, d.data())).toList());
}
