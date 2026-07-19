import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/homestay_booking.dart';
import '../homestay_booking_repository.dart';

class FirestoreHomestayBookingRepository implements HomestayBookingRepository {
  final FirebaseFirestore _db;
  FirestoreHomestayBookingRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('homestayBookings');

  @override
  Future<void> createHomestayBooking(HomestayBooking booking) {
    final map = booking.toMap();
    if ((map['createdAt'] ?? 0) == 0) map['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    return _col.add(map);
  }

  @override
  Stream<List<HomestayBooking>> watchMyHomestayBookings(String guestId) => _col
      .where('guestId', isEqualTo: guestId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => HomestayBooking.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<HomestayBooking>> watchBookingsForHost(String hostId) => _col
      .where('hostId', isEqualTo: hostId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => HomestayBooking.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  Future<void> _setStatus(String id, String status) => _col.doc(id).update({
        'status': status,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

  @override
  Future<void> acceptRequest(String id) => _setStatus(id, 'accepted');

  @override
  Future<void> declineRequest(String id) => _setStatus(id, 'declined');

  @override
  Future<void> cancelStay(String id) => _setStatus(id, 'cancelled');
}
