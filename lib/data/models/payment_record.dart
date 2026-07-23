import 'booking.dart';
import 'homestay_booking.dart';
import '../services/payment_service.dart' show PaymentKind;

export '../services/payment_service.dart' show PaymentKind;

/// A single completed payment, normalised from either a service [Booking] or a
/// [HomestayBooking] so the Payments screen can list both in one timeline and
/// render a receipt. Only *paid* transactions become records (see [from]).
class PaymentRecord {
  final PaymentKind kind;
  final String id;
  final String title; // pro name / home name
  final String subtitle; // "Dog Walker · Bruno" / "3 nights · Bruno"
  final int total; // rupees actually charged
  final int paidAtMillis; // when the payment was written (updatedAt, or createdAt)
  final String paymentId;

  /// The underlying record — exactly one is non-null, keyed by [kind]. The
  /// receipt screen reads it for the line-item breakdown.
  final Booking? booking;
  final HomestayBooking? stay;

  const PaymentRecord({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.total,
    required this.paidAtMillis,
    required this.paymentId,
    this.booking,
    this.stay,
  });

  bool get isRefunded => (stay?.refundId ?? '').isNotEmpty;
  int get refundAmount => stay?.refundAmount ?? 0;

  /// Build the payment timeline: every paid service booking and paid stay,
  /// newest payment first. A record counts as paid once it carries a
  /// `paymentId` (the server stamps it only after verifying the Razorpay
  /// signature), so unpaid/pending bookings never appear.
  static List<PaymentRecord> from({
    required List<Booking> services,
    required List<HomestayBooking> stays,
  }) {
    final out = <PaymentRecord>[];
    for (final b in services) {
      if (b.paymentId.isEmpty) continue;
      out.add(PaymentRecord(
        kind: PaymentKind.service,
        id: b.id,
        title: b.proName,
        subtitle: '${b.serviceType.label} · ${b.petName}',
        total: b.total,
        paidAtMillis: b.updatedAt != 0 ? b.updatedAt : b.createdAt,
        paymentId: b.paymentId,
        booking: b,
      ));
    }
    for (final s in stays) {
      if (s.paymentId.isEmpty) continue;
      out.add(PaymentRecord(
        kind: PaymentKind.homestay,
        id: s.id,
        title: s.homeName,
        subtitle: '${s.nights} night${s.nights == 1 ? '' : 's'} · ${s.petName}',
        total: s.total,
        paidAtMillis: s.updatedAt != 0 ? s.updatedAt : s.createdAt,
        paymentId: s.paymentId,
        stay: s,
      ));
    }
    out.sort((a, b) => b.paidAtMillis.compareTo(a.paidAtMillis));
    return out;
  }

  static const _months =
      ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// "23 Jul 2026, 4:32 PM" from epoch millis; "" when the timestamp is missing
  /// (0) — the receipt shows a dash rather than a bogus 1970 date.
  static String fmtDateTime(int millis) {
    if (millis == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final min = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year}, $h12:$min $ampm';
  }
}
