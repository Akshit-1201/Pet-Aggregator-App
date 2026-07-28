// Task 10 — on-screen affordances consolidated onto the shared resolver.
//
// Tasks 2-9 gave every screen a declared back behaviour, but only the
// hardware/gesture back honoured it: on-screen chevrons still called
// `context.pop()`/`context.go(...)` directly. This file pins the invariant
// the whole slice rests on — a chevron tap and the hardware/gesture back must
// always land in the same place — plus the two live safety gaps that were
// explicitly carried forward into this task:
//   1. Both payment screens' chevrons must honour the "verifying" block
//      (task 8 blocked hardware back but left the chevron calling
//      context.pop() directly).
//   2. The nearby-map screen's internal chevron must return to whichever
//      screen actually pushed it (Discover or Home), not an unconditional
//      go(Routes.discover).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/widgets/pg_app_bar.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import 'package:pet_aggregator_app/features/discovery/nearby_map_screen.dart';
import 'package:pet_aggregator_app/features/payments/receipt_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

/// Simulates the Android system back button/gesture.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the chevron and hardware back land in the same place', (t) async {
    // ReceiptScreen declares `upToIfEmpty: Routes.payments` (see
    // back_terminal_screens_test.dart). Land on it cold — no parent to pop —
    // so both paths are forced through that *declared* destination rather
    // than an ordinary pop, which would pass even if the chevron and gesture
    // disagreed about the fallback. This is the exact shape of bug the
    // Builder-context fix in this task closes: a chevron wired to the wrong
    // BuildContext silently falls back to a no-op plain pop instead of
    // reaching upToIfEmpty.
    Future<void> land(WidgetTester t) async {
      final router = GoRouter(initialLocation: Routes.receipt, routes: [
        GoRoute(path: Routes.receipt, builder: (_, _) => const ReceiptScreen()),
        GoRoute(path: Routes.payments,
            builder: (_, _) => const Scaffold(body: Text('PAYMENTS LIST'))),
      ]);
      await t.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
      await t.pumpAndSettle();
    }

    // Path 1: tap the chevron.
    await land(t);
    expect(find.text('Receipt'), findsOneWidget);
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pumpAndSettle();
    final afterChevron = find.text('PAYMENTS LIST').evaluate().isNotEmpty;

    // Path 2: fire system back on a fresh instance.
    await land(t);
    await _systemBack(t);
    final afterGesture = find.text('PAYMENTS LIST').evaluate().isNotEmpty;

    expect(afterChevron, isTrue,
        reason: 'the chevron must reach the declared upToIfEmpty target');
    expect(afterGesture, isTrue,
        reason: 'hardware back must reach the same declared target');
    expect(afterChevron, afterGesture,
        reason: 'a chevron that fell back to a no-op plain pop while the '
            'gesture reached Payments would fail here even though each '
            'assertion above passed in isolation');
  });

  testWidgets('signup has a visible back affordance', (t) async {
    await pumpPgApp(t, overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.signup);
    await t.pumpAndSettle();

    final bar = t.widget<PgAppBar>(find.byType(PgAppBar));
    expect(bar.onBack, isNotNull);

    // Behavioural, not just cosmetic: signup declares upTo: Routes.welcome,
    // a deterministic target regardless of what (if anything) is on the
    // stack, so the tap can be followed all the way to its destination.
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pumpAndSettle();
    expect(find.text('Welcome back 👋'), findsOneWidget);
  });

  testWidgets('pro-setup has a visible back affordance', (t) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Me',
        email: 'me@x.com', area: 'Khar', role: Role.servicePro));

    await pumpPgApp(t, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    ], initialLocation: Routes.proSetup);
    await t.pumpAndSettle();

    final bar = t.widget<PgAppBar>(find.byType(PgAppBar));
    expect(bar.onBack, isNotNull);
  });

  group('safety gap 1 — payment chevron honours the verifying block', () {
    // Never resolves. Fires `onVerifying` synchronously, then hangs — puts
    // the screen in the real `_PayPhase.verifying` for the life of the test,
    // same fixture shape as back_payment_block_test.dart's own (redefined
    // here since that file's helpers are private to it).
    Future<FakeAuthRepository> signedIn() async {
      final auth = FakeAuthRepository();
      await auth.signUp(email: 'me@x.com', password: 'secret1');
      return auth;
    }

    List<Override> homeOverrides(FakeAuthRepository auth) => [
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

    // Both payment screens are reached by push from a live parent in
    // production and declare no upTo/upToIfEmpty, so landing cold via
    // initialLocation would bake canPop() == false in forever — push over a
    // real Home instead, mirroring back_payment_block_test.dart.
    Future<void> pushOverHome(WidgetTester t,
        {required List<Override> overrides,
        required String route,
        required Object extra}) async {
      await pumpPgApp(t, overrides: overrides, initialLocation: Routes.home);
      await t.pumpAndSettle();
      final ctx = t.element(find.text('Home').first);
      GoRouter.of(ctx).push(route, extra: extra);
      await t.pumpAndSettle();
    }

    const booking = Booking(
        id: 'b1', parentId: 'uid_me@x.com', proId: 'pro1', proName: 'Aarav Sharma',
        petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250,
        fee: 25, total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM',
        date: '2027-01-10');

    testWidgets('services payment chevron is refused while verifying', (t) async {
      final auth = await signedIn();
      await pushOverHome(t,
          overrides: [
            ...homeOverrides(auth),
            paymentServiceProvider.overrideWithValue(_StuckVerifyingPaymentService()),
          ],
          route: Routes.payment,
          extra: booking);

      await t.tap(find.text('Pay ₹275'));
      await t.pump();
      expect(find.text('Verifying…'), findsOneWidget);

      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();

      expect(find.text('Payment'), findsOneWidget); // still here
      expect(find.text('Verifying…'), findsOneWidget); // still verifying
      expect(find.text('Payment in progress — please wait.'), findsOneWidget);
    });

    testWidgets('homestay payment chevron is refused while verifying', (t) async {
      final auth = await signedIn();
      final stay = HomestayBooking(
          id: 'hb1', guestId: 'uid_me@x.com', hostId: 'host1', homeName: "Meera's Home",
          hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
          checkIn: DateTime.now().add(const Duration(days: 5)),
          checkOut: DateTime.now().add(const Duration(days: 8)),
          nights: 3, subtotal: 2700, fee: 150, total: 2850, status: 'accepted');
      await pushOverHome(t,
          overrides: [
            ...homeOverrides(auth),
            paymentServiceProvider.overrideWithValue(_StuckVerifyingPaymentService()),
          ],
          route: Routes.homestayPayment,
          extra: stay);

      await t.tap(find.text('Pay ₹2850'));
      await t.pump();
      expect(find.text('Verifying…'), findsOneWidget);

      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();

      expect(find.text('Payment'), findsOneWidget); // still here
      expect(find.text('Verifying…'), findsOneWidget); // still verifying
      expect(find.text('Payment in progress — please wait.'), findsOneWidget);
    });
  });

  group('safety gap 2 — nearby-map chevron follows its actual parent', () {
    testWidgets('opened from Discover, the chevron returns to Discover', (t) async {
      final auth = FakeAuthRepository();
      await auth.signUp(email: 'me@x.com', password: 'secret1');
      await pumpPgApp(t, overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
        petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('owner-b'))),
        swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
        // GoogleMap is a platform view that cannot render under flutter_test.
        mapViewBuilderProvider.overrideWithValue((cam, markers) => const SizedBox.expand()),
        proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
        homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
      ], initialLocation: Routes.discover);
      await t.pumpAndSettle();

      expect(find.text('Pets near you'), findsOneWidget);
      await t.tap(find.textContaining('Map view'));
      await t.pumpAndSettle();
      expect(find.textContaining('pets nearby'), findsOneWidget); // the map's sheet

      await t.tap(find.byIcon(Icons.chevron_left).first);
      await t.pumpAndSettle();

      expect(find.text('Pets near you'), findsOneWidget);
      expect(find.textContaining('pets nearby'), findsNothing);
    });

    testWidgets('opened from Home, the chevron returns to Home, not Discover', (t) async {
      final auth = FakeAuthRepository();
      await auth.signUp(email: 'me@x.com', password: 'secret1');
      final users = InMemoryUserRepository();
      await users.createUser(UserProfile(
          uid: auth.currentUser!.uid, name: 'Radhika Nair', email: 'me@x.com',
          area: 'Bandra West', role: Role.petParent));

      await pumpPgApp(t, overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        userRepositoryProvider.overrideWithValue(users),
        petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('someone-else'))),
        chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
        reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
        bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
        homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
        proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
        homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
        // GoogleMap is a platform view that cannot render under flutter_test.
        mapViewBuilderProvider.overrideWithValue((cam, markers) => const SizedBox.expand()),
      ], initialLocation: Routes.home);
      await t.pumpAndSettle();

      expect(find.text('Hey Radhika 👋'), findsOneWidget);
      await t.tap(find.text('See map →'));
      await t.pumpAndSettle();
      expect(find.textContaining('pets nearby'), findsOneWidget); // the map's sheet

      // Before this task, this chevron unconditionally called
      // context.go(Routes.discover) — from Home it would have landed on
      // Discover instead, a different screen than the one that pushed it.
      await t.tap(find.byIcon(Icons.chevron_left).first);
      await t.pumpAndSettle();

      expect(find.text('Hey Radhika 👋'), findsOneWidget);
      expect(find.textContaining('pets nearby'), findsNothing);
    });
  });
}

/// Never resolves. Fires `onVerifying` synchronously — the same point the
/// real `RazorpayPaymentService` fires it — then hangs instead of returning,
/// holding the screen in `_PayPhase.verifying` for the life of the test.
class _StuckVerifyingPaymentService implements PaymentService {
  @override
  Future<PaymentResult> payForBooking({
    required String bookingId,
    required PaymentKind kind,
    required String description,
    void Function()? onVerifying,
  }) {
    onVerifying?.call();
    return Completer<PaymentResult>().future;
  }

  @override
  Future<RefundResult> refundBooking({
    required String bookingId,
    required PaymentKind kind,
  }) async =>
      const RefundResult(refundAmount: 0, refundId: '');
}
