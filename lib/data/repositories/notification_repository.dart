import '../models/notification_record.dart';

abstract interface class NotificationRepository {
  /// Newest first. Capped server-side — the feed is a rolling window.
  Stream<List<NotificationRecord>> watch(String uid);
  Future<void> markRead(String uid, String id);
  Future<void> markAllRead(String uid);
}
