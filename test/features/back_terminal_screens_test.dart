import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pet_aggregator_app/core/navigation/pg_back_scope.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/features/community/post_live_screen.dart';
import 'package:pet_aggregator_app/features/community/thread_screen.dart';
import 'package:pet_aggregator_app/features/discovery/woof_match_screen.dart';
import 'package:pet_aggregator_app/features/homestay/host_accepted_screen.dart';
import 'package:pet_aggregator_app/features/payments/receipt_screen.dart';
import 'package:pet_aggregator_app/features/services/booking_confirmed_screen.dart';

typedef _Case = ({String name, Widget screen, String upTo});

/// A terminal screen that forgets its `upTo` silently regains the "back walks
/// into a finished checkout" bug. Nothing else in the suite would catch it.
const _cases = <_Case>[
  (name: 'PostLive',         screen: PostLiveScreen(),         upTo: Routes.community),
  (name: 'BookingConfirmed', screen: BookingConfirmedScreen(), upTo: Routes.bookings),
  (name: 'HostAccepted',     screen: HostAcceptedScreen(),     upTo: Routes.bookings),
  (name: 'WoofMatch',        screen: WoofMatchScreen(),        upTo: Routes.discover),
  (name: 'Receipt',          screen: ReceiptScreen(),          upTo: Routes.payments),
  (name: 'Thread',           screen: ThreadScreen(),           upTo: Routes.community),
];

void main() {
  for (final c in _cases) {
    testWidgets('${c.name} declares upTo ${c.upTo}', (t) async {
      await t.pumpWidget(ProviderScope(
        child: MaterialApp(home: c.screen),
      ));
      await t.pump();

      final scope = t.widget<PgBackScope>(find.byType(PgBackScope).first);
      expect(scope.upTo, c.upTo, reason: '${c.name} must declare its up target');
    });
  }

  // The highest-stakes case end to end: after paying, back must reach My
  // Bookings and never re-enter the checkout that produced it.
  testWidgets('BookingConfirmed back reaches My Bookings, not the payment screen',
      (t) async {
    final router = GoRouter(initialLocation: '/pay', routes: [
      GoRoute(path: '/pay', builder: (_, _) => const Scaffold(body: Text('PAYMENT'))),
      GoRoute(
          path: Routes.bookingConfirmed,
          builder: (_, _) => const BookingConfirmedScreen()),
      GoRoute(path: Routes.bookings, builder: (_, _) => const Scaffold(body: Text('MY BOOKINGS'))),
    ]);

    await t.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await t.pumpAndSettle();

    router.push(Routes.bookingConfirmed);
    await t.pumpAndSettle();

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    expect(find.text('MY BOOKINGS'), findsOneWidget);
    expect(find.text('PAYMENT'), findsNothing);
  });
}
