// A paid service booking used to be cancellable straight from the client, which
// silently kept the customer's money and left the pro's payout standing for a
// service that never happened. These pin the fixed behaviour.
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/booking_lifecycle.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/refund_policy.dart';

Booking _booking({required String status, required String date}) => Booking(
      id: 'b1', parentId: 'me', proId: 'pro1', proName: 'Aarav',
      petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker,
      rate: 250, fee: 25, total: 275,
      dateLabel: 'Tue 15 Jul', timeSlot: '9:00 AM', status: status, date: date);

void main() {
  final now = DateTime(2026, 7, 14, 10); // 14 Jul, 10am

  group('who may cancel what', () {
    test('an UNPAID booking is client-cancellable', () {
      final b = _booking(status: 'pending', date: '2026-07-15');
      expect(canCancelService(b, now), isTrue);
      expect(canCancelPaidService(b, now), isFalse);
    });

    test('a PAID booking is not client-cancellable — it must go through the server', () {
      // This is the fix: 'confirmed' means paid, and the old canCancelService
      // returned true for it, letting the client write status=cancelled with no
      // refund and no payout reversal.
      final b = _booking(status: 'confirmed', date: '2026-07-15');
      expect(canCancelService(b, now), isFalse);
      expect(canCancelPaidService(b, now), isTrue);
    });

    test('neither path is offered once the service day has arrived', () {
      final b = _booking(status: 'confirmed', date: '2026-07-14');
      expect(canCancelService(b, now), isFalse);
      expect(canCancelPaidService(b, now), isFalse);
    });
  });

  group('refund amount', () {
    test('cancelling before the service day refunds the rate, never the fee', () {
      final b = _booking(status: 'confirmed', date: '2026-07-15');
      expect(serviceRefundRupees(b, now), 250); // rate, not the 275 total
    });

    test('cancelling on the service day refunds nothing', () {
      final b = _booking(status: 'confirmed', date: '2026-07-14');
      expect(serviceRefundRupees(b, now), 0);
    });

    test('a day is enough — the policy is day-granular, not 24 hours', () {
      // Booking tomorrow, cancelled at 10pm tonight: under a literal 24h rule
      // measured from IST midnight this would refund nothing, which is why the
      // policy is expressed in days.
      final b = _booking(status: 'confirmed', date: '2026-07-15');
      expect(serviceRefundRupees(b, DateTime(2026, 7, 14, 22)), 250);
    });

    test('a legacy booking with no machine-readable date refunds nothing', () {
      final b = _booking(status: 'confirmed', date: '');
      expect(serviceRefundRupees(b, now), 0);
    });
  });
}
