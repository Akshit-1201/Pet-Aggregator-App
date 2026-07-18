import '../models/user_profile.dart';

abstract interface class UserRepository {
  Future<void> createUser(UserProfile profile);
  Future<void> updateArea(String uid, String area);
  Future<void> markNotificationsSeen(String uid);
  Future<void> setPhotoUrl(String uid, String url);
  Stream<UserProfile?> watchUser(String uid);
}
