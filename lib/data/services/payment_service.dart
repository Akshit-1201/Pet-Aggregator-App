class PaymentResult {
  final String paymentId, orderId;
  const PaymentResult({required this.paymentId, required this.orderId});
}

enum PaymentErrorType { cancelled, failed, unverified }

class PaymentException implements Exception {
  final PaymentErrorType type;
  final String message;
  final String paymentId; // set only for unverified (money may have moved)
  const PaymentException(this.type, this.message, {this.paymentId = ''});
}

class RefundResult {
  final int refundAmount; // rupees actually refunded (0 for the <24h path)
  final String refundId;  // '' when refundAmount == 0
  const RefundResult({required this.refundAmount, required this.refundId});
}

abstract interface class PaymentService {
  Future<PaymentResult> payForBooking({
    required int amountRupees,
    required String description,
    void Function()? onVerifying, // fires when the gateway succeeded and verification starts
  });

  Future<RefundResult> refundStay({required String bookingId});
}
