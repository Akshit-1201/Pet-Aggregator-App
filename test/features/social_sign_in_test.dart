import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

// Client request: "gmail etc routed logins".
void main() {
  Future<(FakeAuthRepository, InMemoryUserRepository)> pumpWelcome(WidgetTester tester,
      {UserProfile? existing}) async {
    final auth = FakeAuthRepository();
    final users = InMemoryUserRepository();
    if (existing != null) await users.createUser(existing);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.welcome);
    await tester.pumpAndSettle();
    return (auth, users);
  }

  testWidgets('Welcome offers Continue with Google above the email form', (tester) async {
    await pumpWelcome(tester);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('or use email'), findsOneWidget);
  });

  testWidgets('a returning Google user goes straight Home', (tester) async {
    final (auth, _) = await pumpWelcome(tester, existing: const UserProfile(
        uid: 'uid_a@gmail.com', name: 'Aakarsh Rao', email: 'a@gmail.com',
        area: 'Bandra West', role: Role.petParent));
    auth.nextSocialAccount = (email: 'a@gmail.com', name: 'Aakarsh Rao');

    await tester.tap(find.byKey(const Key('social-google')));
    await tester.pumpAndSettle();
    expect(find.text('Hey Aakarsh'), findsOneWidget);
  });

  testWidgets('a new Google user finishes setup with no password or email step', (tester) async {
    final (auth, users) = await pumpWelcome(tester);
    auth.nextSocialAccount = (email: 'new@gmail.com', name: 'Meera Iyer');

    await tester.tap(find.byKey(const Key('social-google')));
    await tester.pumpAndSettle();
    expect(find.text('Finish setting up'), findsOneWidget);
    expect(find.text('Meera Iyer'), findsOneWidget);   // prefilled from Google
    expect(find.text('Password'), findsNothing);       // nothing to type
    expect(find.text('Confirm your email'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final saved = await users.watchUser('uid_new@gmail.com').first;
    expect(saved!.name, 'Meera Iyer');
    expect(saved.email, 'new@gmail.com');
    expect(find.text('Choose your area'), findsOneWidget); // Location step
  });

  testWidgets('cancelling the Google sheet leaves you on Welcome, signed out', (tester) async {
    final (auth, _) = await pumpWelcome(tester);
    auth.nextSocialAccount = null;
    await tester.tap(find.byKey(const Key('social-google')));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(auth.currentUser, isNull);
  });

  testWidgets('a provider failure is explained, not swallowed', (tester) async {
    final (auth, _) = await pumpWelcome(tester);
    auth.nextError = const AuthFailure(AuthFailureType.providerNotConfigured,
        "Google sign-in isn't available yet. Please use email and password.");
    await tester.tap(find.byKey(const Key('social-google')));
    await tester.pump();
    expect(find.textContaining("Google sign-in isn't available yet"), findsOneWidget);
  });
}
