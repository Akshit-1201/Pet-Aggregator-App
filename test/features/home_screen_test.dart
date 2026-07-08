import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Home greets the user and lists live nearby pets', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(
        uid: auth.currentUser!.uid, name: 'Radhika Nair', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('someone-else'))),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();

    expect(find.text('Hey Radhika 👋'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Woof!'), findsWidgets);
  });

  testWidgets('Home shows an empty state when there are no nearby pets', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();
    expect(find.text('No pets nearby yet'), findsOneWidget);
  });
}
