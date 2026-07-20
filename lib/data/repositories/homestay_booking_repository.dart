import '../models/homestay_booking.dart';

abstract interface class HomestayBookingRepository {
  Future<void> createHomestayBooking(HomestayBooking booking);
  Stream<List<HomestayBooking>> watchMyHomestayBookings(String guestId);
  Stream<List<HomestayBooking>> watchBookingsForHost(String hostId);
  Future<void> acceptRequest(String id);
  Future<void> declineRequest(String id);
  Future<void> cancelStay(String id);
  Future<void> markPaid(String id, String paymentId);
}
