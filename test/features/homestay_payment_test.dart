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

class _FailOnceHomestayRepo extends InMemoryHomestayBookingRepository {
  int _left = 1;
  @override
  Future<void> markPaid(String id, String paymentId) {
    if (_left > 0) { _left--; throw Exception('write-failed'); }
    return super.markPaid(id, paymentId);
  }
}

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

  testWidgets('success: charged the total, marks paid with paymentId, navigates', (tester) async {
    final (repo, payments) = await _pump(tester);
    await tester.tap(find.text('Pay ₹2850'));
    await tester.pumpAndSettle();
    expect(payments.chargedAmounts, [2850]);
    final s = (await repo.watchMyHomestayBookings('uid_me@x.com').first).single;
    expect(s.status, 'paid');
    expect(s.paymentId, 'pay_fake123');
  });

  testWidgets('cancelled: not paid, honest snackbar, button idle', (tester) async {
    final (repo, _) = await _pump(tester,
        payments: FakePaymentService(error: const PaymentException(PaymentErrorType.cancelled, 'x')));
    await tester.tap(find.text('Pay ₹2850'));
    await tester.pumpAndSettle();
    expect(find.text("Payment cancelled — you haven't been charged."), findsOneWidget);
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

  testWidgets('write-fails-after-pay: Retry saving marks paid without a second charge', (tester) async {
    final repo = _FailOnceHomestayRepo();
    final (_, payments) = await _pump(tester, repo: repo);
    await tester.tap(find.text('Pay ₹2850'));
    await tester.pumpAndSettle();
    expect(find.text('Retry saving'), findsOneWidget);
    await tester.tap(find.text('Retry saving'));
    await tester.pumpAndSettle();
    expect(payments.chargedAmounts, [2850]); // one charge across both taps
    expect((await repo.watchMyHomestayBookings('uid_me@x.com').first).single.status, 'paid');
  });
}
