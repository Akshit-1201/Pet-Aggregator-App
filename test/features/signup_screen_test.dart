import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('shows the three roles and Continue', (tester) async {
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.signup);
    expect(find.text('Pet Parent'), findsOneWidget);
    expect(find.text('Homestay Host'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('filling the form creates account + profile and goes to Location', (tester) async {
    final auth = FakeAuthRepository();
    final users = InMemoryUserRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    ], initialLocation: Routes.signup);

    await tester.enterText(find.byType(TextField).at(0), 'Radhika Nair');
    await tester.enterText(find.byType(TextField).at(1), 'radhika@x.com');
    await tester.enterText(find.byType(TextField).at(2), 'secret1');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(auth.currentUser, isNotNull);
    final profile = await users.watchUser(auth.currentUser!.uid).first;
    expect(profile!.name, 'Radhika Nair');
    expect(find.text('Choose your area'), findsOneWidget); // Location screen
  });
}
