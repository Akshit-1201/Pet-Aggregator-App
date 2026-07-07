import '../models/pet_profile.dart';
import '../mock/mock_pets.dart';

abstract interface class PetRepository {
  List<PetProfile> nearbyPets();
}

class MockPetRepository implements PetRepository {
  const MockPetRepository();
  @override
  List<PetProfile> nearbyPets() => mockPets;
}
