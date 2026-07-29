// Confirm-before-leaving for the four screens where a stray back press
// destroys real, expensive-to-redo work — most costly, 3-5 uploaded photos.
// An untouched form must still pop silently: a dialog on an empty form
// trains people to dismiss it unread, which then defeats it on the screens
// that matter. Every case below tests both directions on the screen it
// covers.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

/// Simulates the Android system back button/gesture.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

Future<FakeAuthRepository> _signedIn() async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  return auth;
}

/// Every screen under test is reached by `push` from a live parent in
/// production (profile, community feed, homestay list) — never landed on
/// cold — and none of them declares `upTo`/`upToIfEmpty`, so a clean form
/// popping silently depends entirely on `context.canPop()` being true.
///
/// `context.canPop()` is read once, when the screen itself builds (it feeds
/// `PgBackScope`'s `canPop:` for `PopScope`, re-evaluated on every rebuild —
/// see `test/core/pg_back_scope_test.dart`'s "canPop is true when nothing
/// needs interception"). Landing directly on the route via `initialLocation`
/// bakes in canPop() == false forever, regardless of anything pushed later
/// on top of it. So: land on Home first (a real entry already in the
/// stack), then push the screen under test on top of that — giving it
/// something real to pop off of, exactly like the fix already applied
/// throughout `pg_back_scope_test.dart`.
Future<void> _pushOverHome(
  WidgetTester t, {
  required List<Override> overrides,
  required String route,
}) async {
  await pumpPgApp(t, overrides: overrides, initialLocation: Routes.home);
  await t.pumpAndSettle();
  final ctx = t.element(find.text('Home').first);
  GoRouter.of(ctx).push(route);
  await t.pumpAndSettle();
}

/// The repositories Home itself reads. Home stays mounted (just off the top
/// of the stack) underneath the pushed screen, so it still needs these to
/// build without throwing — the same set create_pet_screen_test.dart uses
/// for its "Finish ... goes Home" case.
List<Override> _homeOverrides(FakeAuthRepository auth) => [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider
          .overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ];

