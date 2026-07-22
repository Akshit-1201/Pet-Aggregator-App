import '../models/booking.dart';

abstract interface class BookingRepository {
  Future<Booking> createBooking(Booking booking);
  Stream<List<Booking>> watchMyBookings(String parentId);
  Stream<List<Booking>> watchBookingsForPro(String proId);
  Future<void> cancelBooking(String id);
}
