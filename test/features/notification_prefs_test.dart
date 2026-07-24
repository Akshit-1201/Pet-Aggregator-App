// The toggles have to persist, and default to ON for accounts that predate them
// — an absent field must never be read as "notifications off", or every existing
// user goes silently quiet.
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/widgets/pg_toggle.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  test('an absent preference field means ON, not OFF', () {
    // Accounts created before these flags exist have none of the fields.
    final prefs = NotificationPrefs.fromMap({'name': 'Radhika'});
    expect(prefs.messages, isTrue);
    expect(prefs.bookings, isTrue);
    expect(prefs.woofs, isTrue);
  });

  test('preferences round-trip through the profile map', () {
    const profile = UserProfile(
        uid: 'u1', name: 'Radhika', email: 'r@x.com', area: 'Bandra',
        role: Role.petParent,
        notify: NotificationPrefs(messages: false, bookings: true, woofs: false));
    final back = UserProfile.fromMap('u1', profile.toMap());
    expect(back.notify.messages, isFalse);
    expect(back.notify.bookings, isTrue);
    expect(back.notify.woofs, isFalse);
  });

  testWidgets('Settings shows the three categories and persists a change',
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    final uid = auth.currentUser!.uid;
    await users.createUser(UserProfile(
        uid: uid, name: 'Radhika Nair', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      preferencesRepositoryProvider.overrideWithValue(InMemoryPreferencesRepository()),
    ], initialLocation: Routes.settings);
    await tester.pumpAndSettle();

    expect(find.text('New messages'), findsOneWidget);
    expect(find.text('Booking updates'), findsOneWidget);
    expect(find.text('New Woofs & matches'), findsOneWidget);

    // Toggle 0 is Dark mode; 1..3 are the notification categories.
    await tester.tap(find.byType(PgToggle).at(1));
    await tester.pumpAndSettle();

    final saved = await users.watchUser(uid).first;
    expect(saved!.notify.messages, isFalse);
    expect(saved.notify.bookings, isTrue); // untouched
  });

  testWidgets('the dead "Nearby pet alerts" row from the prototype is not shipped',
      (tester) async {
    // There is no nearby-pet notification anywhere in the app, so the switch
    // would control nothing.
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      preferencesRepositoryProvider.overrideWithValue(InMemoryPreferencesRepository()),
    ], initialLocation: Routes.settings);
    await tester.pumpAndSettle();

    expect(find.text('Nearby pet alerts'), findsNothing);
  });
}
