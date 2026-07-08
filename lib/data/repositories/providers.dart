import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/pet_profile.dart';
import '../models/user_profile.dart';
import 'auth_repository.dart';
import 'user_repository.dart';
import 'pet_repository.dart';
import 'firebase/firebase_auth_repository.dart';
import 'firebase/firestore_user_repository.dart';
import 'firebase/firestore_pet_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => FirebaseAuthRepository());
final userRepositoryProvider = Provider<UserRepository>((ref) => FirestoreUserRepository());
final petRepositoryProvider = Provider<PetRepository>((ref) => FirestorePetRepository());

final authStateProvider = StreamProvider<AppUser?>(
    (ref) => ref.watch(authRepositoryProvider).authStateChanges());

final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watchUser(user.uid);
});

final nearbyPetsProvider = StreamProvider<List<PetProfile>>((ref) {
  final user = ref.watch(authStateProvider).value;
  return ref.watch(petRepositoryProvider).watchNearbyPets(excludeOwnerId: user?.uid ?? '__none__');
});
