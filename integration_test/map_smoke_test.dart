// On-device smoke test: opens the Nearby map with the REAL GoogleMap platform
// view (the widget tests stub it out), so a native Maps crash shows up here.
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../test/support/fakes.dart';
import '../test/support/pump.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Nearby map opens with the real GoogleMap without crashing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('owner-b'))),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    ], initialLocation: Routes.nearby);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(GoogleMap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
