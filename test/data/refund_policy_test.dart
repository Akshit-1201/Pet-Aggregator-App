// test/data/refund_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/refund_policy.dart';

HomestayBooking _stay({required DateTime checkIn, int subtotal = 2700}) => HomestayBooking(
    id: 'hb1', guestId: 'g', hostId: 'h', homeName: 'H', hostName: 'M', petId: 'x',
    petName: 'Bruno', ratePerNight: 900, checkIn: checkIn,
    checkOut: checkIn.add(const Duration(days: 3)), nights: 3, subtotal: subtotal,
    fee: 150, total: subtotal + 150, status: 'paid');

void main() {
  final now = DateTime(2026, 7, 19, 12, 0);

  test('>= 24h before check-in refunds the full subtotal', () {
    expect(refundRupees(_stay(checkIn: now.add(const Duration(hours: 24))), now), 2700);
    expect(refundRupees(_stay(checkIn: now.add(const Duration(days: 5))), now), 2700);
    expect(refundRupees(_stay(checkIn: now.add(const Duration(hours: 24)), subtotal: 5000), now), 5000);
  });

  test('< 24h before check-in refunds 0', () {
    expect(refundRupees(_stay(checkIn: now.add(const Duration(hours: 23, minutes: 59))), now), 0);
    expect(refundRupees(_stay(checkIn: now.add(const Duration(hours: 1))), now), 0);
  });

  test('at or after check-in refunds 0', () {
    expect(refundRupees(_stay(checkIn: now), now), 0);
    expect(refundRupees(_stay(checkIn: now.subtract(const Duration(hours: 2))), now), 0);
  });

  test('HomestayBooking.refundAmount/refundId round-trip and default', () {
    final b = _stay(checkIn: now);
    expect(HomestayBooking.fromMap('hb1', b.toMap()).refundAmount, 0);
    expect(HomestayBooking.fromMap('hb1', b.toMap()).refundId, '');
    final r = HomestayBooking.fromMap('hb1', {...b.toMap(), 'refundAmount': 900, 'refundId': 'rfnd_1'});
    expect(r.refundAmount, 900);
    expect(r.refundId, 'rfnd_1');
  });
}
