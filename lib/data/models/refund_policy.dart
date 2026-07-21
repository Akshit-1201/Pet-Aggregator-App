import 'homestay_booking.dart';

/// Refund (rupees, on the subtotal — the ₹150 service fee is never refundable)
/// for cancelling [b] at [now]. Display-only on the client; refundBookingPayment
/// recomputes this authoritatively server-side. Policy: 100% of subtotal if
/// cancelling >= 24h before check-in, else 0.
int refundRupees(HomestayBooking b, DateTime now) {
  if (!now.isBefore(b.checkIn)) return 0; // at or after check-in
  return b.checkIn.difference(now).inHours >= 24 ? b.subtotal : 0;
}
