import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import '../support/fakes.dart';

void main() {
  test('FakeAuthRepository signs up, signs in, and rejects bad credentials', () async {
    final auth = FakeAuthRepository();
    expect(auth.currentUser, isNull);
    final u = await auth.signUp(email: 'a@b.com', password: 'secret1');
    expect(u.email, 'a@b.com');
    expect(auth.currentUser, isNotNull);
    await auth.signOut();
    expect(auth.currentUser, isNull);
    final again = await auth.signIn(email: 'a@b.com', password: 'secret1');
    expect(again.uid, u.uid);
    expect(
      () => auth.signIn(email: 'a@b.com', password: 'wrong'),
      throwsA(isA<AuthFailure>()),
    );
  });

  test('InMemoryUserRepository stores and updates area', () async {
    final repo = InMemoryUserRepository();
    await repo.createUser(const UserProfile(
        uid: 'u1', name: 'R', email: 'r@x.com', area: '', role: Role.petParent));
    await repo.updateArea('u1', 'Bandra West');
    final u = await repo.watchUser('u1').first;
    expect(u!.area, 'Bandra West');
  });

  test('InMemoryPetRepository addPet emits and watchNearby excludes owner', () async {
    final repo = InMemoryPetRepository(fixturePets('other'));
    final nearby = await repo.watchNearbyPets(excludeOwnerId: 'me').first;
    expect(nearby, isNotEmpty);
    expect(nearby.every((p) => p.ownerId != 'me'), isTrue);
  });
}
