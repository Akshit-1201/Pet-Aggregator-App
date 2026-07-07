import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pet_profile.dart';
import 'pet_repository.dart';

final petRepositoryProvider =
    Provider<PetRepository>((ref) => const MockPetRepository());

final nearbyPetsProvider =
    Provider<List<PetProfile>>((ref) => ref.watch(petRepositoryProvider).nearbyPets());
