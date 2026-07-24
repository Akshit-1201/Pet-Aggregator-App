// The token side of push is the part that fails silently: if registration
// doesn't happen, or a rotated token isn't re-saved, notifications simply stop
// arriving with no error anywhere. These pin the lifecycle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
}
