import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/swipe.dart';
import '../swipe_repository.dart';

class FirestoreSwipeRepository implements SwipeRepository {
  final FirebaseFirestore _db;
  FirestoreSwipeRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('swipes');

  @override
  Future<void> recordSwipe(Swipe swipe) => _col.doc(swipe.id).set({
        ...swipe.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  @override
  Stream<Set<String>> watchSwipedPetIds(String uid) => _col
      .where('fromUid', isEqualTo: uid)
      .snapshots()
      .map((snap) => snap.docs.map((d) => d.data()['petId'] as String).toSet());

  @override
  Future<bool> hasReciprocalWoof({required String otherUid, required String myUid}) async {
    final q = await _col
        .where('fromUid', isEqualTo: otherUid)
        .where('ownerId', isEqualTo: myUid)
        .where('direction', isEqualTo: 'woof')
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }
}
