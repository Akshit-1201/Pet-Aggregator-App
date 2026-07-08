import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/pet_profile.dart';
import '../pet_repository.dart';

class FirestorePetRepository implements PetRepository {
  final FirebaseFirestore _db;
  FirestorePetRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('pets');

  @override
  Stream<List<PetProfile>> watchNearbyPets({required String excludeOwnerId}) =>
      _col.orderBy('createdAt', descending: true).snapshots().map((snap) => snap.docs
          .map((d) => PetProfile.fromMap(d.id, d.data()))
          .where((p) => p.ownerId != excludeOwnerId)
          .toList());

  @override
  Stream<List<PetProfile>> watchMyPets(String ownerId) => _col
      .where('ownerId', isEqualTo: ownerId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => PetProfile.fromMap(d.id, d.data())).toList());

  @override
  Future<void> addPet(PetProfile pet) => _col.add({
        ...pet.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
}
