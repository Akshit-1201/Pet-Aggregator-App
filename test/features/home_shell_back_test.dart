import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pet_aggregator_app/core/navigation/exit_confirm.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/widgets/pg_bottom_nav.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/profile/profile_screen.dart';
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

// The Home and Profile branches are both real screens reading live
// repositories (nearbyPetsProvider, currentUserProfileProvider, Profile's
// stats row, etc). pumpPgApp only defaults the cross-cutting ones (block,
// report, verification, payout, posts, notifications); anything a specific
// screen reads has to be supplied here or it falls through to the real
// Firebase-backed provider, which throws with no Firebase test setup and
// sends Riverpod into an endless retry loop that pumpAndSettle never
// settles. This mirrors the override sets already used by
// test/features/home_screen_test.dart and test/features/profile_screen_test.dart.
List<Override> _screenOverrides(FakeAuthRepository auth) => [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ];

void main() {
  setUp(PgExitConfirm.reset);

  testWidgets('back on a non-Home tab returns to Home', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t,
        overrides: _screenOverrides(auth),
        initialLocation: Routes.profile);
    await t.pumpAndSettle();

    await _systemBack(t);
    expect(find.text('Home'), findsWidgets); // the Home tab is selected
    // Discriminating: 'Home' also matches the bottom-nav label on every
    // branch, so it alone would still pass if goBranch() were deleted
    // entirely and back did nothing. Asserting Profile is gone is what
    // actually proves the branch switch happened — this is the regression
    // guard for the bug that motivated the whole slice ("back on Profile
    // exits Pawgo").
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.text('Press back again to exit'), findsNothing);
  });

  testWidgets('first back on Home shows the toast and does not exit', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t,
        overrides: _screenOverrides(auth),
        initialLocation: Routes.home);
    await t.pumpAndSettle();

    await _systemBack(t);
    expect(find.text('Press back again to exit'), findsOneWidget);
  });

  testWidgets('second back on Home inside the window requests an exit', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t,
        overrides: _screenOverrides(auth),
        initialLocation: Routes.home);
    await t.pumpAndSettle();

    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (c) async {
        calls.add(c);
        return null;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _systemBack(t);
    await _systemBack(t);

    expect(calls.any((c) => c.method == 'SystemNavigator.pop'), isTrue);
  });

  // Everything above drives back with `binding.handlePopRoute()`, which calls
  // the framework directly. On a real device the engine only calls that when
  // the framework has told it "I handle back", via
  // SystemNavigator.setFrameworkHandlesBack. When that flag is false, Android
  // finishes the Activity itself and no Dart code runs at all — so every test
  // above can pass while back closes the app on a phone. That is exactly what
  // shipped: back on Home worked, back on any other tab quit Pawgo.
  //
  // Cause: HomeShell's PopScope sits *above* go_router's per-branch
  // Navigators. Each branch Navigator dispatches
  // NavigationNotification(canHandlePop: false) when it has nothing to pop,
  // and the root Navigator forwards a child's notification unchanged whenever
  // its own canPop() is false (navigator.dart, `_NavigatorState.build`) — it
  // never consults its route's popDisposition, which is where HomeShell's
  // PopScope registers. So the false wins and reaches WidgetsApp.
  //
  // These assert on the flag the engine actually receives, which is the only
  // thing that decides whether back reaches Dart at all.
  group('the engine is told the framework handles back', () {
    late List<bool> handlesBack;

    Future<void> pumpShell(WidgetTester t, FakeAuthRepository auth) async {
      handlesBack = <bool>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (c) async {
          if (c.method == 'SystemNavigator.setFrameworkHandlesBack') {
            handlesBack.add(c.arguments as bool);
          }
          return null;
        },
      );
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      // WidgetsApp only forwards the flag once it has seen a lifecycle state
      // (`_defaultOnNavigationNotification` no-ops while it is null), and the
      // test binding never sends one. Without this the list stays empty and
      // the assertions below would pass vacuously.
      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage('AppLifecycleState.resumed'),
        (_) {},
      );

      await pumpPgApp(t,
          overrides: _screenOverrides(auth), initialLocation: Routes.home);
      await t.pumpAndSettle();
    }

    testWidgets('on the Home tab', (t) async {
      await pumpShell(t, await _signedIn());

      expect(handlesBack, isNotEmpty,
          reason: 'the flag was never sent to the engine — this test proves '
              'nothing unless WidgetsApp is actually reporting');
      expect(handlesBack.last, isTrue);
    });

    testWidgets('still, after switching to another tab', (t) async {
      await pumpShell(t, await _signedIn());

      await t.tap(find.descendant(
          of: find.byType(PgBottomNav), matching: find.text('Profile')));
      await t.pumpAndSettle();

      expect(handlesBack, isNotEmpty);
      // The regression guard. Before the fix this is false, and Android closes
      // Pawgo on the next back press or swipe without consulting HomeShell.
      expect(handlesBack.last, isTrue,
          reason: 'back on a non-Home tab will quit the app: the engine was '
              'told the framework does not handle back');
    });
  });
}
