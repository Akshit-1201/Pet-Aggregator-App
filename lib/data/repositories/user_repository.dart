import '../models/user_profile.dart';

abstract interface class UserRepository {
  Future<void> createUser(UserProfile profile);
  Future<void> updateArea(String uid, String area);
  Stream<UserProfile?> watchUser(String uid);
}
