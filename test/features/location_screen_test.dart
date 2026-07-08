import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Allow persists area and continues to Create Pet', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(
        uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com', area: '', role: Role.petParent));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    ], initialLocation: Routes.location);

    expect(find.text('Enable location'), findsOneWidget);
    await tester.tap(find.text('Allow while using app'));
    await tester.pumpAndSettle();

    final profile = await users.watchUser(auth.currentUser!.uid).first;
    expect(profile!.area, 'Bandra West');
    expect(find.text('Add your pet'), findsOneWidget); // Create Pet screen
  });
}
