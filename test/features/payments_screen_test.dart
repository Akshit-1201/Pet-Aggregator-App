import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _uid = 'uid_me@x.com'; // FakeAuthRepository derives uid from the email

Booking _paidService() => const Booking(id: 'bk1', parentId: _uid, proId: 'pro1', proName: 'Aarav Sharma',
    petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
    dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', status: 'confirmed',
    paymentId: 'pay_svc', updatedAt: 2000);

HomestayBooking _paidStay() => HomestayBooking(id: 'hb1', guestId: _uid, hostId: 'h', homeName: "Meera's Home",
    hostName: 'Meera', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
    checkIn: DateTime(2026, 8, 10), checkOut: DateTime(2026, 8, 13), nights: 3,
    subtotal: 2700, fee: 150, total: 2850, status: 'paid', paymentId: 'pay_stay', updatedAt: 1000);

Future<void> _pump(WidgetTester tester,
    {List<Booking> services = const [], List<HomestayBooking> stays = const []}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
  final bookings = InMemoryBookingRepository(services);
  final hbookings = InMemoryHomestayBookingRepository();
  for (final s in stays) {
    await hbookings.createHomestayBooking(s);
  }
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    bookingRepositoryProvider.overrideWithValue(bookings),
    homestayBookingRepositoryProvider.overrideWithValue(hbookings),
  ], initialLocation: Routes.payments);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists paid services + stays, newest first, with amounts', (tester) async {
    // service updatedAt 2000 > stay 1000, so the service sorts first.
    await _pump(tester, services: [_paidService()], stays: [_paidStay()]);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text("Meera's Home"), findsOneWidget);
    expect(find.text('₹275'), findsOneWidget);
    expect(find.text('₹2850'), findsOneWidget);
  });

  testWidgets('unpaid bookings never appear on Payments', (tester) async {
    final unpaid = Booking(id: 'bk2', parentId: _uid, proId: 'pro2', proName: 'Not Paid Pro',
        petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25,
        total: 275, dateLabel: 'Wed', timeSlot: '6 PM', status: 'pending', date: '2030-01-01');
    await _pump(tester, services: [_paidService(), unpaid]);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Not Paid Pro'), findsNothing);
  });

  testWidgets('tapping a row opens the full receipt', (tester) async {
    await _pump(tester, services: [_paidService()]);
    await tester.tap(find.text('Aarav Sharma'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt'), findsOneWidget);
    expect(find.text('Total paid'), findsOneWidget);
    expect(find.text('Payment ID'), findsOneWidget);
    expect(find.text('pay_svc'), findsOneWidget);
  });

  testWidgets('empty state when nothing has been paid', (tester) async {
    await _pump(tester);
    expect(find.text('No payments yet'), findsOneWidget);
  });
}
