import '../models/homestay_booking.dart';

abstract interface class HomestayBookingRepository {
  Future<void> createHomestayBooking(HomestayBooking booking);
  Stream<List<HomestayBooking>> watchMyHomestayBookings(String guestId);
}
