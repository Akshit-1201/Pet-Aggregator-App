import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _draft = Booking(parentId: 'uid_me@x.com', proId: 'pro1', proName: 'Aarav Sharma',
    petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25,
    total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM');

void main() {
  testWidgets('Pay navigates to the confirmation for an already-created (pending) booking',
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final bookings = InMemoryBookingRepository();
    final created = await bookings.createBooking(_draft); // the seam now expects a created booking
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(bookings),
      paymentServiceProvider.overrideWithValue(FakePaymentService.success()),
    ], initialLocation: Routes.payment, extra: created);
    await tester.pumpAndSettle();

    expect(find.textContaining('275'), findsWidgets);
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();

    expect(find.text('Booking confirmed! 🎉'), findsOneWidget);
  });
}
