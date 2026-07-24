import 'package:cloud_firestore/cloud_firestore.dart';
import '../push_token_repository.dart';

class FirestorePushTokenRepository implements PushTokenRepository {
  final FirebaseFirestore _db;
  FirestorePushTokenRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String token) =>
      _db.collection('users').doc(uid).collection('fcmTokens').doc(token);

  @override
  Future<void> saveToken(String uid, String token) => _doc(uid, token).set({
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'platform': 'android',
      });

  @override
  Future<void> removeToken(String uid, String token) => _doc(uid, token).delete();
}
