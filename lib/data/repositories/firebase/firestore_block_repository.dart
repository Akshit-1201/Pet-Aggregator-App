import 'package:cloud_firestore/cloud_firestore.dart';
import '../block_repository.dart';

class FirestoreBlockRepository implements BlockRepository {
  final FirebaseFirestore _db;
  FirestoreBlockRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('blocked');

  @override
  Stream<Set<String>> watchBlockedUids(String uid) =>
      _col(uid).snapshots().map((snap) => snap.docs.map((d) => d.id).toSet());

  @override
  Future<void> block(String uid, String blockedUid) =>
      _col(uid).doc(blockedUid).set({'createdAt': DateTime.now().millisecondsSinceEpoch});

  @override
  Future<void> unblock(String uid, String blockedUid) => _col(uid).doc(blockedUid).delete();
}
