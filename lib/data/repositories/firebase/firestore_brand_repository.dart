import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/brand.dart';
import '../brand_repository.dart';

class FirestoreBrandRepository implements BrandRepository {
  final FirebaseFirestore _db;
  FirestoreBrandRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('brands');

  @override
  Future<void> upsertBrand(Brand brand) => _col.doc(brand.uid).set({
        ...brand.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Stream<Brand?> watchBrand(String uid) => _col.doc(uid).snapshots().map(
      (doc) => doc.exists ? Brand.fromMap(uid, doc.data()!) : null);

  @override
  Stream<List<Brand>> watchBrands() => _col
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Brand.fromMap(d.id, d.data())).toList());
}
