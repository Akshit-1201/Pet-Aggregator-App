import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/pro.dart';
import '../pro_repository.dart';

class FirestoreProRepository implements ProRepository {
  final FirebaseFirestore _db;
  FirestoreProRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('pros');

  @override
  Future<void> upsertPro(Pro pro) => _col.doc(pro.uid).set({
        ...pro.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Stream<Pro?> watchPro(String uid) => _col.doc(uid).snapshots().map(
      (doc) => doc.exists ? Pro.fromMap(uid, doc.data()!) : null);

  @override
  Stream<List<Pro>> watchPros() => _col
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Pro.fromMap(d.id, d.data())).toList());
}
