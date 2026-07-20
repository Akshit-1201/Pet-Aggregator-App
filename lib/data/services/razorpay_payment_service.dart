// lib/data/services/razorpay_payment_service.dart
//
// The ONLY file allowed to import razorpay_flutter and cloud_functions.
// Flow: createBookingOrder (callable) -> Razorpay Checkout -> on success
// verifyBookingPayment (callable) -> PaymentResult. Cancel/failed mean
// "not charged"; unverified means the gateway succeeded but verification
// didn't - it carries the paymentId and must never be conflated with failed.
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'payment_service.dart';

class RazorpayPaymentService implements PaymentService {
  final FirebaseFunctions _functions;
  RazorpayPaymentService([FirebaseFunctions? functions])
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  Completer<PaymentResult>? _inFlight;
  void Function()? _onVerifying;

  @override
  Future<PaymentResult> payForBooking({
    required int amountRupees,
    required String description,
    void Function()? onVerifying,
  }) async {
    if (_inFlight != null) {
      throw const PaymentException(PaymentErrorType.failed, 'busy');
    }
    final Map<String, dynamic> order;
    try {
      final res = await _functions
          .httpsCallable('createBookingOrder')
          .call<Map<Object?, Object?>>({'amountRupees': amountRupees});
      order = Map<String, dynamic>.from(res.data);
    } catch (_) {
      throw const PaymentException(PaymentErrorType.failed, 'order-failed');
    }

    final completer = Completer<PaymentResult>();
    _inFlight = completer;
    _onVerifying = onVerifying;
    final razorpay = Razorpay();
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS,
        (PaymentSuccessResponse r) => _verify(razorpay, r));
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      _finishError(
          razorpay,
          r.code == Razorpay.PAYMENT_CANCELLED
              ? const PaymentException(PaymentErrorType.cancelled, 'cancelled')
              : PaymentException(PaymentErrorType.failed, r.message ?? 'failed'));
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      _finishError(razorpay,
          const PaymentException(PaymentErrorType.failed, 'external-wallet-unsupported'));
    });
    razorpay.open({
      'key': order['keyId'],
      'order_id': order['orderId'],
      'amount': order['amountPaise'],
      'currency': 'INR',
      'name': 'Pawgo',
      'description': description,
      'theme': {'color': '#F59E2E'},
    });
    return completer.future;
  }

  Future<void> _verify(Razorpay razorpay, PaymentSuccessResponse r) async {
    _onVerifying?.call();
    final paymentId = r.paymentId ?? '';
    try {
      await _functions.httpsCallable('verifyBookingPayment').call<Map<Object?, Object?>>({
        'orderId': r.orderId,
        'paymentId': r.paymentId,
        'signature': r.signature,
      });
      _finish(razorpay,
          result: PaymentResult(paymentId: paymentId, orderId: r.orderId ?? ''));
    } catch (_) {
      _finishError(
          razorpay,
          PaymentException(PaymentErrorType.unverified, 'verification-failed',
              paymentId: paymentId));
    }
  }

  void _finish(Razorpay razorpay, {required PaymentResult result}) {
    razorpay.clear();
    final c = _inFlight;
    _inFlight = null;
    _onVerifying = null;
    if (c != null && !c.isCompleted) c.complete(result);
  }

  void _finishError(Razorpay razorpay, PaymentException e) {
    razorpay.clear();
    final c = _inFlight;
    _inFlight = null;
    _onVerifying = null;
    if (c != null && !c.isCompleted) c.completeError(e);
  }
}
