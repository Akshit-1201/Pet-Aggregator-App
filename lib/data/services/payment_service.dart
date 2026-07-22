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

enum PaymentKind { service, homestay }

abstract interface class PaymentService {
  /// Pays for an EXISTING booking. The server prices it and writes the paid
  /// state — the client never supplies an amount.
  Future<PaymentResult> payForBooking({
    required String bookingId,
    required PaymentKind kind,
    required String description,
    void Function()? onVerifying,
  });

  Future<RefundResult> refundStay({required String bookingId});
}
