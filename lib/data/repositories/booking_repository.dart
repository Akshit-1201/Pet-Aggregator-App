import '../models/booking.dart';

abstract interface class BookingRepository {
  Future<void> createBooking(Booking booking);
  Stream<List<Booking>> watchMyBookings(String parentId);
}
