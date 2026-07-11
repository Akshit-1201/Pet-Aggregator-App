import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _aarav = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
    serviceType: ServiceType.walker, rate: 250, experienceYears: 4);

void main() {
  testWidgets('lists live pros', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository([_aarav])),
    ], initialLocation: Routes.services);
    await tester.pumpAndSettle();
    expect(find.text('Services near you'), findsOneWidget);
    expect(find.text('Aarav Sharma'), findsOneWidget);
  });

  testWidgets('shows a set-up banner for a servicePro without a listing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com',
        area: 'Khar', role: Role.servicePro));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    ], initialLocation: Routes.services);
    await tester.pumpAndSettle();
    expect(find.text('Set up your services'), findsOneWidget);
  });
}
