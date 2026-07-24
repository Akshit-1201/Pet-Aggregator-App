import '../models/user_profile.dart';

abstract interface class UserRepository {
  Future<void> createUser(UserProfile profile);
  Future<void> updateArea(String uid, String area);
  Future<void> markNotificationsSeen(String uid);
  Future<void> setPhotoUrl(String uid, String url);

  /// Persists the push-category toggles. Written as a partial update so it can
  /// never clobber the rest of the profile.
  Future<void> setNotificationPrefs(String uid, NotificationPrefs prefs);

  Stream<UserProfile?> watchUser(String uid);
}
