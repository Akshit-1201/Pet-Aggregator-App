import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
    serviceType: ServiceType.walker, rate: 250, experienceYears: 4);

void main() {
  testWidgets('creating the booking writes a machine-readable ISO date', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final bookings = InMemoryBookingRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets(uid))),
      bookingRepositoryProvider.overrideWithValue(bookings),
      paymentServiceProvider.overrideWithValue(FakePaymentService.success()),
    ], initialLocation: Routes.booking, extra: _pro);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Continue to payment'));
    await tester.tap(find.text('Continue to payment'));
    await tester.pumpAndSettle();

    final stored = (await bookings.watchMyBookings(uid).first).single;
    expect(stored.status, 'pending'); // BookingScreen creates the pending booking before navigating
    expect(stored.date, Booking.isoDate(DateTime.now())); // default selection = today
  });
}
