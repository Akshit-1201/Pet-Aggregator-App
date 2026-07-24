import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/review.dart';
import '../review_repository.dart';

class FirestoreReviewRepository implements ReviewRepository {
  final FirebaseFirestore _db;
  FirestoreReviewRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('reviews');

  /// Writes only the review itself. The target's `rating`/`reviewCount` used to
  /// be recomputed here, which meant the rules had to let clients write those
  /// fields — and a rule cannot check arithmetic, so any signed-in user could
  /// set any pro's rating to 5.0. Aggregation now happens in the
  /// `onReviewCreated` Function, so the fields are server-only.
  @override
  Future<void> submitReview(Review review) async {
    final reviewRef = _col.doc(review.bookingId); // one review per booking
    await _db.runTransaction((tx) async {
      final existing = await tx.get(reviewRef);
      if (existing.exists) return; // idempotent — the booking was already rated
      tx.set(reviewRef, review.toMap());
    });
  }

  @override
  Stream<List<Review>> watchReviews(String targetId) => _col
      .where('targetId', isEqualTo: targetId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Review.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Stream<Set<String>> watchMyReviewedBookingIds(String uid) => _col
      .where('authorId', isEqualTo: uid)
      .snapshots()
      .map((snap) => snap.docs.map((d) => (d.data()['bookingId'] ?? '') as String).toSet());
}
