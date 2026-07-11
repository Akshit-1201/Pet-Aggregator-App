import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test("currentProProvider streams the signed-in user's listing", () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository([
        const Pro(uid: 'uid_me@x.com', name: 'Me', area: 'Khar', bio: 'x',
            serviceType: ServiceType.sitter, rate: 400, experienceYears: 2),
      ])),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(currentProProvider, (_, _) {}, fireImmediately: true);
    container.listen(prosProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();
    expect(container.read(currentProProvider).value?.rate, 400);
    expect((container.read(prosProvider).value ?? []).length, 1);
  });
}
