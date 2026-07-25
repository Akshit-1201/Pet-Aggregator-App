// test/data/refund_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';

void main() {
  test('FakePaymentService.refundBooking returns the configured result + records the id',
      () async {
    final fake = FakePaymentService(
        refundResult: const RefundResult(refundAmount: 2700, refundId: 'rfnd_1'));
    final r = await fake.refundBooking(bookingId: 'hb1', kind: PaymentKind.homestay);
    expect(r.refundAmount, 2700);
    expect(r.refundId, 'rfnd_1');
    expect(fake.refundedBookingIds, ['hb1']);
  });

  test('the kind is carried through — the server picks a different collection per kind',
      () async {
    final fake = FakePaymentService();
    await fake.refundBooking(bookingId: 'b1', kind: PaymentKind.service);
    await fake.refundBooking(bookingId: 'hb1', kind: PaymentKind.homestay);
    expect(fake.refundedKinds, [PaymentKind.service, PaymentKind.homestay]);
  });

  test('default fake refund is a 0-refund cancel', () async {
    final r =
        await FakePaymentService().refundBooking(bookingId: 'hb1', kind: PaymentKind.homestay);
    expect(r.refundAmount, 0);
    expect(r.refundId, '');
  });

  test('a configured refund error is thrown and still records the attempt', () async {
    final fake = FakePaymentService(
        refundError: const PaymentException(PaymentErrorType.failed, 'refund-failed'));
    await expectLater(fake.refundBooking(bookingId: 'hb1', kind: PaymentKind.homestay),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', 'refund-failed')));
    expect(fake.refundedBookingIds, ['hb1']);
  });
}
