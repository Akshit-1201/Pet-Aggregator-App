// Slice 23 — every screen gains a visible on-screen back chevron, on top of
// the Slice 22 PgBackScope resolver that already governs hardware/gesture
// back. These pin two things per screen: the chevron is actually there, and
// tapping it lands in the *same* place hardware/gesture back does — the
// invariant this whole area rests on. Several of these use a bare
// GoRouter/ProviderScope rather than the full app (pumpPgApp) because the
// screen under test never calls `ref` during build, mirroring the pattern
// already established in back_affordance_parity_test.dart and
// back_terminal_screens_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pet_aggregator_app/core/navigation/exit_confirm.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/auth/location_screen.dart';
import 'package:pet_aggregator_app/features/auth/welcome_screen.dart';
import 'package:pet_aggregator_app/features/community/community_feed_screen.dart';
import 'package:pet_aggregator_app/features/community/post_live_screen.dart';
import 'package:pet_aggregator_app/features/discovery/discover_screen.dart';
import 'package:pet_aggregator_app/features/home/home_screen.dart';
import 'package:pet_aggregator_app/features/homestay/host_accepted_screen.dart';
import 'package:pet_aggregator_app/features/onboarding/onboarding_screen.dart';
import 'package:pet_aggregator_app/features/profile/profile_screen.dart';
import 'package:pet_aggregator_app/features/services/booking_confirmed_screen.dart';
import 'package:pet_aggregator_app/features/services/services_list_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

/// Simulates the Android system back button/gesture.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

/// The cross-cutting overrides Home/Discover/Services/Community/Profile all
/// pull in transitively (nearby pets, chat, reviews, bookings…) — identical
/// to home_shell_back_test.dart's own `_screenOverrides`, since a tab-root
/// chevron test always ends up rendering Home too.
Future<FakeAuthRepository> _signedIn() async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  return auth;
}

List<Override> _fullOverrides(FakeAuthRepository auth) => [
  authRepositoryProvider.overrideWithValue(auth),
  userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
  petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
  swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
  chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
  reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
  bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
  homestayBookingRepositoryProvider.overrideWithValue(
    InMemoryHomestayBookingRepository(),
  ),
  proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
  homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
];

