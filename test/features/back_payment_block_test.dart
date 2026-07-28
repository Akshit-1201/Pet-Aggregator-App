// Back is refused while a Razorpay payment is verifying, on both payment
// screens (services + homestay). Backing out mid-verification is how a
// payment succeeds with no booking written: the server owns the paid-write,
// but the user must not be able to leave before it lands. Back must still
// work before checkout starts — a block that always blocks would strand
// someone on the payment screen forever — so every case below tests both
// directions.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

/// Simulates the Android system back button/gesture.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

/// Never resolves. Fires `onVerifying` synchronously — the same point the
/// real `RazorpayPaymentService` fires it, right before its network verify
/// call — then hangs instead of returning, holding the screen in
/// `_PayPhase.verifying` for the life of the test. `FakePaymentService`'s own
/// `gate` can't be reused for this: it returns *before* calling `onVerifying`,
/// which models the `opening` wait, not `verifying` (see
/// `payment_flow_test.dart`'s "button is disabled while a payment is in
/// flight", which depends on that ordering to see "Opening…" — reordering it
/// there to fire onVerifying first would flip that test to "Verifying…" and
/// break it instead).
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

Future<FakeAuthRepository> _signedIn() async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  return auth;
}

/// Both payment screens are reached by `push` from a live parent in
/// production (booking_screen, my_bookings_screen) — never landed on cold —
/// and neither declares `upTo`/`upToIfEmpty`, so a clean "back before
/// checkout" pop depends entirely on `context.canPop()` being true. Landing
/// directly on the route via `initialLocation` would bake canPop() == false
/// in forever, so land on Home first (a real entry already in the stack) and
/// push the payment screen on top of it — same fix `back_guarded_forms_test`
/// already applies for its screens.
Future<void> _pushOverHome(
  WidgetTester t, {
  required List<Override> overrides,
  required String route,
  required Object extra,
}) async {
  await pumpPgApp(t, overrides: overrides, initialLocation: Routes.home);
  await t.pumpAndSettle();
  final ctx = t.element(find.text('Home').first);
  GoRouter.of(ctx).push(route, extra: extra);
  await t.pumpAndSettle();
}

/// The repositories Home itself reads. Home stays mounted (just off the top
/// of the stack) underneath the pushed payment screen, so it still needs
/// these to build without throwing.
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

const _booking = Booking(
    id: 'b1', parentId: 'uid_me@x.com', proId: 'pro1', proName: 'Aarav Sharma',
    petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25,
    total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', date: '2027-01-10');

final _stay = HomestayBooking(
    id: 'hb1', guestId: 'uid_me@x.com', hostId: 'host1', homeName: "Meera's Home",
    hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
    checkIn: DateTime.now().add(const Duration(days: 5)),
    checkOut: DateTime.now().add(const Duration(days: 8)),
    nights: 3, subtotal: 2700, fee: 150, total: 2850, status: 'accepted');

void main() {
  group('services payment screen', () {
    testWidgets('back before checkout starts leaves the screen', (t) async {
      final auth = await _signedIn();
      await _pushOverHome(t,
          overrides: [
            ..._homeOverrides(auth),
            paymentServiceProvider.overrideWithValue(FakePaymentService.success()),
          ],
          route: Routes.payment,
          extra: _booking);
      expect(find.text('Pay ₹275'), findsOneWidget);

      await _systemBack(t);

      expect(find.text('Payment'), findsNothing); // left the screen
      expect(find.text('Pay ₹275'), findsNothing);
    });

    testWidgets('back while verifying is refused, screen stays, message shown', (t) async {
      final auth = await _signedIn();
      await _pushOverHome(t,
          overrides: [
            ..._homeOverrides(auth),
            paymentServiceProvider.overrideWithValue(_StuckVerifyingPaymentService()),
          ],
          route: Routes.payment,
          extra: _booking);

      await t.tap(find.text('Pay ₹275'));
      await t.pump();
      expect(find.text('Verifying…'), findsOneWidget);

      await _systemBack(t);

      expect(find.text('Payment'), findsOneWidget); // still here
      expect(find.text('Verifying…'), findsOneWidget); // still verifying
      expect(find.text('Payment in progress — please wait.'), findsOneWidget);
    });
  });

  group('homestay payment screen', () {
    testWidgets('back before checkout starts leaves the screen', (t) async {
      final auth = await _signedIn();
      await _pushOverHome(t,
          overrides: [
            ..._homeOverrides(auth),
            paymentServiceProvider.overrideWithValue(FakePaymentService.success()),
          ],
          route: Routes.homestayPayment,
          extra: _stay);
      expect(find.text('Pay ₹2850'), findsOneWidget);

      await _systemBack(t);

      expect(find.text('Payment'), findsNothing); // left the screen
      expect(find.text('Pay ₹2850'), findsNothing);
    });

    testWidgets('back while verifying is refused, screen stays, message shown', (t) async {
      final auth = await _signedIn();
      await _pushOverHome(t,
          overrides: [
            ..._homeOverrides(auth),
            paymentServiceProvider.overrideWithValue(_StuckVerifyingPaymentService()),
          ],
          route: Routes.homestayPayment,
          extra: _stay);

      await t.tap(find.text('Pay ₹2850'));
      await t.pump();
      expect(find.text('Verifying…'), findsOneWidget);

      await _systemBack(t);

      expect(find.text('Payment'), findsOneWidget); // still here
      expect(find.text('Verifying…'), findsOneWidget); // still verifying
      expect(find.text('Payment in progress — please wait.'), findsOneWidget);
    });
  });
}
