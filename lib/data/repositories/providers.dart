import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/pet_profile.dart';
import '../models/user_profile.dart';
import '../models/pro.dart';
import '../models/homestay.dart';
import '../models/post.dart';
import 'auth_repository.dart';
import 'booking_repository.dart';
import 'user_repository.dart';
import 'pet_repository.dart';
import 'pro_repository.dart';
import 'homestay_repository.dart';
import 'homestay_booking_repository.dart';
import 'swipe_repository.dart';
import 'post_repository.dart';
import 'firebase/firebase_auth_repository.dart';
import 'firebase/firestore_user_repository.dart';
import 'firebase/firestore_pet_repository.dart';
import 'firebase/firestore_pro_repository.dart';
import 'firebase/firestore_homestay_repository.dart';
import 'firebase/firestore_homestay_booking_repository.dart';
import 'firebase/firestore_swipe_repository.dart';
import 'firebase/firestore_booking_repository.dart';
import 'firebase/firestore_post_repository.dart';

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

final swipeRepositoryProvider = Provider<SwipeRepository>((ref) => FirestoreSwipeRepository());

final swipedPetIdsProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(<String>{});
  return ref.watch(swipeRepositoryProvider).watchSwipedPetIds(user.uid);
});

final discoverDeckProvider = Provider<AsyncValue<List<PetProfile>>>((ref) {
  final swiped = ref.watch(swipedPetIdsProvider).value ?? const <String>{};
  return ref.watch(nearbyPetsProvider).whenData(
      (pets) => pets.where((p) => !swiped.contains(p.id)).toList());
});

final proRepositoryProvider = Provider<ProRepository>((ref) => FirestoreProRepository());

final prosProvider = StreamProvider<List<Pro>>((ref) => ref.watch(proRepositoryProvider).watchPros());

final currentProProvider = StreamProvider<Pro?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(proRepositoryProvider).watchPro(user.uid);
});

final bookingRepositoryProvider =
    Provider<BookingRepository>((ref) => FirestoreBookingRepository());

final myPetsProvider = StreamProvider<List<PetProfile>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(petRepositoryProvider).watchMyPets(user.uid);
});

final homestayRepositoryProvider =
    Provider<HomestayRepository>((ref) => FirestoreHomestayRepository());

final homestaysProvider =
    StreamProvider<List<Homestay>>((ref) => ref.watch(homestayRepositoryProvider).watchHomestays());

final currentHomestayProvider = StreamProvider<Homestay?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(homestayRepositoryProvider).watchHomestay(user.uid);
});

final homestayBookingRepositoryProvider =
    Provider<HomestayBookingRepository>((ref) => FirestoreHomestayBookingRepository());

final postRepositoryProvider = Provider<PostRepository>((ref) => FirestorePostRepository());

final postsProvider = StreamProvider<List<Post>>((ref) => ref.watch(postRepositoryProvider).watchPosts());

final commentsProvider = StreamProvider.family<List<Comment>, String>(
    (ref, postId) => ref.watch(postRepositoryProvider).watchComments(postId));
