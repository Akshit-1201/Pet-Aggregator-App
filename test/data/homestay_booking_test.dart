import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';

void main() {
  test('serviceFee / nightsBetween / fmtDay', () {
    expect(HomestayBooking.serviceFee, 150);
    expect(HomestayBooking.nightsBetween(DateTime(2026, 7, 12), DateTime(2026, 7, 15)), 3);
    expect(HomestayBooking.fmtDay(DateTime(2024, 1, 1)), 'Mon, 1 Jan'); // 2024-01-01 was a Monday
  });

  test('toMap omits id/createdAt with ISO dates; fromMap restores', () {
    final b = HomestayBooking(guestId: 'g1', hostId: 'h1', homeName: "Meera's Home",
        hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 7, 12), checkOut: DateTime(2026, 7, 15), nights: 3,
        subtotal: 2700, fee: 150, total: 2850, note: 'Friendly boy');
    final m = b.toMap();
    expect(m.containsKey('id'), isFalse);
    expect(m.containsKey('createdAt'), isFalse);
    expect(m['checkIn'], '2026-07-12');
    expect(m['checkOut'], '2026-07-15');
    expect(m['status'], 'requested');
    expect(m['total'], 2850);
    final back = HomestayBooking.fromMap('bk1', m);
    expect(back.id, 'bk1');
    expect(back.petName, 'Bruno');
    expect(back.checkIn, DateTime(2026, 7, 12));
    expect(back.nights, 3);
    expect(back.note, 'Friendly boy');
  });
}