void main() {
  setUp(PgExitConfirm.reset);

  group('onboarding chevron', () {
    Future<void> pumpOnboarding(WidgetTester t) async {
      // The default 800x600 test surface is too short for onboarding's fixed
      // 460px hero + content below it — same phone-sized surface pumpPg/
      // pumpPgApp use (see test/support/pump.dart).
      t.view.physicalSize = const Size(420, 920);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final router = GoRouter(
        initialLocation: Routes.onboarding,
        routes: [
          GoRoute(
            path: Routes.onboarding,
            builder: (_, _) => const OnboardingScreen(),
          ),
          GoRoute(
            path: Routes.welcome,
            builder: (_, _) => const Scaffold(body: Text('WELCOME')),
          ),
        ],
      );
      await t.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await t.pumpAndSettle();
    }

    testWidgets('slide 1: shows the exit confirmation, does not navigate', (
      t,
    ) async {
      await pumpOnboarding(t);

      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();

      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(
        find.text('Find playmates just around the corner'),
        findsOneWidget,
      );
    });

    // The critical case: PgBackScope's blockWhen steps the PageController
    // back on any page but the first. A chevron wired to a plain pop instead
    // of PgBackScope.pop would do nothing here (no stack to pop) — the two
    // paths must land on the same page.
    testWidgets(
      'slide 3: chevron and hardware back both step back exactly one page',
      (t) async {
        Future<void> toSlide3(WidgetTester t) async {
          await pumpOnboarding(t);
          await t.tap(find.text('Next'));
          await t.pumpAndSettle();
          await t.tap(find.text('Next'));
          await t.pumpAndSettle();
          expect(find.text('Homestays with verified hosts'), findsOneWidget);
        }

        await toSlide3(t);
        await t.tap(find.byIcon(Icons.chevron_left));
        await t.pumpAndSettle();
        final afterChevron = find
            .text('Trusted walkers, sitters & groomers')
            .evaluate()
            .isNotEmpty;
        expect(find.text('Press back again to exit'), findsNothing);

        await toSlide3(t);
        await _systemBack(t);
        final afterGesture = find
            .text('Trusted walkers, sitters & groomers')
            .evaluate()
            .isNotEmpty;
        expect(find.text('Press back again to exit'), findsNothing);

        expect(afterChevron, isTrue);
        expect(afterGesture, isTrue);
        expect(
          afterChevron,
          afterGesture,
          reason:
              'a chevron that fell back to a no-op pop would fail here even '
              'though hardware back (already covered elsewhere) still worked',
        );
      },
    );
  });

  group('welcome chevron', () {
    Future<void> pumpWelcome(WidgetTester t) async {
      final router = GoRouter(
        initialLocation: Routes.welcome,
        routes: [
          GoRoute(
            path: Routes.welcome,
            builder: (_, _) => const WelcomeScreen(),
          ),
        ],
      );
      await t.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await t.pumpAndSettle();
    }

    // Welcome is the auth root — nowhere up. Both paths must show the
    // confirm-exit toast on a first press and leave the screen exactly where
    // it was, never a silent pop or an immediate exit.
    testWidgets('chevron and hardware back both show the exit confirmation', (
      t,
    ) async {
      await pumpWelcome(t);
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(find.text('Welcome back 👋'), findsOneWidget);

      // Reset the shared window before the second path — otherwise this tap
      // reads as the *second* press of the pair and would wrongly exit.
      PgExitConfirm.reset();

      await pumpWelcome(t);
      await _systemBack(t);
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(find.text('Welcome back 👋'), findsOneWidget);
    });
  });

  group('location chevron', () {
    Future<void> pumpLocation(WidgetTester t) async {
      final router = GoRouter(
        initialLocation: Routes.location,
        routes: [
          GoRoute(
            path: Routes.location,
            builder: (_, _) => const LocationScreen(),
          ),
        ],
      );
      await t.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await t.pumpAndSettle();
    }

    // Location has nowhere sound to go up to (see location_screen.dart) —
    // same confirmed-exit treatment as Welcome, on both paths.
    testWidgets('chevron and hardware back both show the exit confirmation', (
      t,
    ) async {
      await pumpLocation(t);
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(find.text('Choose your area'), findsOneWidget);

      PgExitConfirm.reset();

      await pumpLocation(t);
      await _systemBack(t);
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(find.text('Choose your area'), findsOneWidget);
    });
  });

  group('terminal screens: chevron reaches the declared upTo target', () {
    // Same shape as back_affordance_parity_test.dart's Receipt case: land
    // cold (no parent to pop) so both paths are forced through the
    // *declared* upTo rather than an ordinary pop, which would pass even if
    // the chevron silently fell back to a no-op.
    testWidgets('PostLive: chevron and hardware back both reach Community', (
      t,
    ) async {
      const post = Post(
        id: 'p1',
        authorId: 'u1',
        authorName: 'Radhika',
        category: PostCategory.health,
        title: 'Vet in Bandra?',
        body: 'x',
        createdAt: 1000,
      );
      Future<void> land(WidgetTester t) async {
        final router = GoRouter(
          initialLocation: Routes.postLive,
          routes: [
            GoRoute(
              path: Routes.postLive,
              builder: (_, _) => const PostLiveScreen(post: post),
            ),
            GoRoute(
              path: Routes.community,
              builder: (_, _) => const Scaffold(body: Text('COMMUNITY FEED')),
            ),
          ],
        );
        await t.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: router)),
        );
        await t.pumpAndSettle();
      }

      await land(t);
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      final afterChevron = find.text('COMMUNITY FEED').evaluate().isNotEmpty;

      await land(t);
      await _systemBack(t);
      final afterGesture = find.text('COMMUNITY FEED').evaluate().isNotEmpty;

      expect(afterChevron, isTrue);
      expect(afterGesture, isTrue);
      expect(afterChevron, afterGesture);
    });

    testWidgets(
      'BookingConfirmed: chevron and hardware back both reach My Bookings',
      (t) async {
        const booking = Booking(
          id: 'b1',
          parentId: 'u1',
          proId: 'pro1',
          proName: 'Aarav Sharma',
          petId: 'p1',
          petName: 'Bruno',
          serviceType: ServiceType.walker,
          rate: 250,
          fee: 25,
          total: 275,
          dateLabel: 'Tue 15 Jul',
          timeSlot: '5:00 PM',
        );
        Future<void> land(WidgetTester t) async {
          final router = GoRouter(
            initialLocation: Routes.bookingConfirmed,
            routes: [
              GoRoute(
                path: Routes.bookingConfirmed,
                builder: (_, _) =>
                    const BookingConfirmedScreen(booking: booking),
              ),
              GoRoute(
                path: Routes.bookings,
                builder: (_, _) => const Scaffold(body: Text('MY BOOKINGS')),
              ),
            ],
          );
          await t.pumpWidget(
            ProviderScope(child: MaterialApp.router(routerConfig: router)),
          );
          await t.pumpAndSettle();
        }

        await land(t);
        await t.tap(find.byIcon(Icons.chevron_left));
        await t.pumpAndSettle();
        final afterChevron = find.text('MY BOOKINGS').evaluate().isNotEmpty;

        await land(t);
        await _systemBack(t);
        final afterGesture = find.text('MY BOOKINGS').evaluate().isNotEmpty;

        expect(afterChevron, isTrue);
        expect(afterGesture, isTrue);
        expect(afterChevron, afterGesture);
      },
    );

    testWidgets(
      'HostAccepted: chevron and hardware back both reach My Bookings',
      (t) async {
        final booking = HomestayBooking(
          id: 'hb1',
          guestId: 'u1',
          hostId: 'h1',
          homeName: "Meera's Home",
          hostName: 'Meera Iyer',
          petId: 'p1',
          petName: 'Bruno',
          ratePerNight: 900,
          checkIn: DateTime(2027, 1, 12),
          checkOut: DateTime(2027, 1, 15),
          nights: 3,
          subtotal: 2700,
          fee: 150,
          total: 2850,
        );
        Future<void> land(WidgetTester t) async {
          final router = GoRouter(
            initialLocation: Routes.hostAccepted,
            routes: [
              GoRoute(
                path: Routes.hostAccepted,
                builder: (_, _) => HostAcceptedScreen(booking: booking),
              ),
              GoRoute(
                path: Routes.bookings,
                builder: (_, _) => const Scaffold(body: Text('MY BOOKINGS')),
              ),
            ],
          );
          await t.pumpWidget(
            ProviderScope(child: MaterialApp.router(routerConfig: router)),
          );
          await t.pumpAndSettle();
        }

        await land(t);
        await t.tap(find.byIcon(Icons.chevron_left));
        await t.pumpAndSettle();
        final afterChevron = find.text('MY BOOKINGS').evaluate().isNotEmpty;

        await land(t);
        await _systemBack(t);
        final afterGesture = find.text('MY BOOKINGS').evaluate().isNotEmpty;

        expect(afterChevron, isTrue);
        expect(afterGesture, isTrue);
        expect(afterChevron, afterGesture);
      },
    );
  });

  group('Home chevron shares the exit-confirm window with hardware back', () {
    testWidgets('first tap shows the toast and does not exit', (t) async {
      final auth = await _signedIn();
      await pumpPgApp(
        t,
        overrides: _fullOverrides(auth),
        initialLocation: Routes.home,
      );
      await t.pumpAndSettle();

      await t.tap(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byIcon(Icons.chevron_left),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Press back again to exit'), findsOneWidget);
    });

    // The defect this whole slice exists to prevent: if the chevron ran its
    // own PgExitConfirm-alike instead of calling the shared
    // HomeShell.confirmExit, a hardware press followed by a chevron tap
    // would show the toast twice instead of completing the exit on the
    // second press.
    testWidgets('hardware back once, then the chevron completes the exit', (
      t,
    ) async {
      final auth = await _signedIn();
      await pumpPgApp(
        t,
        overrides: _fullOverrides(auth),
        initialLocation: Routes.home,
      );
      await t.pumpAndSettle();

      final calls = <MethodCall>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (c) async {
          calls.add(c);
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _systemBack(t);
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(calls, isEmpty);

      await t.tap(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byIcon(Icons.chevron_left),
        ),
      );
      await t.pumpAndSettle();

      expect(
        calls.any((c) => c.method == 'SystemNavigator.pop'),
        isTrue,
        reason:
            'the chevron must share PgExitConfirm\'s window with hardware '
            'back, not run an independent timer',
      );
    });
  });

  group('tab-root chevrons switch to Home — HomeShell owns their back', () {
    testWidgets('Discover', (t) async {
      final auth = await _signedIn();
      await pumpPgApp(
        t,
        overrides: _fullOverrides(auth),
        initialLocation: Routes.discover,
      );
      await t.pumpAndSettle();
      expect(find.byType(DiscoverScreen), findsOneWidget);

      await t.tap(
        find.descendant(
          of: find.byType(DiscoverScreen),
          matching: find.byIcon(Icons.chevron_left),
        ),
      );
      await t.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(DiscoverScreen), findsNothing);
    });

    testWidgets('Services', (t) async {
      final auth = await _signedIn();
      await pumpPgApp(
        t,
        overrides: _fullOverrides(auth),
        initialLocation: Routes.services,
      );
      await t.pumpAndSettle();
      expect(find.byType(ServicesListScreen), findsOneWidget);

      await t.tap(
        find.descendant(
          of: find.byType(ServicesListScreen),
          matching: find.byIcon(Icons.chevron_left),
        ),
      );
      await t.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ServicesListScreen), findsNothing);
    });

    testWidgets('Community', (t) async {
      final auth = await _signedIn();
      await pumpPgApp(
        t,
        overrides: _fullOverrides(auth),
        initialLocation: Routes.community,
      );
      await t.pumpAndSettle();
      expect(find.byType(CommunityFeedScreen), findsOneWidget);

      await t.tap(
        find.descendant(
          of: find.byType(CommunityFeedScreen),
          matching: find.byIcon(Icons.chevron_left),
        ),
      );
      await t.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(CommunityFeedScreen), findsNothing);
    });

    testWidgets('Profile', (t) async {
      final auth = await _signedIn();
      await pumpPgApp(
        t,
        overrides: _fullOverrides(auth),
        initialLocation: Routes.profile,
      );
      await t.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);

      await t.tap(
        find.descendant(
          of: find.byType(ProfileScreen),
          matching: find.byIcon(Icons.chevron_left),
        ),
      );
      await t.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
    });

    // The chevron (StatefulNavigationShell.maybeOf(context)?.goBranch) and
    // hardware back (HomeShell._onBack's navigationShell.goBranch) are two
    // separate call sites, unlike PgBackScope's single shared resolver — so
    // unlike the other parity tests in this file, this one is not
    // automatically guaranteed by construction and earns its own check.
    testWidgets('chevron and hardware back land in the same place (Discover)', (
      t,
    ) async {
      Future<void> land(WidgetTester t) async {
        final auth = await _signedIn();
        await pumpPgApp(
          t,
          overrides: _fullOverrides(auth),
          initialLocation: Routes.discover,
        );
        await t.pumpAndSettle();
      }

      await land(t);
      await t.tap(
        find.descendant(
          of: find.byType(DiscoverScreen),
          matching: find.byIcon(Icons.chevron_left),
        ),
      );
      await t.pumpAndSettle();
      final afterChevron = find.byType(HomeScreen).evaluate().isNotEmpty;

      await land(t);
      await _systemBack(t);
      final afterGesture = find.byType(HomeScreen).evaluate().isNotEmpty;

      expect(afterChevron, isTrue);
      expect(afterGesture, isTrue);
      expect(afterChevron, afterGesture);
    });
  });
}
