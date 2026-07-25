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
  String? _bookingId;
  PaymentKind? _kind;

  @override
  Future<PaymentResult> payForBooking({
    required String bookingId,
    required PaymentKind kind,
    required String description,
    void Function()? onVerifying,
  }) async {
    if (_inFlight != null) {
      throw const PaymentException(PaymentErrorType.failed, 'busy');
    }
    // Claim the slot synchronously, before any await, so a re-entrant call
    // (e.g. a double-tap during order creation) is rejected as busy rather
    // than creating a second order and orphaning this completer.
    final completer = Completer<PaymentResult>();
    _inFlight = completer;
    _onVerifying = onVerifying;
    _bookingId = bookingId;
    _kind = kind;

    final Map<String, dynamic> order;
    try {
      final res = await _functions
          .httpsCallable('createBookingOrder')
          .call<Map<Object?, Object?>>({'kind': kind.name, 'bookingId': bookingId});
      order = Map<String, dynamic>.from(res.data);
    } catch (_) {
      _inFlight = null;
      _onVerifying = null;
      throw const PaymentException(PaymentErrorType.failed, 'order-failed');
    }

    final razorpay = Razorpay();
    try {
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
    } catch (_) {
      _finishError(razorpay, const PaymentException(PaymentErrorType.failed, 'open-failed'));
    }
    return completer.future;
  }

  Future<void> _verify(Razorpay razorpay, PaymentSuccessResponse r) async {
    _onVerifying?.call();
    final paymentId = r.paymentId ?? '';
    try {
      await _functions.httpsCallable('verifyBookingPayment').call<Map<Object?, Object?>>({
        'kind': _kind?.name,
        'bookingId': _bookingId,
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
    _bookingId = null;
    _kind = null;
    if (c != null && !c.isCompleted) c.complete(result);
  }

  void _finishError(Razorpay razorpay, PaymentException e) {
    razorpay.clear();
    final c = _inFlight;
    _inFlight = null;
    _onVerifying = null;
    _bookingId = null;
    _kind = null;
    if (c != null && !c.isCompleted) c.completeError(e);
  }

  @override
  Future<RefundResult> refundBooking({
    required String bookingId,
    required PaymentKind kind,
  }) async {
    try {
      final res = await _functions
          .httpsCallable('refundBookingPayment')
          .call<Map<Object?, Object?>>({
        'bookingId': bookingId,
        'kind': kind == PaymentKind.service ? 'service' : 'homestay',
      });
      final data = Map<String, dynamic>.from(res.data);
      return RefundResult(
          refundAmount: (data['refundAmount'] ?? 0) as int,
          refundId: (data['refundId'] ?? '') as String);
    } on FirebaseFunctionsException catch (e) {
      // Pre-claim codes are provably "nothing happened" (the transaction never
      // committed). An explicit 'refund-failed' means the booking WAS cancelled
      // but the refund did not go through. Anything else (unavailable,
      // deadline-exceeded, unknown...) is ambiguous — never claim either way.
      const preClaim = {
        'unauthenticated', 'invalid-argument', 'not-found',
        'permission-denied', 'failed-precondition',
      };
      if (preClaim.contains(e.code)) {
        throw const PaymentException(PaymentErrorType.failed, 'cancel-failed');
      }
      throw PaymentException(PaymentErrorType.failed,
          e.message == 'refund-failed' ? 'refund-failed' : 'unconfirmed');
    } catch (_) {
      // e.g. decoding a 200 response failed — the refund may well have succeeded.
      throw const PaymentException(PaymentErrorType.failed, 'unconfirmed');
    }
  }
}
