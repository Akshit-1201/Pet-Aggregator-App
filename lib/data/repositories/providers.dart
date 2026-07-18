import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/booking.dart';
import '../models/pet_profile.dart';
import '../models/user_profile.dart';
import '../models/pro.dart';
import '../models/homestay.dart';
import '../models/homestay_booking.dart';
import '../models/post.dart';
import '../models/chat.dart';
import '../models/review.dart';
import '../../features/notifications/notification_item.dart';
import 'auth_repository.dart';
import 'booking_repository.dart';
import 'user_repository.dart';
import 'pet_repository.dart';
import 'pro_repository.dart';
import 'homestay_repository.dart';
import 'homestay_booking_repository.dart';
import 'swipe_repository.dart';
import 'post_repository.dart';
import 'chat_repository.dart';
import 'preferences_repository.dart';
import 'review_repository.dart';
import 'storage_repository.dart';
import '../services/image_picker_service.dart';
import 'firebase/firebase_auth_repository.dart';
import 'firebase/firestore_user_repository.dart';
import 'firebase/firestore_pet_repository.dart';
import 'firebase/firestore_pro_repository.dart';
import 'firebase/firestore_homestay_repository.dart';
import 'firebase/firestore_homestay_booking_repository.dart';
import 'firebase/firestore_swipe_repository.dart';
import 'firebase/firestore_booking_repository.dart';
import 'firebase/firestore_post_repository.dart';
import 'firebase/firestore_chat_repository.dart';
import 'firebase/firestore_review_repository.dart';
import 'firebase/firebase_storage_repository.dart';

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

final commentsProvider = StreamProvider.autoDispose.family<List<Comment>, String>(
    (ref, postId) => ref.watch(postRepositoryProvider).watchComments(postId));

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
    (ref) => throw UnimplementedError('preferencesRepositoryProvider must be overridden in main()'));

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(preferencesRepositoryProvider).themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await ref.read(preferencesRepositoryProvider).setThemeMode(mode);
  }

  Future<void> toggleDark(bool on) => setThemeMode(on ? ThemeMode.dark : ThemeMode.light);
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

final myWoofCountProvider = StreamProvider<int>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(0);
  return ref.watch(swipeRepositoryProvider).watchMyWoofCount(user.uid);
});

final myBookingsProvider = StreamProvider<List<Booking>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(bookingRepositoryProvider).watchMyBookings(user.uid);
});

final userByIdProvider = StreamProvider.family<UserProfile?, String>(
    (ref, uid) => ref.watch(userRepositoryProvider).watchUser(uid));

final chatRepositoryProvider = Provider<ChatRepository>((ref) => FirestoreChatRepository());

final myChatsProvider = StreamProvider<List<Chat>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(chatRepositoryProvider).watchMyChats(user.uid);
});

final chatMessagesProvider = StreamProvider.autoDispose.family<List<Message>, String>(
    (ref, chatId) => ref.watch(chatRepositoryProvider).watchMessages(chatId));

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) => FirestoreReviewRepository());

final reviewsProvider = StreamProvider.autoDispose.family<List<Review>, String>(
    (ref, targetId) => ref.watch(reviewRepositoryProvider).watchReviews(targetId));

final myReviewedBookingIdsProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const {});
  return ref.watch(reviewRepositoryProvider).watchMyReviewedBookingIds(user.uid);
});

final myHomestayBookingsProvider = StreamProvider<List<HomestayBooking>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(homestayBookingRepositoryProvider).watchMyHomestayBookings(user.uid);
});

final notificationsProvider = Provider<List<NotificationItem>>((ref) {
  final uid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';
  final seenAt = ref.watch(currentUserProfileProvider).value?.notifsSeenAt ?? 0;
  return buildNotifications(
    myUid: uid,
    seenAt: seenAt,
    chats: ref.watch(myChatsProvider).value ?? const [],
    reviews: ref.watch(reviewsProvider(uid)).value ?? const [],
    bookings: ref.watch(myBookingsProvider).value ?? const [],
    homestays: ref.watch(myHomestayBookingsProvider).value ?? const [],
    myPro: ref.watch(currentProProvider).value,
    myHomestay: ref.watch(currentHomestayProvider).value,
  );
});

final hasUnreadNotificationsProvider =
    Provider<bool>((ref) => ref.watch(notificationsProvider).any((n) => !n.read));

final storageRepositoryProvider =
    Provider<StorageRepository>((ref) => FirebaseStorageRepository());

final imagePickerServiceProvider =
    Provider<ImagePickerService>((ref) => ImagePickerServiceImpl());
