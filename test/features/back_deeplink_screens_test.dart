// Four screens (`MyBookings`, `ChatList`, `Payments`, `Notifications`) are
// cold-start deep-link targets (`resolveTapRoute` allowlists `/bookings`,
// `/messages`, `/payments`, `/notifications`) AND `notifications_screen.dart`
// does `context.go(item.route)` in-session for the same set — so all four
// can be the bottom of the stack with nothing to pop to. Before this fix
// wave, none of them wrapped their `PgBackScope.pop(context)` call in a
// `PgBackScope`, so with no scope in the tree the static fell through to
// `if (context.canPop()) context.pop();` — a silent no-op — and hardware
// back bubbled out of the root Navigator and closed Pawgo.
//
// Each case below lands directly on the screen (no stack beneath it, same
// as `pumpPgApp`'s ordinary `initialLocation` — nothing is pushed on top),
// fires system back, and asserts it lands on Home rather than exiting. Each
// must fail if the screen's `PgBackScope(upToIfEmpty: Routes.home, ...)`
// wrapper is removed.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pet_aggregator_app/core/navigation/exit_confirm.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/home/home_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _systemBack(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

Future<FakeAuthRepository> _signedIn() async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  return auth;
}

/// Covers what each of the four screens reads, plus what Home (the expected
/// landing point) reads — mirrors `home_shell_back_test.dart`'s
/// `_screenOverrides`, since a wrong or missing `upToIfEmpty` would otherwise
/// still resolve here rather than exiting, but Home itself has to build
/// without throwing for the assertion to mean anything.
List<Override> _overrides(FakeAuthRepository auth) => [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider
          .overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ];

void main() {
  setUp(PgExitConfirm.reset);

  testWidgets('My Bookings with no stack: back lands on Home, not exit', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t, overrides: _overrides(auth), initialLocation: Routes.bookings);
    await t.pumpAndSettle();

    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() =>
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _systemBack(t);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(calls.any((c) => c.method == 'SystemNavigator.pop'), isFalse);
  });

  testWidgets('Messages with no stack: back lands on Home, not exit', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t, overrides: _overrides(auth), initialLocation: Routes.chatList);
    await t.pumpAndSettle();

    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() =>
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _systemBack(t);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(calls.any((c) => c.method == 'SystemNavigator.pop'), isFalse);
  });

  testWidgets('Payments with no stack: back lands on Home, not exit', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t, overrides: _overrides(auth), initialLocation: Routes.payments);
    await t.pumpAndSettle();

    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() =>
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _systemBack(t);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(calls.any((c) => c.method == 'SystemNavigator.pop'), isFalse);
  });

  testWidgets('Notifications with no stack: back lands on Home, not exit', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t, overrides: _overrides(auth), initialLocation: Routes.notifications);
    await t.pumpAndSettle();

    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() =>
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _systemBack(t);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(calls.any((c) => c.method == 'SystemNavigator.pop'), isFalse);
  });
}
