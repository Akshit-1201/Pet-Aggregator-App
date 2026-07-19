import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

void main() {
  test('Booking.date + updatedAt round-trip; default empty/0; non-int degrades', () {
    final b = Booking(id: 'bk1', parentId: 'g', proId: 'p', proName: 'Aarav', petId: 'x',
        petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue 21 Jul', timeSlot: '5:00 PM', date: '2026-07-21', updatedAt: 9);
    final back = Booking.fromMap('bk1', b.toMap());
    expect(back.date, '2026-07-21');
    expect(back.updatedAt, 9);
    expect(Booking.fromMap('bk1', const {}).date, '');
    expect(Booking.fromMap('bk1', const {}).updatedAt, 0);
    expect(Booking.fromMap('bk1', const {'updatedAt': 'x'}).updatedAt, 0);
  });

  test('Booking.isoDate pads to yyyy-MM-dd', () {
    expect(Booking.isoDate(DateTime(2026, 7, 5)), '2026-07-05');
    expect(Booking.isoDate(DateTime(2026, 11, 23)), '2026-11-23');
  });

  test('HomestayBooking.updatedAt round-trips; default 0', () {
    final s = HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h', homeName: 'H',
        hostName: 'M', petId: 'x', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 7, 20), checkOut: DateTime(2026, 7, 23), nights: 3,
        subtotal: 2700, fee: 150, total: 2850, updatedAt: 7);
    expect(HomestayBooking.fromMap('hb1', s.toMap()).updatedAt, 7);
    expect(HomestayBooking.fromMap('hb1', {'checkIn': '2026-07-20', 'checkOut': '2026-07-23'}).updatedAt, 0);
  });
}
