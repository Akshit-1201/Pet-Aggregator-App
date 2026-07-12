import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('currentHomestayProvider streams the signed-in host\'s listing', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository([
        const Homestay(uid: 'uid_me@x.com', homeName: 'My Home', hostName: 'Me', area: 'Khar',
            about: 'x', homeType: HomeType.apartment, ratePerNight: 800),
      ])),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(currentHomestayProvider, (_, _) {}, fireImmediately: true);
    container.listen(homestaysProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();
    expect(container.read(currentHomestayProvider).value?.ratePerNight, 800);
    expect((container.read(homestaysProvider).value ?? []).length, 1);
  });
}
