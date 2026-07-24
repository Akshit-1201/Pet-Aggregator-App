// Firebase Auth only validates that an address is syntactically well-formed —
// it never checks the mailbox exists or that whoever typed it owns it. (The
// address that prompted this, abc@email.com, is on a real domain with live MX
// records, so no amount of domain checking would have caught it.) Proving
// ownership via the emailed link is the actual fix, and these pin the gate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('an unverified account is bounced off protected routes to the gate',
      (tester) async {
    final auth = FakeAuthRepository(emailVerified: false);
    await auth.signUp(email: 'abc@email.com', password: 'secret1');

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();

    expect(find.text('Confirm your email'), findsOneWidget);
    expect(find.text('abc@email.com'), findsOneWidget);
  });

  testWidgets('a verified account passes straight through the gate', (tester) async {
    final auth = FakeAuthRepository(); // verified by default
    await auth.signUp(email: 'real@gmail.com', password: 'secret1');

    // Settings rather than Home: it is protected (so the redirect is exercised)
    // but light enough that this test measures the gate, not the Home shell.
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      preferencesRepositoryProvider.overrideWithValue(InMemoryPreferencesRepository()),
    ], initialLocation: Routes.settings);
    await tester.pumpAndSettle();

    expect(find.text('Confirm your email'), findsNothing);
    expect(find.text('Dark mode'), findsOneWidget); // actually landed
  });

  testWidgets('the gate offers a resend and moves on once verified', (tester) async {
    final auth = FakeAuthRepository(emailVerified: false);
    await auth.signUp(email: 'abc@email.com', password: 'secret1');

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.verifyEmail);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Resend email'));
    await tester.pumpAndSettle();
    expect(auth.verificationEmailsSent, 1);
    // Cooldown replaces the button so it can't be hammered.
    expect(find.textContaining('Resend email in'), findsOneWidget);

    // Simulate the person clicking the link, then confirming in-app.
    auth.emailVerified = true;
    await tester.tap(find.text("I've confirmed it"));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your email'), findsNothing);
  });

  testWidgets('signing up sends a verification email and stops at the gate',
      (tester) async {
    final auth = FakeAuthRepository(emailVerified: false);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.signup);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Radhika Nair');
    await tester.enterText(find.byType(TextField).at(1), 'abc@email.com');
    await tester.enterText(find.byType(TextField).at(2), 'secret1');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(auth.verificationEmailsSent, 1);
    expect(find.text('Confirm your email'), findsOneWidget);
  });
}
