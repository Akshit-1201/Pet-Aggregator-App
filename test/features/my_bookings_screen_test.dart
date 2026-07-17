import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('lists services + homestays; Rate opens the Rate screen', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final bookings = InMemoryBookingRepository();
    await bookings.createBooking(Booking(id: 'bk1', parentId: uid, proId: 'pro1', proName: 'Aarav Sharma',
        petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM'));
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(HomestayBooking(id: 'hb1', guestId: uid, hostId: 'host1',
        homeName: "Meera's Home", hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 7, 20), checkOut: DateTime(2026, 7, 23), nights: 3, subtotal: 2700,
        fee: 150, total: 2850));
    final reviews = InMemoryReviewRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      bookingRepositoryProvider.overrideWithValue(bookings),
      homestayBookingRepositoryProvider.overrideWithValue(hbookings),
      reviewRepositoryProvider.overrideWithValue(reviews),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    expect(find.text('My Bookings'), findsOneWidget);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text("Meera's Home"), findsOneWidget);
    expect(find.text('Rate'), findsNWidgets(2));

    await tester.tap(find.text('Rate').first);
    await tester.pumpAndSettle();
    expect(find.text('Submit review'), findsOneWidget);
  });
}
