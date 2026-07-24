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

  testWidgets('filling the form creates account + profile, then continues past the '
      'email gate to Location', (tester) async {
    // Signup no longer lands on Location directly — the email-verification gate
    // sits in between, because Firebase Auth validates an address's shape but
    // never that the mailbox exists or belongs to whoever typed it.
    final auth = FakeAuthRepository(emailVerified: false);
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
    expect(find.text('Confirm your email'), findsOneWidget);

    // Clicking the emailed link, then confirming, resumes the original funnel.
    auth.emailVerified = true;
    await tester.tap(find.text("I've confirmed it"));
    await tester.pumpAndSettle();
    expect(find.text('Choose your area'), findsOneWidget); // Location screen
  });
}
