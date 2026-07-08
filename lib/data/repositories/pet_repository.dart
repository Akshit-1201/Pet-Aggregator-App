import '../models/pet_profile.dart';

abstract interface class PetRepository {
  Stream<List<PetProfile>> watchNearbyPets({required String excludeOwnerId});
  Stream<List<PetProfile>> watchMyPets(String ownerId);
  Future<void> addPet(PetProfile pet);
}
