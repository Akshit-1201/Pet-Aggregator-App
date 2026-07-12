import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/homestay_booking.dart';
import '../homestay_booking_repository.dart';

class FirestoreHomestayBookingRepository implements HomestayBookingRepository {
  final FirebaseFirestore _db;
  FirestoreHomestayBookingRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('homestayBookings');

  @override
  Future<void> createHomestayBooking(HomestayBooking booking) => _col.add({
        ...booking.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  @override
  Stream<List<HomestayBooking>> watchMyHomestayBookings(String guestId) => _col
      .where('guestId', isEqualTo: guestId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => HomestayBooking.fromMap(d.id, d.data())).toList());
}
