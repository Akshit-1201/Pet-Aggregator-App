import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/auth/phone_sign_in_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

// Client request: "any person can log in using email or phone number".
void main() {
  group('normaliseIndianMobile', () {
    test('accepts common ways of typing a mobile number', () {
      for (final raw in ['9812345678', '98123 45678', '+91 98123-45678', '919812345678', '09812345678']) {
        expect(normaliseIndianMobile(raw), '+919812345678', reason: raw);
      }
    });
    test('rejects landlines, short numbers and non-Indian prefixes', () {
      for (final raw in ['', '12345', '2212345678', '981234567', '+1 415 555 0100']) {
        expect(normaliseIndianMobile(raw), isNull, reason: raw);
      }
    });
  });

  Future<(FakeAuthRepository, InMemoryUserRepository)> pumpPhone(WidgetTester tester,
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
    await tester.tap(find.byKey(const Key('social-phone')));
    await tester.pumpAndSettle();
    return (auth, users);
  }

  Future<void> enterNumberAndSend(WidgetTester tester, String number) async {
    await tester.enterText(find.descendant(of: find.byKey(const Key('phone-number')),
        matching: find.byType(TextField)), number);
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.descendant(of: find.byKey(const Key('phone-code')),
        matching: find.byType(TextField)), code);
    await tester.tap(find.text('Verify & continue'));
    await tester.pumpAndSettle();
  }

  testWidgets('Welcome offers phone sign-in', (tester) async {
    await pumpPhone(tester);
    expect(find.text('Continue with phone'), findsOneWidget);
  });

  testWidgets('a new number gets a code, then finishes setup with no email or password',
      (tester) async {
    final (auth, users) = await pumpPhone(tester);
    await enterNumberAndSend(tester, '98123 45678');
    expect(auth.textedNumbers, ['+919812345678']);
    expect(find.text('Sent to +919812345678.'), findsOneWidget);

    await enterCode(tester, FakeAuthRepository.smsCode);
    expect(find.text('Finish setting up'), findsOneWidget);
    expect(find.textContaining('+919812345678'), findsOneWidget);
    expect(find.text('Password'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Aakarsh Rao');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final saved = await users.watchUser('uid_+919812345678').first;
    expect(saved!.name, 'Aakarsh Rao');
    // A confirmed phone counts as verified: no "confirm your email" detour.
    expect(find.text('Confirm your email'), findsNothing);
    expect(find.text('Choose your area'), findsOneWidget);
  });

  testWidgets('a returning phone user goes straight Home', (tester) async {
    await pumpPhone(tester, existing: const UserProfile(uid: 'uid_+919812345678',
        name: 'Aakarsh Rao', email: '', area: 'Bandra West', role: Role.petParent));
    await enterNumberAndSend(tester, '9812345678');
    await enterCode(tester, FakeAuthRepository.smsCode);
    expect(find.text('Hey Aakarsh'), findsOneWidget);
  });

  testWidgets('a wrong code is explained and you stay signed out', (tester) async {
    final (auth, _) = await pumpPhone(tester);
    await enterNumberAndSend(tester, '9812345678');
    await enterCode(tester, '000000');
    expect(find.textContaining("That code isn't right"), findsOneWidget);
    expect(auth.currentUser, isNull);
  });

  testWidgets('an invalid number never sends an SMS', (tester) async {
    final (auth, _) = await pumpPhone(tester);
    await enterNumberAndSend(tester, '12345');
    expect(find.textContaining('10-digit Indian mobile'), findsOneWidget);
    expect(auth.textedNumbers, isEmpty);
  });

  testWidgets('an unexpected failure while sending is explained, not swallowed', (tester) async {
    final (auth, _) = await pumpPhone(tester);
    auth.nextPhoneError = StateError('plugin blew up');
    await enterNumberAndSend(tester, '9812345678');
    expect(find.textContaining("Couldn't send the code"), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget); // still on step one, not busy
  });

  // A phone account has neither a password nor Google/Apple to re-check with.
  testWidgets('a phone account deletes itself after confirming an SMS code', (tester) async {
    final auth = FakeAuthRepository();
    final v = await auth.sendPhoneCode('+919812345678');
    await auth.confirmPhoneCode(v, FakeAuthRepository.smsCode);
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'A', email: '',
        area: 'Bandra West', role: Role.petParent));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      preferencesRepositoryProvider.overrideWithValue(InMemoryPreferencesRepository()),
    ], initialLocation: Routes.settings);
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
        find.text('Delete account'), find.byType(Scrollable), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(auth.deleted, isFalse); // nothing happens on the first tap but the SMS
    await tester.enterText(find.descendant(of: find.byType(AlertDialog),
        matching: find.byType(TextField)), FakeAuthRepository.smsCode);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(auth.phoneReauths, 1);
    expect(auth.deleted, isTrue);
  });
}
