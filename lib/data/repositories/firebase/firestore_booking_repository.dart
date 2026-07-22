import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/booking.dart';
import '../booking_repository.dart';

class FirestoreBookingRepository implements BookingRepository {
  final FirebaseFirestore _db;
  FirestoreBookingRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('bookings');

  @override
  Future<Booking> createBooking(Booking booking) async {
    final map = booking.toMap();
    if ((map['createdAt'] ?? 0) == 0) map['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    map['status'] = 'pending'; // paid state is server-written (verifyBookingPayment)
    final doc = await _col.add(map);
    return Booking.fromMap(doc.id, map);
  }

  @override
  Stream<List<Booking>> watchMyBookings(String parentId) => _col
      .where('parentId', isEqualTo: parentId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Booking.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Booking>> watchBookingsForPro(String proId) => _col
      .where('proId', isEqualTo: proId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Booking.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Future<void> cancelBooking(String id) => _col.doc(id).update({
        'status': 'cancelled',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
}
