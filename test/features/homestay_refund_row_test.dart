// test/features/homestay_refund_row_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

HomestayBooking _stay(String uid, {required String status, required int checkInHours,
        int refundAmount = 0, String refundId = ''}) =>
    HomestayBooking(id: 'hb1', guestId: uid, hostId: 'host1', homeName: "Meera's Home",
        hostName: 'Meera', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime.now().add(Duration(hours: checkInHours)),
        checkOut: DateTime.now().add(Duration(hours: checkInHours + 72)),
        nights: 3, subtotal: 2700, fee: 150, total: 2850, status: status,
        paymentId: 'pay_x', refundAmount: refundAmount, refundId: refundId,
        createdAt: DateTime.now().millisecondsSinceEpoch);

// Note: FakePaymentService.refundStay only records the call + returns the result
// (it models the CLIENT calling the function); the actual paid->cancelled write is
// server-side, so these widget tests assert the client behavior (refundStay called,
// snackbar, dialog copy), not a repo status flip — that's covered by the Function
// emulator test + the on-device pass.
Future<(InMemoryHomestayBookingRepository, FakePaymentService)> _pump(WidgetTester tester,
    HomestayBooking stay, {FakePaymentService? payments}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final repo = InMemoryHomestayBookingRepository();
  await repo.createHomestayBooking(stay);
  final p = payments ?? FakePaymentService();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    homestayBookingRepositoryProvider.overrideWithValue(repo),
    bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    paymentServiceProvider.overrideWithValue(p),
  ], initialLocation: Routes.bookings);
  await tester.pumpAndSettle();
  return (repo, p);
}

void main() {
  testWidgets('paid + >=24h shows Cancel; dialog shows the full-refund estimate', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'paid', checkInHours: 120)); // 5 days out
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('₹2700 of ₹2850'), findsOneWidget);
    expect(find.text('Cancel & refund'), findsOneWidget);
  });

  testWidgets('paid + <24h dialog shows the non-refundable copy', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'paid', checkInHours: 6)); // 6h out
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining("within 24 hours of check-in aren't refundable"), findsOneWidget);
    expect(find.text('Cancel anyway'), findsOneWidget);
  });

  testWidgets('confirming Cancel & refund calls refundStay for the booking', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final payments = FakePaymentService(
        refundResult: const RefundResult(refundAmount: 2700, refundId: 'rfnd_1'));
    final (_, p) = await _pump(tester, _stay(uid, status: 'paid', checkInHours: 120), payments: payments);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel & refund'));
    await tester.pumpAndSettle();
    expect(p.refundedBookingIds, ['hb1']);
    expect(find.textContaining('₹2700 will be refunded'), findsOneWidget);
  });

  testWidgets('mid-stay paid (after check-in) shows Contact host, no Cancel', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'paid', checkInHours: -12)); // checked in 12h ago
    expect(find.text('Contact host to cancel'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('a cancelled stay with a refund shows the refunded amount', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester,
        _stay(uid, status: 'cancelled', checkInHours: 120, refundAmount: 900, refundId: 'rfnd_1'));
    expect(find.textContaining('₹900 refunded'), findsOneWidget);
  });

  testWidgets('a claimed-but-unrefunded stay shows refund pending, not refunded', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'cancelled', checkInHours: 120, refundAmount: 900));
    expect(find.textContaining('₹900 refund pending'), findsOneWidget);
    expect(find.textContaining('₹900 refunded'), findsNothing);
  });

  testWidgets('tapping Keep dismisses the dialog and refunds nothing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final payments = FakePaymentService(
        refundResult: const RefundResult(refundAmount: 2700, refundId: 'rfnd_1'));
    final (_, p) = await _pump(tester, _stay(uid, status: 'paid', checkInHours: 120), payments: payments);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(p.refundedBookingIds, isEmpty);
    expect(find.text('Cancel this stay?'), findsNothing);
  });

  testWidgets('a post-claim refund failure says the stay was cancelled', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final payments = FakePaymentService(
        refundError: const PaymentException(PaymentErrorType.failed, 'refund-failed'));
    await _pump(tester, _stay(uid, status: 'paid', checkInHours: 120), payments: payments);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel & refund'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stay cancelled, but the refund'), findsOneWidget);
  });

  testWidgets('an ambiguous/unconfirmed refund failure tells the user to check bookings',
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final payments = FakePaymentService(
        refundError: const PaymentException(PaymentErrorType.failed, 'unconfirmed'));
    await _pump(tester, _stay(uid, status: 'paid', checkInHours: 120), payments: payments);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel & refund'));
    await tester.pumpAndSettle();
    expect(find.textContaining("couldn't confirm this cancellation"), findsOneWidget);
  });

  testWidgets('a pre-claim failure says nothing happened', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final payments = FakePaymentService(
        refundError: const PaymentException(PaymentErrorType.failed, 'cancel-failed'));
    await _pump(tester, _stay(uid, status: 'paid', checkInHours: 120), payments: payments);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel & refund'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't cancel the stay"), findsOneWidget);
  });
}
