import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
    serviceType: ServiceType.walker, rate: 250, experienceYears: 4);

void main() {
  testWidgets('renders total and the pet; Continue enabled with a pet', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('uid_me@x.com'))),
    ], initialLocation: Routes.booking, extra: _pro);
    await tester.pumpAndSettle();
    expect(find.text('Bruno'), findsOneWidget);          // first of the user's pets
    expect(find.textContaining('275'), findsWidgets);    // total = 250 + 25
    expect(find.text('Continue to payment'), findsOneWidget);
  });

  testWidgets('with no pets, prompts to add one', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    ], initialLocation: Routes.booking, extra: _pro);
    await tester.pumpAndSettle();
    expect(find.text('Add a pet to book'), findsOneWidget);
  });
}
