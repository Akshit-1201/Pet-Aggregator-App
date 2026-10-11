import '../models/availability.dart';
import '../models/booking.dart';

/// Someone else holds or has booked an overlapping time with this pro.
class SlotTakenException implements Exception {
  const SlotTakenException();
  @override
  String toString() => 'SlotTakenException';
}

abstract interface class BookingRepository {
  Future<Booking> createBooking(Booking booking);
  Stream<List<Booking>> watchMyBookings(String parentId);
  Stream<List<Booking>> watchBookingsForPro(String proId);
  Future<void> cancelBooking(String id);

  /// Times already taken on [proId]'s day [isoDate] (yyyy-MM-dd): confirmed
  /// bookings and other customers' live holds.
  Stream<List<BusySlot>> watchBusySlots(String proId, String isoDate);

  /// Reserves a pending booking's slot for a short window while the customer
  /// pays. Throws [SlotTakenException] if the time is no longer free.
  Future<void> holdSlot(String bookingId);
}
