import '../models/swipe.dart';

abstract interface class SwipeRepository {
  Future<void> recordSwipe(Swipe swipe);
  Stream<Set<String>> watchSwipedPetIds(String uid);
  Stream<int> watchMyWoofCount(String uid);
  Future<bool> hasReciprocalWoof({required String otherUid, required String myUid});
}
