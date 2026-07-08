import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('signed-out splash advances to Onboarding', (tester) async {
    await pumpPgApp(tester,
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
        initialLocation: Routes.splash);
    expect(find.text('Pawgo'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600)); // brand delay + auth
    await tester.pumpAndSettle();
    expect(find.text('Find playmates just around the corner'), findsOneWidget);
  });

  testWidgets('signed-in splash advances to Home', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.splash);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets); // bottom nav
  });
}
