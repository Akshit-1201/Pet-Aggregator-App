import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';

void main() {
  test('payForBooking takes a bookingId + kind and records both', () async {
    final fake = FakePaymentService.success();
    final r = await fake.payForBooking(
        bookingId: 'bk1', kind: PaymentKind.service, description: 'Dog Walker');
    expect(r.paymentId, 'pay_fake123');
    expect(fake.paidBookingIds, ['bk1']);
    expect(fake.paidKinds, [PaymentKind.service]);
  });

  test('homestay kind is recorded too', () async {
    final fake = FakePaymentService.success();
    await fake.payForBooking(
        bookingId: 'hb1', kind: PaymentKind.homestay, description: 'Meera\'s Home');
    expect(fake.paidBookingIds, ['hb1']);
    expect(fake.paidKinds, [PaymentKind.homestay]);
  });
}
