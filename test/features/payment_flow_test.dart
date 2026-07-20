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

class _FailingOnceBookingRepository extends InMemoryBookingRepository {
  int _failuresLeft = 1;
  @override
  Future<void> createBooking(Booking booking) {
    if (_failuresLeft > 0) {
      _failuresLeft--;
      throw Exception('write-failed');
    }
    return super.createBooking(booking);
  }
}

Future<(InMemoryBookingRepository, FakePaymentService)> _pump(WidgetTester tester,
    {FakePaymentService? payments, InMemoryBookingRepository? bookings}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final b = bookings ?? InMemoryBookingRepository();
  final p = payments ?? FakePaymentService.success();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    bookingRepositoryProvider.overrideWithValue(b),
    paymentServiceProvider.overrideWithValue(p),
  ], initialLocation: Routes.payment, extra: _draft);
  await tester.pumpAndSettle();
  return (b, p);
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

  testWidgets('success: charged the exact total, booking written with paymentId, navigates',
      (tester) async {
    final (bookings, payments) = await _pump(tester);
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(payments.chargedAmounts, [275]);
    final stored = (await bookings.watchMyBookings('uid_me@x.com').first).single;
    expect(stored.paymentId, 'pay_fake123');
    expect(stored.date, '2027-01-10'); // draft fields survive
    expect(find.text('Booking confirmed! 🎉'), findsOneWidget);
  });

  testWidgets('cancelled: no booking, honest snackbar, button idle again', (tester) async {
    final (bookings, _) = await _pump(tester,
        payments: FakePaymentService(
            error: const PaymentException(PaymentErrorType.cancelled, 'cancelled')));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(find.text("Payment cancelled — you haven't been charged."), findsOneWidget);
    expect(find.text('Pay ₹275'), findsOneWidget);
    expect(await bookings.watchMyBookings('uid_me@x.com').first, isEmpty);
  });

  testWidgets('failed: no booking, failure snackbar', (tester) async {
    final (bookings, _) = await _pump(tester,
        payments: FakePaymentService(
            error: const PaymentException(PaymentErrorType.failed, 'declined')));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(find.text("Payment failed — you haven't been charged. Try again."), findsOneWidget);
    expect(await bookings.watchMyBookings('uid_me@x.com').first, isEmpty);
  });

  testWidgets('unverified: no booking, snackbar carries the payment id', (tester) async {
    final (bookings, _) = await _pump(tester,
        payments: FakePaymentService(
            error: const PaymentException(PaymentErrorType.unverified, 'verification-failed',
                paymentId: 'pay_x9')));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pay_x9'), findsOneWidget);
    expect(await bookings.watchMyBookings('uid_me@x.com').first, isEmpty);
  });

  testWidgets('write-fails-after-verified-payment: Retry saving writes without a second charge',
      (tester) async {
    final bookings = _FailingOnceBookingRepository();
    final (_, payments) = await _pump(tester, bookings: bookings);
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(find.textContaining('saving the booking failed'), findsOneWidget);
    expect(find.text('Retry saving'), findsOneWidget);

    await tester.tap(find.text('Retry saving'));
    await tester.pumpAndSettle();
    expect(payments.chargedAmounts, [275]); // exactly ONE charge across both taps
    final stored = (await bookings.watchMyBookings('uid_me@x.com').first).single;
    expect(stored.paymentId, 'pay_fake123');
    expect(find.text('Booking confirmed! 🎉'), findsOneWidget);
  });

  testWidgets('button is disabled while a payment is in flight', (tester) async {
    final gate = Completer<PaymentResult>();
    final (bookings, payments) = await _pump(tester, payments: FakePaymentService(gate: gate));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pump();
    expect(find.text('Opening…'), findsOneWidget);
    await tester.tap(find.text('Opening…')); // second tap must be a no-op
    await tester.pump();
    gate.complete(const PaymentResult(paymentId: 'pay_g', orderId: 'order_g'));
    await tester.pumpAndSettle();
    expect(payments.chargedAmounts, [275]); // single attempt
    expect((await bookings.watchMyBookings('uid_me@x.com').first).single.paymentId, 'pay_g');
  });
}
