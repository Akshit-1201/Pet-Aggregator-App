import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('myWoofCountProvider streams my woofs; userByIdProvider streams a user', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final swipes = InMemorySwipeRepository();
    await swipes.recordSwipe(Swipe(fromUid: uid, petId: 'p1', ownerId: 'o1', direction: SwipeDirection.woof));
    final users = InMemoryUserRepository();
    await users.createUser(const UserProfile(uid: 'o1', name: 'Owner One', email: 'o@x.com', area: 'Khar', role: Role.petParent));

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      swipeRepositoryProvider.overrideWithValue(swipes),
      userRepositoryProvider.overrideWithValue(users),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(myWoofCountProvider, (_, _) {}, fireImmediately: true);
    container.listen(userByIdProvider('o1'), (_, _) {}, fireImmediately: true);
    await pumpEventQueue();
    expect(container.read(myWoofCountProvider).value, 1);
    expect(container.read(userByIdProvider('o1')).value?.name, 'Owner One');
  });
}
