// The token side of push is the part that fails silently: if registration
// doesn't happen, or a rotated token isn't re-saved, notifications simply stop
// arriving with no error anywhere. These pin the lifecycle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/notifications/push_registrar.dart';
import '../support/fakes.dart';

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: PushRegistrar(child: SizedBox())),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('a verified signed-in user gets their device token registered',
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final push = FakePushService();
    final tokens = InMemoryPushTokenRepository();

    await _pump(tester, [
      authRepositoryProvider.overrideWithValue(auth),
      pushServiceProvider.overrideWithValue(push),
      pushTokenRepositoryProvider.overrideWithValue(tokens),
    ]);

    expect(tokens.saved[auth.currentUser!.uid], contains('tok-1'));
  });

  testWidgets('an unverified user is not registered', (tester) async {
    // Nothing to notify them about — every screen a notification links to is
    // behind the verification gate.
    final auth = FakeAuthRepository(emailVerified: false);
    await auth.signUp(email: 'abc@email.com', password: 'secret1');
    final push = FakePushService();
    final tokens = InMemoryPushTokenRepository();

    await _pump(tester, [
      authRepositoryProvider.overrideWithValue(auth),
      pushServiceProvider.overrideWithValue(push),
      pushTokenRepositoryProvider.overrideWithValue(tokens),
    ]);

    expect(tokens.saved, isEmpty);
    expect(push.permissionRequests, 0);
  });

  testWidgets('declining the OS permission registers nothing and does not throw',
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final push = FakePushService(permissionGranted: false);
    final tokens = InMemoryPushTokenRepository();

    await _pump(tester, [
      authRepositoryProvider.overrideWithValue(auth),
      pushServiceProvider.overrideWithValue(push),
      pushTokenRepositoryProvider.overrideWithValue(tokens),
    ]);

    expect(push.permissionRequests, greaterThan(0));
    expect(tokens.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rotated token replaces the stored one', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final push = FakePushService();
    final tokens = InMemoryPushTokenRepository();

    await _pump(tester, [
      authRepositoryProvider.overrideWithValue(auth),
      pushServiceProvider.overrideWithValue(push),
      pushTokenRepositoryProvider.overrideWithValue(tokens),
    ]);
    final uid = auth.currentUser!.uid;
    expect(tokens.saved[uid], contains('tok-1'));

    // FCM rotates tokens on its own schedule; missing this is a silent outage.
    push.tokenRefreshes.add('tok-2');
    await tester.pump(const Duration(milliseconds: 50));
    expect(tokens.saved[uid], contains('tok-2'));
  });

  testWidgets('signing out stops this device receiving the old user\'s pushes',
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final push = FakePushService();
    final tokens = InMemoryPushTokenRepository();

    await _pump(tester, [
      authRepositoryProvider.overrideWithValue(auth),
      pushServiceProvider.overrideWithValue(push),
      pushTokenRepositoryProvider.overrideWithValue(tokens),
    ]);
    final uid = auth.currentUser!.uid;
    expect(tokens.saved[uid], contains('tok-1'));

    await auth.signOut();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tokens.saved[uid] ?? const <String>{}, isNot(contains('tok-1')));
  });

  // Where a tapped notification lands. The tap handler itself calls context.go,
  // which needs a live router this file deliberately doesn't build — so the
  // decision is extracted and pinned here instead.
  group('resolveTapRoute', () {
    // Every distinct `route:` value in functions/src/notify/catalog.ts. If a new
    // scenario introduces a route, this list must grow with it — otherwise the
    // notification silently redirects to the Notifications screen instead of the
    // screen it names.
    const catalogueRoutes = [
      '/bookings',   // BOOK1-10, REM1-5, BOOK8
      '/messages',   // MSG1
      '/discover',   // WOOF1
      '/community',  // COMM1
      '/payments',   // PAY1-5
      '/profile',    // ACC1, ACC2 — the KYC verdicts
    ];

    test('passes through every route the catalogue can emit', () {
      for (final r in catalogueRoutes) {
        expect(resolveTapRoute(r), r, reason: 'catalogue route $r must survive');
      }
    });

    test('passes through /home and /notifications', () {
      expect(resolveTapRoute(Routes.home), Routes.home);
      expect(resolveTapRoute(Routes.notifications), Routes.notifications);
    });

    test('falls back to Notifications for an unknown route', () {
      // An installed app can be older than the Functions sending to it, so an
      // unrecognised path must land somewhere sane rather than crash.
      expect(resolveTapRoute('/scenario-from-a-newer-server'), Routes.notifications);
      expect(resolveTapRoute('/settings'), Routes.notifications);
    });

    test('falls back for a null or empty route', () {
      expect(resolveTapRoute(null), Routes.notifications);
      expect(resolveTapRoute(''), Routes.notifications);
    });
  });
}
