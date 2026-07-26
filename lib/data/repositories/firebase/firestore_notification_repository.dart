import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/notification_record.dart';
import '../notification_repository.dart';

class FirestoreNotificationRepository implements NotificationRepository {
  final FirebaseFirestore _db;
  FirestoreNotificationRepository([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _items(String uid) =>
      _db.collection('notifications').doc(uid).collection('items');

  @override
  Stream<List<NotificationRecord>> watch(String uid) {
    if (uid.isEmpty) return Stream.value(const []);
    return _items(uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs
            .map((d) => NotificationRecord.fromMap(d.id, d.data()))
            .toList());
  }

  /// Rules allow the owner to change `read` and nothing else.
  @override
  Future<void> markRead(String uid, String id) =>
      _items(uid).doc(id).update({'read': true});

  @override
  Future<void> markAllRead(String uid) async {
    final unread = await _items(uid).where('read', isEqualTo: false).limit(400).get();
    if (unread.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in unread.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }
}
