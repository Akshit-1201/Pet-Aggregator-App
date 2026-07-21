// test/data/refund_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';

void main() {
  test('FakePaymentService.refundStay returns the configured result + records the id', () async {
    final fake = FakePaymentService(
        refundResult: const RefundResult(refundAmount: 2700, refundId: 'rfnd_1'));
    final r = await fake.refundStay(bookingId: 'hb1');
    expect(r.refundAmount, 2700);
    expect(r.refundId, 'rfnd_1');
    expect(fake.refundedBookingIds, ['hb1']);
  });

  test('default fake refund is a 0-refund cancel', () async {
    final r = await FakePaymentService().refundStay(bookingId: 'hb1');
    expect(r.refundAmount, 0);
    expect(r.refundId, '');
  });

  test('a configured refund error is thrown and still records the attempt', () async {
    final fake = FakePaymentService(
        refundError: const PaymentException(PaymentErrorType.failed, 'refund-failed'));
    await expectLater(fake.refundStay(bookingId: 'hb1'),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', 'refund-failed')));
    expect(fake.refundedBookingIds, ['hb1']);
  });
}
