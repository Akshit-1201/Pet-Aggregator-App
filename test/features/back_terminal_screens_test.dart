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

/// [isUpToIfEmpty] distinguishes the two fields `PgBackScope` exposes:
/// - false → `upTo`, a forced destination (this screen is only ever reached
///   via `go`, so a real pop could never be its own parent — back must never
///   re-enter a finished checkout).
/// - true  → `upToIfEmpty`, a fallback used only when there is nothing to pop
///   (this screen is reached by `push` from a live parent, so a real pop must
///   win and return to it with its state intact).
typedef _Case = ({
  String name,
  Widget screen,
  String target,
  bool isUpToIfEmpty,
});

/// A terminal screen that forgets its target silently regains either the
/// "back walks into a finished checkout" bug (wrong field: upToIfEmpty
/// instead of upTo) or the "chevron and gesture disagree" bug (wrong field:
/// upTo instead of upToIfEmpty, discarding a live parent's state). Nothing
/// else in the suite would catch either.
const _cases = <_Case>[
  (
    name: 'PostLive',
    screen: PostLiveScreen(),
    target: Routes.community,
    isUpToIfEmpty: false,
  ),
  (
    name: 'BookingConfirmed',
    screen: BookingConfirmedScreen(),
    target: Routes.bookings,
    isUpToIfEmpty: false,
  ),
  (
    name: 'HostAccepted',
    screen: HostAcceptedScreen(),
    target: Routes.bookings,
    isUpToIfEmpty: false,
  ),
  (
    name: 'WoofMatch',
    screen: WoofMatchScreen(),
    target: Routes.discover,
    isUpToIfEmpty: true,
  ),
  (
    name: 'Receipt',
    screen: ReceiptScreen(),
    target: Routes.payments,
    isUpToIfEmpty: true,
  ),
  (
    name: 'Thread',
    screen: ThreadScreen(),
    target: Routes.community,
    isUpToIfEmpty: true,
  ),
];

/// A stateful stand-in for a live parent screen (the community feed, the
/// discover deck, the payments list). Its counter lets a test prove a pop
/// returned to the *same* instance rather than `go` rebuilding a fresh one.
class _CounterParent extends StatefulWidget {
  const _CounterParent();
  @override
  State<_CounterParent> createState() => _CounterParentState();
}

class _CounterParentState extends State<_CounterParent> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: GestureDetector(
        onTap: () => setState(() => count++),
        child: Text('PARENT $count'),
      ),
    ),
  );
}

/// Pumps [screen] behind a real `GoRouter` (a single dummy route) rather
/// than a bare `MaterialApp(home: ...)`. `PgBackScope._nativePop` calls
/// `context.canPop()` whenever `upTo` is null — true for every screen on
/// `upToIfEmpty` — and that throws "No GoRouter found in context" without
/// one, even though this test only inspects the widget's declared fields.
Future<void> _pumpCase(WidgetTester t, Widget screen) async {
  final router = GoRouter(
    initialLocation: '/case',
    routes: [GoRoute(path: '/case', builder: (_, _) => screen)],
  );
  await t.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
  );
  await t.pump();
}

void main() {
  for (final c in _cases) {
    testWidgets(
      '${c.name} declares its ${c.isUpToIfEmpty ? "upToIfEmpty" : "upTo"} target',
      (t) async {
        await _pumpCase(t, c.screen);

        final scope = t.widget<PgBackScope>(find.byType(PgBackScope).first);
        if (c.isUpToIfEmpty) {
          expect(
            scope.upToIfEmpty,
            c.target,
            reason: '${c.name} must declare its upToIfEmpty target',
          );
          expect(
            scope.upTo,
            isNull,
            reason:
                '${c.name} is reached by push from a live parent — upTo would force a '
                'go() over a real pop even when that parent is on the stack, discarding its state',
          );
        } else {
          expect(
            scope.upTo,
            c.target,
            reason: '${c.name} must declare its upTo target',
          );
          expect(
            scope.upToIfEmpty,
            isNull,
            reason:
                '${c.name} is only ever reached via go() — a plain upToIfEmpty would let a '
                'future push land back inside the finished checkout on pop',
          );
        }
      },
    );
  }

  // The highest-stakes case end to end: after paying, back must reach My
  // Bookings and never re-enter the checkout that produced it.
  testWidgets(
    'BookingConfirmed back reaches My Bookings, not the payment screen',
    (t) async {
      final router = GoRouter(
        initialLocation: '/pay',
        routes: [
          GoRoute(
            path: '/pay',
            builder: (_, _) => const Scaffold(body: Text('PAYMENT')),
          ),
          GoRoute(
            path: Routes.bookingConfirmed,
            builder: (_, _) => const BookingConfirmedScreen(),
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

      router.push(Routes.bookingConfirmed);
      await t.pumpAndSettle();

      await t.binding.handlePopRoute();
      await t.pumpAndSettle();

      expect(find.text('MY BOOKINGS'), findsOneWidget);
      expect(find.text('PAYMENT'), findsNothing);
    },
  );

  // The other blast-radius case: Thread is reached by `push` from a live
  // community feed. Back must pop to that same live instance — preserving
  // its state — never `go(Routes.community)`, which would rebuild it fresh.
  testWidgets(
    'Thread pushed from a parent pops back to that same parent, state intact',
    (t) async {
      final router = GoRouter(
        initialLocation: Routes.community,
        routes: [
          GoRoute(
            path: Routes.community,
            builder: (_, _) => const _CounterParent(),
          ),
          GoRoute(path: Routes.thread, builder: (_, _) => const ThreadScreen()),
        ],
      );

      await t.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await t.pumpAndSettle();

      // Mutate the parent's state before navigating away from it.
      await t.tap(find.text('PARENT 0'));
      await t.pump();
      expect(find.text('PARENT 1'), findsOneWidget);

      router.push(Routes.thread);
      await t.pumpAndSettle();

      await t.binding.handlePopRoute();
      await t.pumpAndSettle();

      // A real pop lands on the same _CounterParent instance (counter still 1).
      // If back had instead done context.go(Routes.community), the route would
      // have been rebuilt fresh and the counter would have reset to 0.
      expect(find.text('PARENT 1'), findsOneWidget);
      expect(find.text('PARENT 0'), findsNothing);
    },
  );
}
