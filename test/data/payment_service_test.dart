import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';

void main() {
  test('FakePaymentService.success returns the canned result, records amount, fires onVerifying', () async {
    final fake = FakePaymentService.success();
    var verifying = false;
    final r = await fake.payForBooking(
        amountRupees: 275, description: 'Dog Walker', onVerifying: () => verifying = true);
    expect(r.paymentId, 'pay_fake123');
    expect(r.orderId, 'order_fake123');
    expect(fake.chargedAmounts, [275]);
    expect(verifying, isTrue);
  });

  test('a configured error is thrown and still records the attempt', () async {
    final fake = FakePaymentService(
        error: const PaymentException(PaymentErrorType.cancelled, 'cancelled'));
    await expectLater(
        fake.payForBooking(amountRupees: 100, description: 'x'),
        throwsA(isA<PaymentException>()
            .having((e) => e.type, 'type', PaymentErrorType.cancelled)));
    expect(fake.chargedAmounts, [100]);
  });

  test('gate holds the payment in flight until completed', () async {
    final gate = Completer<PaymentResult>();
    final fake = FakePaymentService(gate: gate);
    final future = fake.payForBooking(amountRupees: 50, description: 'x');
    var done = false;
    unawaited(future.then((_) => done = true));
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    gate.complete(const PaymentResult(paymentId: 'pay_g', orderId: 'order_g'));
    expect((await future).paymentId, 'pay_g');
  });
}
