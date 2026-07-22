// test/features/payment_flow_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _draft = Booking(parentId: 'uid_me@x.com', proId: 'pro1', proName: 'Aarav Sharma',
    petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25,
    total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', date: '2027-01-10');

Future<(InMemoryBookingRepository, FakePaymentService, Booking)> _pump(WidgetTester tester,
    {FakePaymentService? payments, InMemoryBookingRepository? bookings}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final b = bookings ?? InMemoryBookingRepository();
  final created = await b.createBooking(_draft); // pre-existing pending booking, as the real flow now requires
  final p = payments ?? FakePaymentService.success();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    bookingRepositoryProvider.overrideWithValue(b),
    paymentServiceProvider.overrideWithValue(p),
  ], initialLocation: Routes.payment, extra: created);
  await tester.pumpAndSettle();
  return (b, p, created);
}

void main() {
  testWidgets('the fake theater is gone; the honest summary is shown', (tester) async {
    await _pump(tester);
    expect(find.text('PAWGO PAY'), findsNothing);
    expect(find.textContaining('4421'), findsNothing);
    expect(find.textContaining('Pawgo Wallet'), findsNothing);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('🔒 Secured by Razorpay — UPI, cards & netbanking'), findsOneWidget);
  });

  testWidgets('success: pays for the created booking by id and kind, navigates',
      (tester) async {
    final (_, payments, created) = await _pump(tester);
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(payments.paidBookingIds, [created.id]);
    expect(payments.paidKinds, [PaymentKind.service]);
    expect(find.text('Booking confirmed! 🎉'), findsOneWidget);
  });

  testWidgets('cancelled: honest snackbar, button idle again, no navigation', (tester) async {
    await _pump(tester,
        payments: FakePaymentService(
            error: const PaymentException(PaymentErrorType.cancelled, 'cancelled')));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(find.text("Payment cancelled — you haven't been charged."), findsOneWidget);
    expect(find.text('Pay ₹275'), findsOneWidget);
    expect(find.text('Booking confirmed! 🎉'), findsNothing);
  });

  testWidgets('failed: failure snackbar, no navigation', (tester) async {
    await _pump(tester,
        payments: FakePaymentService(
            error: const PaymentException(PaymentErrorType.failed, 'declined')));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(find.text("Payment failed — you haven't been charged. Try again."), findsOneWidget);
    expect(find.text('Booking confirmed! 🎉'), findsNothing);
  });

  testWidgets('unverified: snackbar carries the payment id, no navigation', (tester) async {
    await _pump(tester,
        payments: FakePaymentService(
            error: const PaymentException(PaymentErrorType.unverified, 'verification-failed',
                paymentId: 'pay_x9')));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pay_x9'), findsOneWidget);
    expect(find.text('Booking confirmed! 🎉'), findsNothing);
  });

  testWidgets('button is disabled while a payment is in flight', (tester) async {
    final gate = Completer<PaymentResult>();
    final (_, payments, _) = await _pump(tester, payments: FakePaymentService(gate: gate));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pump();
    expect(find.text('Opening…'), findsOneWidget);
    await tester.tap(find.text('Opening…')); // second tap must be a no-op
    await tester.pump();
    gate.complete(const PaymentResult(paymentId: 'pay_g', orderId: 'order_g'));
    await tester.pumpAndSettle();
    expect(payments.paidBookingIds.length, 1); // single attempt
  });
}
