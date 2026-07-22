// test/features/received_tab_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

HomestayBooking _request(String id, String hostId, {String note = ''}) => HomestayBooking(
    id: id, guestId: 'guest1', hostId: hostId, homeName: 'My Home', hostName: 'Me',
    petId: 'p1', petName: 'Bruno', ratePerNight: 900,
    checkIn: DateTime.now().add(const Duration(days: 3)),
    checkOut: DateTime.now().add(const Duration(days: 6)),
    nights: 3, subtotal: 2700, fee: 150, total: 2850, note: note);

Future<void> _pumpAsHost(WidgetTester tester,
    {required FakeAuthRepository auth,
    required InMemoryHomestayBookingRepository hbookings,
    InMemoryBookingRepository? bookings,
    InMemoryProRepository? pros,
    InMemoryHomestayRepository? homestays}) async {
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    bookingRepositoryProvider.overrideWithValue(bookings ?? InMemoryBookingRepository()),
    homestayBookingRepositoryProvider.overrideWithValue(hbookings),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    proRepositoryProvider.overrideWithValue(pros ?? InMemoryProRepository()),
    homestayRepositoryProvider.overrideWithValue(homestays ?? InMemoryHomestayRepository()),
  ], initialLocation: Routes.bookings);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Received'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('host sees a pending request and Accept flips it to Awaiting payment', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'host@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final homestays = InMemoryHomestayRepository();
    await homestays.upsertHomestay(Homestay(uid: uid, homeName: 'My Home', hostName: 'Me',
        area: 'Khar', about: '', homeType: HomeType.apartment, ratePerNight: 900));
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(_request('hb1', uid, note: 'Friendly boy'));

    await _pumpAsHost(tester, auth: auth, hbookings: hbookings, homestays: homestays);

    expect(find.text('Stay request · Bruno'), findsOneWidget);
    expect(find.text('"Friendly boy"'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Awaiting payment'), findsOneWidget);
    final stored = (await hbookings.watchBookingsForHost(uid).first).single;
    expect(stored.status, 'accepted');
    expect(stored.updatedAt, greaterThan(0));
  });

  testWidgets('Decline asks for confirmation first', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'host@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final homestays = InMemoryHomestayRepository();
    await homestays.upsertHomestay(Homestay(uid: uid, homeName: 'My Home', hostName: 'Me',
        area: 'Khar', about: '', homeType: HomeType.apartment, ratePerNight: 900));
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(_request('hb1', uid));

    await _pumpAsHost(tester, auth: auth, hbookings: hbookings, homestays: homestays);

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(find.text('Decline this request?'), findsOneWidget);
    await tester.tap(find.text('Decline').last); // the dialog's confirm action
    await tester.pumpAndSettle();
    expect(find.text('Declined'), findsOneWidget);
    expect((await hbookings.watchBookingsForHost(uid).first).single.status, 'declined');
  });

  testWidgets('a pro sees a read-only ledger of their service bookings', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'pro@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final pros = InMemoryProRepository();
    await pros.upsertPro(Pro(uid: uid, name: 'Me', area: 'Khar', bio: '',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 2));
    // Seeded directly (not via createBooking, which forces 'pending' to match
    // production) to represent a booking the server has already confirmed.
    final bookings = InMemoryBookingRepository([Booking(id: 'bk1', parentId: 'guest1', proId: uid,
        proName: 'Me', petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker,
        rate: 250, fee: 25, total: 275, dateLabel: 'Tue', timeSlot: '5:00 PM',
        date: Booking.isoDate(DateTime.now().add(const Duration(days: 2))))]);

    await _pumpAsHost(tester, auth: auth,
        hbookings: InMemoryHomestayBookingRepository(), bookings: bookings, pros: pros);

    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Accept'), findsNothing); // service bookings are never actionable
  });

  testWidgets('empty received state', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'host@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final homestays = InMemoryHomestayRepository();
    await homestays.upsertHomestay(Homestay(uid: uid, homeName: 'My Home', hostName: 'Me',
        area: 'Khar', about: '', homeType: HomeType.apartment, ratePerNight: 900));

    await _pumpAsHost(tester, auth: auth,
        hbookings: InMemoryHomestayBookingRepository(), homestays: homestays);

    expect(find.text('No bookings for your listing yet.'), findsOneWidget);
  });
}
