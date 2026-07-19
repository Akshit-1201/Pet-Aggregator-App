import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import '../support/fakes.dart';

Booking _svc(String id, {String parentId = 'g', String proId = 'p', int createdAt = 0}) => Booking(
    id: id, parentId: parentId, proId: proId, proName: 'Aarav', petId: 'x', petName: 'Bruno',
    serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
    dateLabel: 'Tue', timeSlot: '5:00 PM', date: '2027-01-10', createdAt: createdAt);

HomestayBooking _stay(String id, {String guestId = 'g', String hostId = 'h'}) => HomestayBooking(
    id: id, guestId: guestId, hostId: hostId, homeName: 'H', hostName: 'M', petId: 'x',
    petName: 'Bruno', ratePerNight: 900, checkIn: DateTime(2027, 1, 10),
    checkOut: DateTime(2027, 1, 13), nights: 3, subtotal: 2700, fee: 150, total: 2850);

void main() {
  test('watchBookingsForPro filters by proId, newest first', () async {
    final repo = InMemoryBookingRepository();
    await repo.createBooking(_svc('a', proId: 'me', createdAt: 1));
    await repo.createBooking(_svc('b', proId: 'me', createdAt: 2));
    await repo.createBooking(_svc('c', proId: 'other', createdAt: 3));
    final mine = await repo.watchBookingsForPro('me').first;
    expect(mine.map((b) => b.id).toList(), ['b', 'a']);
  });

  test('cancelBooking flips status + stamps updatedAt', () async {
    final repo = InMemoryBookingRepository();
    await repo.createBooking(_svc('a'));
    await repo.cancelBooking('a');
    final b = (await repo.watchMyBookings('g').first).single;
    expect(b.status, 'cancelled');
    expect(b.updatedAt, greaterThan(0));
  });

  test('watchBookingsForHost filters by hostId', () async {
    final repo = InMemoryHomestayBookingRepository();
    await repo.createHomestayBooking(_stay('s1', hostId: 'me'));
    await repo.createHomestayBooking(_stay('s2', hostId: 'other'));
    final mine = await repo.watchBookingsForHost('me').first;
    expect(mine.single.id, 's1');
  });

  test('accept / decline / cancel set status + updatedAt', () async {
    final repo = InMemoryHomestayBookingRepository();
    await repo.createHomestayBooking(_stay('s1'));
    await repo.acceptRequest('s1');
    var s = (await repo.watchMyHomestayBookings('g').first).firstWhere((x) => x.id == 's1');
    expect(s.status, 'accepted');
    expect(s.updatedAt, greaterThan(0));

    await repo.createHomestayBooking(_stay('s2'));
    await repo.declineRequest('s2');
    s = (await repo.watchMyHomestayBookings('g').first).firstWhere((x) => x.id == 's2');
    expect(s.status, 'declined');

    await repo.cancelStay('s1');
    s = (await repo.watchMyHomestayBookings('g').first).firstWhere((x) => x.id == 's1');
    expect(s.status, 'cancelled');
  });
}
