import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/review.dart';
import '../review_repository.dart';

class FirestoreReviewRepository implements ReviewRepository {
  final FirebaseFirestore _db;
  FirestoreReviewRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('reviews');

  @override
  Future<void> submitReview(Review review) async {
    final reviewRef = _col.doc(review.bookingId); // one review per booking
    final targetCol = review.targetType == ReviewTargetType.pro ? 'pros' : 'homestays';
    final targetRef = _db.collection(targetCol).doc(review.targetId);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(reviewRef);
      if (existing.exists) return; // idempotent — the booking was already rated
      final targetSnap = await tx.get(targetRef);
      final data = targetSnap.data() ?? const <String, dynamic>{};
      final count = (data['reviewCount'] ?? 0) as int;
      final rating = ((data['rating'] ?? 0) as num).toDouble();
      final newCount = count + 1;
      final newRating = (rating * count + review.stars) / newCount;
      tx.set(reviewRef, review.toMap());
      tx.update(targetRef, {'rating': newRating, 'reviewCount': newCount});
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
