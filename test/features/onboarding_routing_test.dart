import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _pumpLocationAs(WidgetTester tester, Role role) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(
      uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com', area: '', role: role));
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
  ], initialLocation: Routes.location);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pet parent routes to Create Pet', (tester) async {
    await _pumpLocationAs(tester, Role.petParent);
    expect(find.text('Add your pet'), findsOneWidget);
  });
  testWidgets('service pro routes to Pro setup', (tester) async {
    await _pumpLocationAs(tester, Role.servicePro);
    expect(find.text('Offer your services'), findsOneWidget);
  });
  testWidgets('homestay host routes to Host setup', (tester) async {
    await _pumpLocationAs(tester, Role.homestayHost);
    expect(find.text('List your home'), findsOneWidget);
  });
}
