import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';

void main() {
  test('MockPetRepository returns the prototype pets', () {
    final pets = const MockPetRepository().nearbyPets();
    expect(pets.length, greaterThanOrEqualTo(3));
    expect(pets.first.name, 'Bruno');
  });
}
