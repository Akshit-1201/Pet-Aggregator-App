import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/availability.dart';
import '../../models/booking.dart';
import '../booking_repository.dart';

class FirestoreBookingRepository implements BookingRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions? _fns;
  FirestoreBookingRepository([FirebaseFirestore? db, FirebaseFunctions? functions])
      : _db = db ?? FirebaseFirestore.instance,
        _fns = functions;

  FirebaseFunctions get _functions =>
      _fns ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  @override
  Stream<List<BusySlot>> watchBusySlots(String proId, String isoDate) => _db
      .collection('proSchedule')
      .doc('${proId}_$isoDate')
      .snapshots()
      .map((s) => busySlotsFrom(s.data(), nowMs: DateTime.now().millisecondsSinceEpoch));

  @override
  Future<void> holdSlot(String bookingId) async {
    try {
      await _functions.httpsCallable('holdServiceSlot').call<Object?>({'bookingId': bookingId});
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists') throw const SlotTakenException();
      rethrow;
    }
  }

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
