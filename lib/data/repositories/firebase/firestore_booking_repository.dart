import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/booking.dart';
import '../booking_repository.dart';

class FirestoreBookingRepository implements BookingRepository {
  final FirebaseFirestore _db;
  FirestoreBookingRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('bookings');

  @override
  Future<void> createBooking(Booking booking) => _col.add({
        ...booking.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  @override
  Stream<List<Booking>> watchMyBookings(String parentId) => _col
      .where('parentId', isEqualTo: parentId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Booking.fromMap(d.id, d.data())).toList());
}
