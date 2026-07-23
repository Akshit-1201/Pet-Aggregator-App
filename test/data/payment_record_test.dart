import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/payment_record.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

Booking _service({String id = 'bk', String paymentId = 'pay_1', int updatedAt = 0, int total = 275}) =>
    Booking(id: id, parentId: 'u', proId: 'pro', proName: 'Aarav Sharma', petId: 'p1',
        petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: total,
        dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', status: 'confirmed',
        paymentId: paymentId, updatedAt: updatedAt);

HomestayBooking _stay({String id = 'hb', String paymentId = 'pay_2', int updatedAt = 0,
        String refundId = '', int refundAmount = 0}) =>
    HomestayBooking(id: id, guestId: 'u', hostId: 'h', homeName: "Meera's Home", hostName: 'Meera',
        petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 8, 10), checkOut: DateTime(2026, 8, 13), nights: 3,
        subtotal: 2700, fee: 150, total: 2850, status: 'paid',
        paymentId: paymentId, refundId: refundId, refundAmount: refundAmount, updatedAt: updatedAt);

void main() {
  test('keeps only paid records (paymentId set) and drops unpaid ones', () {
    final records = PaymentRecord.from(
      services: [_service(id: 'paid'), _service(id: 'unpaid', paymentId: '')],
      stays: [_stay(id: 'paidStay'), _stay(id: 'unpaidStay', paymentId: '')],
    );
    expect(records.map((r) => r.id), containsAll(['paid', 'paidStay']));
    expect(records.any((r) => r.id == 'unpaid'), isFalse);
    expect(records.any((r) => r.id == 'unpaidStay'), isFalse);
  });

  test('sorts newest payment first by paidAt', () {
    final records = PaymentRecord.from(
      services: [_service(id: 'old', updatedAt: 1000)],
      stays: [_stay(id: 'new', updatedAt: 5000)],
    );
    expect(records.first.id, 'new');
    expect(records.last.id, 'old');
  });

  test('maps a service booking to a receipt shape', () {
    final r = PaymentRecord.from(services: [_service()], stays: []).single;
    expect(r.kind, PaymentKind.service);
    expect(r.title, 'Aarav Sharma');
    expect(r.subtitle, 'Dog Walker · Bruno');
    expect(r.total, 275);
    expect(r.booking, isNotNull);
    expect(r.isRefunded, isFalse);
  });

  test('maps a stay and surfaces refund info', () {
    final r = PaymentRecord.from(services: [],
        stays: [_stay(refundId: 're_1', refundAmount: 2700)]).single;
    expect(r.kind, PaymentKind.homestay);
    expect(r.subtitle, '3 nights · Bruno');
    expect(r.isRefunded, isTrue);
    expect(r.refundAmount, 2700);
  });

  test('falls back to createdAt when updatedAt is 0', () {
    final b = Booking(id: 'b', parentId: 'u', proId: 'p', proName: 'X', petId: 'p1', petName: 'B',
        serviceType: ServiceType.walker, rate: 100, fee: 10, total: 110, dateLabel: 'd',
        timeSlot: 't', status: 'confirmed', paymentId: 'pay', createdAt: 777, updatedAt: 0);
    expect(PaymentRecord.from(services: [b], stays: []).single.paidAtMillis, 777);
  });

  test('formats a real date-time and blanks a missing one', () {
    // 2026-07-23 16:32 local
    final millis = DateTime(2026, 7, 23, 16, 32).millisecondsSinceEpoch;
    expect(PaymentRecord.fmtDateTime(millis), '23 Jul 2026, 4:32 PM');
    expect(PaymentRecord.fmtDateTime(0), '');
  });
}
