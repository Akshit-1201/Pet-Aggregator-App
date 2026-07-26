// Deleting an account is irreversible and Play-mandated, so the two things that
// matter are pinned here: a wrong password must not delete anything, and the
// consequences must be stated before it does.
//
// It also guards the shape. This started as a full-screen wall of prose plus a
// second password dialog; the field inside it was a Column sized to whatever
// height it was offered, which stretched the dialog to nearly the full screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<FakeAuthRepository> _openDialog(WidgetTester tester) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(
      uid: auth.currentUser!.uid, name: 'Radhika', email: 'me@x.com',
      area: 'Bandra West', role: Role.petParent));

  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    preferencesRepositoryProvider.overrideWithValue(InMemoryPreferencesRepository()),
  ], initialLocation: Routes.settings);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Delete account'));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('the dialog states what is deleted, kept and anonymised',
      (tester) async {
    await _openDialog(tester);

    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.text('This cannot be undone.'), findsOneWidget);
    expect(find.textContaining('profile, pets, photos, listings'), findsOneWidget);
    expect(find.textContaining('reviews, posts'), findsOneWidget);
    expect(find.textContaining('past bookings'), findsOneWidget);
    // Password lives in the same dialog rather than behind a second tap.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('it stays a dialog rather than filling the screen', (tester) async {
    await _openDialog(tester);

    // AlertDialog's own box spans the whole overlay, so measure the painted
    // card: the Material the Dialog lays its surface on.
    final screen = tester.getSize(find.byType(MaterialApp));
    final card = tester.getSize(find.descendant(
        of: find.byType(Dialog), matching: find.byType(Material)).first);
    expect(card.height, lessThan(screen.height * 0.5));
  });

  testWidgets('a wrong password deletes nothing and says so', (tester) async {
    final auth = await _openDialog(tester);

    await tester.enterText(find.byType(TextField), 'not-my-password');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(auth.deleted, isFalse);
    expect(auth.currentUser, isNotNull); // still signed in
    // Re-auth only asks for the password, so the error must not blame the email.
    expect(find.text('Incorrect password.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget); // stays open to retry
  });

  testWidgets('an empty password is refused before hitting the backend',
      (tester) async {
    final auth = await _openDialog(tester);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(auth.deleted, isFalse);
    expect(find.text('Enter your password to confirm.'), findsOneWidget);
  });

  testWidgets('the correct password deletes and signs out', (tester) async {
    final auth = await _openDialog(tester);

    await tester.enterText(find.byType(TextField), 'secret1');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(auth.deleted, isTrue);
    expect(auth.currentUser, isNull);
  });
}
