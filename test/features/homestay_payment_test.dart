import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

HomestayBooking _accepted(String uid) => HomestayBooking(
    id: 'hb1', guestId: uid, hostId: 'host1', homeName: "Meera's Home", hostName: 'Meera Iyer',
    petId: 'p1', petName: 'Bruno', ratePerNight: 900, checkIn: DateTime.now().add(const Duration(days: 5)),
    checkOut: DateTime.now().add(const Duration(days: 8)), nights: 3, subtotal: 2700, fee: 150,
    total: 2850, status: 'accepted');

Future<(InMemoryHomestayBookingRepository, FakePaymentService)> _pump(WidgetTester tester,
    {FakePaymentService? payments, InMemoryHomestayBookingRepository? repo}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final uid = auth.currentUser!.uid;
  final r = repo ?? InMemoryHomestayBookingRepository();
  await r.createHomestayBooking(_accepted(uid));
  final p = payments ?? FakePaymentService.success();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    homestayBookingRepositoryProvider.overrideWithValue(r),
    paymentServiceProvider.overrideWithValue(p),
    proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
  ], initialLocation: Routes.homestayPayment, extra: _accepted(uid));
  await tester.pumpAndSettle();
  return (r, p);
}

void main() {
  testWidgets('shows the honest summary (home, host, nights, total)', (tester) async {
    await _pump(tester);
    expect(find.text("Meera's Home"), findsOneWidget);
    expect(find.text('🔒 Secured by Razorpay — UPI, cards & netbanking'), findsOneWidget);
    expect(find.text('Pay ₹2850'), findsOneWidget);
  });

  testWidgets('success: pays for the stay by booking id and kind', (tester) async {
    final (_, payments) = await _pump(tester);
    await tester.tap(find.text('Pay ₹2850'));
    await tester.pumpAndSettle();
    expect(payments.paidBookingIds, ['hb1']);
    expect(payments.paidKinds, [PaymentKind.homestay]);
  });

  testWidgets('cancelled: not paid, honest snackbar, button idle', (tester) async {
    final (repo, _) = await _pump(tester,
        payments: FakePaymentService(error: const PaymentException(PaymentErrorType.cancelled, 'x')));
    await tester.tap(find.text('Pay ₹2850'));
    await tester.pumpAndSettle();
    expect(find.text("Payment cancelled — you haven't been charged."), findsOneWidget);
    expect(find.text('Pay ₹2850'), findsOneWidget);
    // The server flips status to paid; the client never writes it — the fake stays as seeded.
    expect((await repo.watchMyHomestayBookings('uid_me@x.com').first).single.status, 'accepted');
  });

  testWidgets('unverified: not paid, snackbar carries the payment id', (tester) async {
    final (repo, _) = await _pump(tester,
        payments: FakePaymentService(
            error: const PaymentException(PaymentErrorType.unverified, 'x', paymentId: 'pay_z9')));
    await tester.tap(find.text('Pay ₹2850'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pay_z9'), findsOneWidget);
    expect((await repo.watchMyHomestayBookings('uid_me@x.com').first).single.status, 'accepted');
  });
}
