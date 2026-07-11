import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test("myPetsProvider streams the signed-in user's own pets", () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('uid_me@x.com'))),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(myPetsProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();
    final pets = container.read(myPetsProvider).value ?? [];
    expect(pets, isNotEmpty);
    expect(pets.every((p) => p.ownerId == 'uid_me@x.com'), isTrue);
  });
}
