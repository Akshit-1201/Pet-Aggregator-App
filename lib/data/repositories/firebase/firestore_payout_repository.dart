import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/payout_account.dart';
import '../payout_repository.dart';

class FirestorePayoutRepository implements PayoutRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  FirestorePayoutRepository([FirebaseFirestore? db, FirebaseFunctions? functions])
      : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  @override
  Stream<PayoutAccount?> watchMyAccount(String uid) =>
      _db.collection('payoutAccounts').doc(uid).snapshots().map(
          (doc) => doc.exists ? PayoutAccount.fromMap(uid, doc.data()!) : null);

  @override
  Stream<List<Payout>> watchMyPayouts(String uid) => _db
      .collection('payouts')
      .where('partnerId', isEqualTo: uid)
      .snapshots()
      // Sorted client-side to avoid a composite index; a partner's payout count
      // stays small.
      .map((snap) => snap.docs.map((d) => Payout.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Future<void> createAccount({
    required String name,
    required String email,
    required String pan,
    required String accountNumber,
    required String ifsc,
    required String beneficiaryName,
  }) async {
    try {
      await _functions.httpsCallable('createPayoutAccount').call<Map<String, dynamic>>({
        'name': name,
        'email': email,
        'pan': pan,
        'accountNumber': accountNumber,
        'ifsc': ifsc,
        'beneficiaryName': beneficiaryName,
      });
    } on FirebaseFunctionsException catch (e) {
      throw PayoutFailure.fromCode(e.message ?? '');
    }
  }
}
