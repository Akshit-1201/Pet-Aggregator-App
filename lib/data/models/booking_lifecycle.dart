// Derived booking phases + permissions. Pure: no SDK imports, `now` injected.
// Only human decisions are ever stored ('accepted'/'declined'/'cancelled');
// 'completed' and 'expired' exist only here, derived from calendar dates.
import 'booking.dart';
import 'homestay_booking.dart';

enum BookingPhase {
  pending('Pending'),
  awaitingPayment('Awaiting payment'),
  upcoming('Upcoming'),
  completed('Completed'),
  declined('Declined'),
  cancelled('Cancelled'),
  expired('Expired');

  final String label;
  const BookingPhase(this.label);
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

BookingPhase servicePhase(Booking b, DateTime now) {
  if (b.status == 'cancelled') return BookingPhase.cancelled;
  final d = DateTime.tryParse(b.date);
  if (d == null) return BookingPhase.completed; // legacy: no machine date, grandfathered
  return _day(d).isBefore(_day(now)) ? BookingPhase.completed : BookingPhase.upcoming;
}

BookingPhase stayPhase(HomestayBooking b, DateTime now) {
  switch (b.status) {
    case 'declined':
      return BookingPhase.declined;
    case 'cancelled':
      return BookingPhase.cancelled;
    case 'paid':
      return _day(b.checkOut).isBefore(_day(now)) ? BookingPhase.completed : BookingPhase.upcoming;
    case 'accepted':
      return _day(b.checkIn).isBefore(_day(now)) ? BookingPhase.expired : BookingPhase.awaitingPayment;
    default: // 'requested'
      return _day(b.checkIn).isBefore(_day(now)) ? BookingPhase.expired : BookingPhase.pending;
  }
}

bool canRate(BookingPhase p) => p == BookingPhase.completed;

bool canCancelService(Booking b, DateTime now) {
  final d = DateTime.tryParse(b.date);
  return b.status == 'confirmed' && d != null && _day(now).isBefore(_day(d));
}

bool canCancelStay(HomestayBooking b, DateTime now) =>
    (b.status == 'requested' && !_day(b.checkIn).isBefore(_day(now))) ||
    (b.status == 'accepted' && _day(now).isBefore(_day(b.checkIn)));

bool canPay(HomestayBooking b, DateTime now) =>
    b.status == 'accepted' && !_day(b.checkIn).isBefore(_day(now));

bool canCancelPaidStay(HomestayBooking b, DateTime now) =>
    b.status == 'paid' && now.isBefore(b.checkIn);

bool canDecide(HomestayBooking b, DateTime now) =>
    b.status == 'requested' && !_day(b.checkIn).isBefore(_day(now));
