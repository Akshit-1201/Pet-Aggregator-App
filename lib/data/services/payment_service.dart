class PaymentResult {
  final String paymentId, orderId;
  const PaymentResult({required this.paymentId, required this.orderId});
}

enum PaymentErrorType {
  cancelled,
  failed,
  unverified,

  /// Service bookings only: the chosen time went to someone else before any
  /// money moved (caught when the order was created). Nothing was charged.
  slotTaken,

  /// Service bookings only: the time went to someone else while this payment
  /// was in flight. The server cancelled the booking and refunded in full.
  slotTakenRefunded,
}

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

  /// Cancels a PAID booking and refunds it. The server owns both the amount and
  /// the cancellation write — a client cannot cancel a paid booking directly,
  /// which is what stops a cancellation silently keeping the customer's money.
  Future<RefundResult> refundBooking({
    required String bookingId,
    required PaymentKind kind,
  });
}
