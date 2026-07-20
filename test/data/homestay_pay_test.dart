import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import '../support/fakes.dart';

HomestayBooking _stay(String id, {String status = 'accepted'}) => HomestayBooking(
    id: id, guestId: 'g', hostId: 'h', homeName: 'H', hostName: 'M', petId: 'x',
    petName: 'Bruno', ratePerNight: 900, checkIn: DateTime(2027, 1, 10),
    checkOut: DateTime(2027, 1, 13), nights: 3, subtotal: 2700, fee: 150, total: 2850,
    status: status);

void main() {
  test('HomestayBooking.paymentId round-trips and defaults to empty', () {
    final b = HomestayBooking.fromMap('hb1', _stay('hb1').toMap());
    expect(b.paymentId, '');
    final withId = HomestayBooking.fromMap('hb1', {..._stay('hb1').toMap(), 'paymentId': 'pay_x'});
    expect(withId.paymentId, 'pay_x');
  });

  test('markPaid sets status=paid + updatedAt + paymentId', () async {
    final repo = InMemoryHomestayBookingRepository();
    await repo.createHomestayBooking(_stay('hb1'));
    await repo.markPaid('hb1', 'pay_abc');
    final s = (await repo.watchMyHomestayBookings('g').first).single;
    expect(s.status, 'paid');
    expect(s.paymentId, 'pay_abc');
    expect(s.updatedAt, greaterThan(0));
  });
}
