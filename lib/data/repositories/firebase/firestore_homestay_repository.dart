import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/homestay.dart';
import '../homestay_repository.dart';

class FirestoreHomestayRepository implements HomestayRepository {
  final FirebaseFirestore _db;
  FirestoreHomestayRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('homestays');

  @override
  Future<void> upsertHomestay(Homestay homestay) => _col.doc(homestay.uid).set({
        ...homestay.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Stream<Homestay?> watchHomestay(String uid) => _col.doc(uid).snapshots().map(
      (doc) => doc.exists ? Homestay.fromMap(uid, doc.data()!) : null);

  @override
  Stream<List<Homestay>> watchHomestays() => _col
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Homestay.fromMap(d.id, d.data())).toList());
}
