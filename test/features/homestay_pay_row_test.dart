// test/features/homestay_pay_row_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

HomestayBooking _stay(String uid, {required String status, int checkInDays = 5}) => HomestayBooking(
    id: 'hb1', guestId: uid, hostId: 'host1', homeName: "Meera's Home", hostName: 'Meera',
    petId: 'p1', petName: 'Bruno', ratePerNight: 900,
    checkIn: DateTime.now().add(Duration(days: checkInDays)),
    checkOut: DateTime.now().add(Duration(days: checkInDays + 3)),
    nights: 3, subtotal: 2700, fee: 150, total: 2850, status: status);

Future<void> _pump(WidgetTester tester, HomestayBooking stay) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final repo = InMemoryHomestayBookingRepository();
  await repo.createHomestayBooking(stay);
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    homestayBookingRepositoryProvider.overrideWithValue(repo),
    bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
  ], initialLocation: Routes.bookings);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('accepted stay shows Awaiting payment chip + Pay to confirm button + Cancel; Pay opens payment', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'accepted'));
    // The BookingPhase.awaitingPayment chip label is 'Awaiting payment' (a
    // neutral state descriptor); the separate CTA button below it is the
    // guest-facing action 'Pay to confirm'. State vs action — not redundant.
    expect(find.text('Awaiting payment'), findsOneWidget);
    expect(find.text('Pay to confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.widgetWithText(GestureDetector, 'Pay to confirm'));
    await tester.pumpAndSettle();
    expect(find.text('🔒 Secured by Razorpay — UPI, cards & netbanking'), findsOneWidget); // payment screen
  });

  testWidgets('paid/upcoming stay shows no Cancel, shows Contact host to cancel', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'paid'));
    expect(find.text('Contact host to cancel'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Pay to confirm'), findsNothing);
  });
}
