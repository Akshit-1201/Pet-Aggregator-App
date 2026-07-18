import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import '../support/fakes.dart';

Booking _booking({int createdAt = 0}) => Booking(id: 'bk1', parentId: 'me', proId: 'p1',
    proName: 'Aarav', petId: 'x', petName: 'Bruno', serviceType: ServiceType.walker,
    rate: 250, fee: 25, total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', createdAt: createdAt);

void main() {
  test('Booking.createdAt round-trips; stale non-int degrades to 0', () {
    expect(Booking.fromMap('bk1', _booking(createdAt: 42).toMap()).createdAt, 42);
    expect(Booking.fromMap('bk1', {'createdAt': 'not-an-int'}).createdAt, 0); // defensive guard
  });

  test('createBooking stamps createdAt when unset, preserves when set', () async {
    final repo = InMemoryBookingRepository();
    await repo.createBooking(_booking()); // createdAt 0 -> stamped
    final stamped = (await repo.watchMyBookings('me').first).single;
    expect(stamped.createdAt, greaterThan(0));

    final repo2 = InMemoryBookingRepository();
    await repo2.createBooking(_booking(createdAt: 500));
    expect((await repo2.watchMyBookings('me').first).single.createdAt, 500);
  });

  test('HomestayBooking.createdAt round-trips + fake stamps', () async {
    final hb = HomestayBooking(id: 'hb1', guestId: 'me', hostId: 'h1', homeName: "Meera's Home",
        hostName: 'Meera', petId: 'x', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 7, 20), checkOut: DateTime(2026, 7, 23), nights: 3,
        subtotal: 2700, fee: 150, total: 2850, createdAt: 7);
    expect(HomestayBooking.fromMap('hb1', hb.toMap()).createdAt, 7);
    final repo = InMemoryHomestayBookingRepository();
    await repo.createHomestayBooking(HomestayBooking(guestId: 'me', hostId: 'h1', homeName: 'H',
        hostName: 'M', petId: 'x', petName: 'B', ratePerNight: 900, checkIn: DateTime(2026, 7, 20),
        checkOut: DateTime(2026, 7, 23), nights: 3, subtotal: 2700, fee: 150, total: 2850));
    expect((await repo.watchMyHomestayBookings('me').first).single.createdAt, greaterThan(0));
  });
}
