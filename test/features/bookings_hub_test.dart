import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

HomestayBooking _stay(String id, String guestId, {String status = 'requested',
        String hostId = 'host1', DateTime? checkIn, DateTime? checkOut}) =>
    HomestayBooking(id: id, guestId: guestId, hostId: hostId, homeName: "Meera's Home",
        hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: checkIn ?? DateTime.now().add(const Duration(days: 3)),
        checkOut: checkOut ?? DateTime.now().add(const Duration(days: 6)),
        nights: 3, subtotal: 2700, fee: 150, total: 2850, status: status);

Future<(FakeAuthRepository, String)> _me() async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  return (auth, auth.currentUser!.uid);
}

void main() {
  testWidgets('plain pet parent: no Received tab, title stays My Bookings', (tester) async {
    final (auth, uid) = await _me();
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(_stay('hb1', uid));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(hbookings),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    expect(find.text('My Bookings'), findsOneWidget);
    expect(find.text('Received'), findsNothing);
  });

  testWidgets('chips reflect phases; Rate hidden until completed', (tester) async {
    final (auth, uid) = await _me();
    // Seeded directly (not via createBooking, which forces 'pending' to match
    // production) to represent a booking the server has already confirmed.
    final bookings = InMemoryBookingRepository([Booking(id: 'bk1', parentId: uid, proId: 'pro1',
        proName: 'Aarav Sharma', petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker,
        rate: 250, fee: 25, total: 275, dateLabel: 'Tue', timeSlot: '5:00 PM',
        date: Booking.isoDate(DateTime.now().add(const Duration(days: 2))))]);
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(_stay('hb1', uid));                       // Pending
    await hbookings.createHomestayBooking(_stay('hb2', uid, status: 'declined'));   // Declined
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(bookings),
      homestayBookingRepositoryProvider.overrideWithValue(hbookings),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    expect(find.text('Upcoming'), findsOneWidget);   // the future service booking
    expect(find.text('Pending'), findsOneWidget);    // hb1
    expect(find.text('Declined'), findsOneWidget);   // hb2
    expect(find.text('Rate'), findsNothing);         // nothing completed yet
  });

  testWidgets('guest cancels a pending request via the confirm dialog', (tester) async {
    final (auth, uid) = await _me();
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(_stay('hb1', uid));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(hbookings),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this booking?'), findsOneWidget);
    await tester.tap(find.text('Keep'));               // dismiss: nothing happens
    await tester.pumpAndSettle();
    expect(find.text('Pending'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel booking'));      // confirm
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsOneWidget);
    expect((await hbookings.watchMyHomestayBookings(uid).first).single.status, 'cancelled');
  });

  testWidgets('a host sees the Received tab and the Bookings title', (tester) async {
    final (auth, uid) = await _me();
    final homestays = InMemoryHomestayRepository();
    await homestays.upsertHomestay(Homestay(uid: uid, homeName: 'My Home', hostName: 'Me',
        area: 'Khar', about: '', homeType: HomeType.apartment, ratePerNight: 900));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(homestays),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('My bookings'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
  });

  testWidgets('a legacy rated-but-upcoming stay still offers Cancel', (tester) async {
    final (auth, uid) = await _me();
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(_stay('hb1', uid)); // requested, future dates
    final reviews = InMemoryReviewRepository();
    await reviews.submitReview(Review(targetType: ReviewTargetType.homestay, targetId: 'host1',
        targetName: "Meera's Home", authorId: uid, authorName: 'Me', bookingId: 'hb1',
        stars: 5, createdAt: 1));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(hbookings),
      reviewRepositoryProvider.overrideWithValue(reviews),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    expect(find.text('★ Rated'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel booking'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsOneWidget);
    expect((await hbookings.watchMyHomestayBookings(uid).first).single.status, 'cancelled');
  });
}
