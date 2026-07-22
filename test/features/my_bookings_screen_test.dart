import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
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
    final now = DateTime.now();
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(HomestayBooking(id: 'hb1', guestId: uid, hostId: 'host1',
        homeName: "Meera's Home", hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: now.subtract(const Duration(days: 5)), checkOut: now.subtract(const Duration(days: 2)),
        nights: 3, subtotal: 2700, fee: 150, total: 2850, status: 'paid'));
    final reviews = InMemoryReviewRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      bookingRepositoryProvider.overrideWithValue(bookings),
      homestayBookingRepositoryProvider.overrideWithValue(hbookings),
      reviewRepositoryProvider.overrideWithValue(reviews),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
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

  testWidgets('an unpaid pending service booking offers Pay to confirm and resumes payment',
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final bookings = InMemoryBookingRepository();
    // createBooking forces status:'pending'; a future date makes it payable
    // (awaitingPayment) rather than expired — the "abandon checkout, pay later" case.
    await bookings.createBooking(Booking(id: 'bk1', parentId: uid, proId: 'pro1', proName: 'Aarav Sharma',
        petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', date: '2030-01-10'));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(bookings),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    expect(find.text('Pay to confirm'), findsOneWidget);
    await tester.tap(find.text('Pay to confirm'));
    await tester.pumpAndSettle();

    // Navigated to the payment screen for this booking (pays by id, no re-charge risk).
    expect(find.text('Pay ₹275'), findsOneWidget);
  });

  testWidgets('a reviewed booking shows ★ Rated instead of Rate', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final bookings = InMemoryBookingRepository();
    await bookings.createBooking(Booking(id: 'bk1', parentId: uid, proId: 'pro1', proName: 'Aarav Sharma',
        petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM'));
    final now = DateTime.now();
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(HomestayBooking(id: 'hb1', guestId: uid, hostId: 'host1',
        homeName: "Meera's Home", hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: now.subtract(const Duration(days: 5)), checkOut: now.subtract(const Duration(days: 2)),
        nights: 3, subtotal: 2700, fee: 150, total: 2850, status: 'paid'));
    final reviews = InMemoryReviewRepository();
    // The service booking (bk1) is already reviewed; the homestay (hb1) is not.
    await reviews.submitReview(Review(targetType: ReviewTargetType.pro, targetId: 'pro1',
        targetName: 'Aarav Sharma', authorId: uid, authorName: 'Radhika', bookingId: 'bk1',
        stars: 5, createdAt: 1));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(bookings),
      homestayBookingRepositoryProvider.overrideWithValue(hbookings),
      reviewRepositoryProvider.overrideWithValue(reviews),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    expect(find.text('★ Rated'), findsOneWidget);       // bk1, keyed by booking id
    expect(find.text('Rate'), findsOneWidget);           // only hb1 is still rateable
  });
}
