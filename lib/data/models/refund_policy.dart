import 'booking.dart';
import 'homestay_booking.dart';

/// Refund (rupees, on the subtotal — the ₹150 service fee is never refundable)
/// for cancelling [b] at [now]. Display-only on the client; refundBookingPayment
/// recomputes this authoritatively server-side. Policy: 100% of subtotal if
/// cancelling >= 24h before check-in, else 0.
int refundRupees(HomestayBooking b, DateTime now) {
  if (!now.isBefore(b.checkIn)) return 0; // at or after check-in
  return b.checkIn.difference(now).inHours >= 24 ? b.subtotal : 0;
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Refund for cancelling a paid service booking — the pro's rate, never the
/// Pawgo fee. Display-only; the server recomputes it.
///
/// Policy: full refund while the service day is still ahead, nothing once it
/// has arrived. Deliberately day-granular rather than a 24-hour rule, because
/// a service booking stores a **date only** — an hour-precise policy would be
/// fake precision, and measuring 24h from IST midnight would quietly require
/// two days' notice.
int serviceRefundRupees(Booking b, DateTime now) {
  final d = DateTime.tryParse(b.date);
  if (d == null) return 0; // legacy booking with no machine-readable date
  return _day(now).isBefore(_day(d)) ? b.rate : 0;
}
