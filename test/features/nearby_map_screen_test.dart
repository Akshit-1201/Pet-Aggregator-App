import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Nearby shows a count and lists real nearby pets', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('owner-b'))),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
    ], initialLocation: Routes.nearby);
    await tester.pumpAndSettle();
    expect(find.textContaining('pets nearby'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
  });
}