void main() {
  group('create-pet', () {
    Future<void> push(WidgetTester t, FakeAuthRepository auth) => _pushOverHome(
          t,
          overrides: [
            ..._homeOverrides(auth),
            storageRepositoryProvider.overrideWithValue(InMemoryStorageRepository()),
            imagePickerServiceProvider.overrideWithValue(
                FakeImagePickerService(Uint8List.fromList([1, 2, 3]))),
          ],
          route: Routes.createPet,
        );

    testWidgets('create-pet back pops silently when nothing was entered', (t) async {
      final auth = await _signedIn();
      await push(t, auth);
      expect(find.text('Add your pet'), findsOneWidget);

      await _systemBack(t);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Add your pet'), findsNothing); // left the screen
    });

    testWidgets('create-pet back warns once a name is typed', (t) async {
      final auth = await _signedIn();
      await push(t, auth);

      // 'Simba', not 'Bruno' — 'Bruno' is this field's own hint text, which
      // stays mounted (invisible) even once real text is entered, so it
      // would falsely double-match `find.text`.
      await t.enterText(find.byType(TextField).at(0), 'Simba'); // pet name
      await t.pump();
      await _systemBack(t);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text("This pet isn't saved yet. Leaving now discards it."),
          findsOneWidget);

      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();

      expect(find.text('Add your pet'), findsOneWidget); // still here
      expect(find.text('Simba'), findsOneWidget); // typed text intact
    });

    testWidgets('create-pet back warns once a photo is attached', (t) async {
      final auth = await _signedIn();
      await push(t, auth);

      // The expensive case: 3-5 uploaded photos are the most costly
      // accidental loss in the app.
      await t.tap(find.byKey(const Key('add-pet-photo')));
      await t.pumpAndSettle();
      await _systemBack(t);

      expect(find.byType(AlertDialog), findsOneWidget);

      await t.tap(find.text('Discard'));
      await t.pumpAndSettle();

      expect(find.text('Add your pet'), findsNothing); // left, photo discarded
    });
  });

  group('pro-setup', () {
    Future<void> push(WidgetTester t, FakeAuthRepository auth) =>
        _pushOverHome(t, overrides: _homeOverrides(auth), route: Routes.proSetup);

    testWidgets('pro-setup back pops silently when nothing was entered', (t) async {
      final auth = await _signedIn();
      await push(t, auth);
      expect(find.text('Offer your services'), findsOneWidget);

      await _systemBack(t);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Offer your services'), findsNothing); // left the screen
    });

    testWidgets('pro-setup back warns once a rate is typed', (t) async {
      final auth = await _signedIn();
      await push(t, auth);

      // '300', not '250' — '250' is this field's own hint text, which stays
      // mounted (invisible) even once real text is entered, so it would
      // falsely double-match `find.text`.
      await t.enterText(find.byType(TextField).at(0), '300'); // rate
      await t.pump();
      await _systemBack(t);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
          find.text("Your service listing isn't saved yet. Leaving now discards it."),
          findsOneWidget);

      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();

      expect(find.text('Offer your services'), findsOneWidget); // still here
      expect(find.text('300'), findsOneWidget); // typed text intact
    });

    // Rate is a couple of digits; bio is the field that costs the most to
    // retype, so it stands in here for the "expensive" case create-pet and
    // host-setup cover with photos.
    testWidgets('pro-setup back warns once a bio is typed', (t) async {
      final auth = await _signedIn();
      await push(t, auth);

      await t.enterText(find.byType(TextField).at(2), 'Friendly walker'); // bio
      await t.pump();
      await _systemBack(t);

      expect(find.byType(AlertDialog), findsOneWidget);

      await t.tap(find.text('Discard'));
      await t.pumpAndSettle();

      expect(find.text('Offer your services'), findsNothing); // left, bio discarded
    });
  });

  group('host-setup', () {
    Future<void> push(WidgetTester t, FakeAuthRepository auth) => _pushOverHome(
          t,
          overrides: [
            ..._homeOverrides(auth),
            storageRepositoryProvider.overrideWithValue(InMemoryStorageRepository()),
            imagePickerServiceProvider.overrideWithValue(
                FakeImagePickerService(Uint8List.fromList([1, 2, 3]))),
          ],
          route: Routes.hostSetup,
        );

    testWidgets('host-setup back pops silently when nothing was entered', (t) async {
      final auth = await _signedIn();
      await push(t, auth);
      expect(find.text('List your home'), findsOneWidget);

      await _systemBack(t);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('List your home'), findsNothing); // left the screen
    });

    testWidgets('host-setup back warns once a name is typed', (t) async {
      final auth = await _signedIn();
      await push(t, auth);

      // Not "Meera's Home" — that's this field's own hint text, which stays
      // mounted (invisible) even once real text is entered, so it would
      // falsely double-match `find.text`.
      await t.enterText(find.byType(TextField).at(0), "Bruno's Retreat"); // home name
      await t.pump();
      await _systemBack(t);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
          find.text("Your homestay listing isn't saved yet. Leaving now discards it."),
          findsOneWidget);

      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();

      expect(find.text('List your home'), findsOneWidget); // still here
      expect(find.text("Bruno's Retreat"), findsOneWidget); // typed text intact
    });

    testWidgets('host-setup back warns once a photo is attached', (t) async {
      final auth = await _signedIn();
      await push(t, auth);

      // The expensive case: 3-5 uploaded photos are the most costly
      // accidental loss in the app.
      await t.tap(find.byKey(const Key('add-home-photo')));
      await t.pumpAndSettle();
      await _systemBack(t);

      expect(find.byType(AlertDialog), findsOneWidget);

      await t.tap(find.text('Discard'));
      await t.pumpAndSettle();

      expect(find.text('List your home'), findsNothing); // left, photo discarded
    });
  });

  group('new-post', () {
    Future<void> push(WidgetTester t, FakeAuthRepository auth) => _pushOverHome(
          t,
          overrides: [
            ..._homeOverrides(auth),
            imagePickerServiceProvider.overrideWithValue(FakeImagePickerService(kTinyPng)),
          ],
          route: Routes.newPost,
        );

    testWidgets('new-post back pops silently when nothing was entered', (t) async {
      final auth = await _signedIn();
      await push(t, auth);
      expect(find.text('New post'), findsOneWidget);

      await _systemBack(t);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('New post'), findsNothing); // left the screen
    });

    testWidgets('new-post back warns once a title is typed', (t) async {
      final auth = await _signedIn();
      await push(t, auth);

      await t.enterText(find.byType(TextField).at(0), 'Best paw balm?'); // title
      await t.pump();
      await _systemBack(t);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text("This post isn't published yet. Leaving now discards it."),
          findsOneWidget);

      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();

      expect(find.text('New post'), findsOneWidget); // still here
      expect(find.text('Best paw balm?'), findsOneWidget); // typed text intact
    });

    testWidgets('new-post back warns once a photo is attached', (t) async {
      final auth = await _signedIn();
      await push(t, auth);

      await t.tap(find.text('📷 Photo'));
      await t.pumpAndSettle();
      await _systemBack(t);

      expect(find.byType(AlertDialog), findsOneWidget);

      await t.tap(find.text('Discard'));
      await t.pumpAndSettle();

      expect(find.text('New post'), findsNothing); // left, photo discarded
    });
  });
}
