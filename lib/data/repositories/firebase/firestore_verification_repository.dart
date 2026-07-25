import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../models/verification_request.dart';
import '../verification_repository.dart';

class FirestoreVerificationRepository implements VerificationRepository {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  FirestoreVerificationRepository([FirebaseFirestore? db, FirebaseStorage? storage])
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('verificationRequests');

  @override
  Stream<VerificationRequest?> watchMyRequest(String uid) => _col.doc(uid).snapshots().map(
      (doc) => doc.exists ? VerificationRequest.fromMap(uid, doc.data()!) : null);

  @override
  Future<String> uploadDocument({
    required String uid, required Uint8List bytes, required int index,
  }) async {
    final path = 'verification/$uid/doc_$index.jpg';
    await _storage.ref(path).putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    // Deliberately no getDownloadURL(): the object is unreadable by clients and
    // the admin panel signs a short-lived URL when a reviewer opens the request.
    return path;
  }

  @override
  Future<void> submit(VerificationRequest request) =>
      _col.doc(request.uid).set(request.toMap());
}
