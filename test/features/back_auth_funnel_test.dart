// The auth funnel is the highest stranding risk in the app: verify-email in
// particular used to have no back escape at all short of force-killing the
// app (every meaningful route is gated behind verification, so a plain pop
// bounces straight back here via the router redirect). These pin the fix
// for each screen in the funnel.
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/navigation/exit_confirm.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

/// Simulates the Android system back button.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

void main() {
  setUp(PgExitConfirm.reset);

  testWidgets('verify-email back signs out and reaches Welcome', (tester) async {
    // Sign up an UNVERIFIED user and land on verify-email, same as
    // test/features/email_verification_test.dart's gate tests.
    final auth = FakeAuthRepository(emailVerified: false);
    await auth.signUp(email: 'abc@email.com', password: 'secret1');

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.verifyEmail);
    await tester.pumpAndSettle();

    await _systemBack(tester);

    // A plain pop would have landed back on a protected route, been bounced
    // here again by the redirect, and looped forever — this is the bug this
    // screen's back handling fixes.
    expect(auth.currentUser, isNull);
    expect(find.text('Welcome back 👋'), findsOneWidget);
  });

  testWidgets('signup back reaches Welcome', (tester) async {
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.signup);
    await tester.pumpAndSettle();

    await _systemBack(tester);

    expect(find.text('Welcome back 👋'), findsOneWidget);
  });

  testWidgets('location back shows the exit confirmation, does not navigate',
      (tester) async {
    // Verified and signed in — location is reached only from verify-email,
    // so by this point the account exists and is already verified.
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'abc@email.com', password: 'secret1');

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.location);
    await tester.pumpAndSettle();

    await _systemBack(tester);

    // Popping to signup would be a dead end and popping to verify-email
    // would just loop (a verified user is redirected straight back off it) —
    // the toast appears and we're still on Location, not bounced anywhere.
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(find.text('Choose your area'), findsOneWidget);
  });

  testWidgets('onboarding back steps to the previous page before exiting',
      (tester) async {
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
    ], initialLocation: Routes.onboarding);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Homestays with verified hosts'), findsOneWidget);

    await _systemBack(tester);

    // Stepped back exactly one page — not exited, no exit toast either.
    expect(find.text('Trusted walkers, sitters & groomers'), findsOneWidget);
    expect(find.text('Press back again to exit'), findsNothing);
  });
}
