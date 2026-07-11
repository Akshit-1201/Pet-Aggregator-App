import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('filling the form and saving writes a pro listing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Aarav Sharma',
        email: 'me@x.com', area: 'Bandra West', role: Role.servicePro));
    final pros = InMemoryProRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      proRepositoryProvider.overrideWithValue(pros),
    ], initialLocation: Routes.proSetup);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '250'); // rate
    await tester.enterText(find.byType(TextField).at(1), '4');   // experience
    await tester.enterText(find.byType(TextField).at(2), 'Friendly walker'); // bio
    await tester.tap(find.text('Save listing'));
    await tester.pumpAndSettle();

    final mine = await pros.watchPro(auth.currentUser!.uid).first;
    expect(mine!.name, 'Aarav Sharma');
    expect(mine.rate, 250);
    expect(mine.area, 'Bandra West');
  });
}
