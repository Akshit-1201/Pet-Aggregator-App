import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_profile.dart';
import '../user_repository.dart';

class FirestoreUserRepository implements UserRepository {
  final FirebaseFirestore _db;
  FirestoreUserRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('users');

  @override
  Future<void> createUser(UserProfile profile) => _col.doc(profile.uid).set({
        ...profile.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> updateArea(String uid, String area) => _col.doc(uid).update({'area': area});

  @override
  Future<void> setPhotoUrl(String uid, String url) => _col.doc(uid).update({'photoUrl': url});

  @override
  Future<void> setNotificationPrefs(String uid, NotificationPrefs prefs) =>
      _col.doc(uid).update(prefs.toMap());

  @override
  Stream<UserProfile?> watchUser(String uid) => _col.doc(uid).snapshots().map(
      (doc) => doc.exists ? UserProfile.fromMap(uid, doc.data()!) : null);
}
