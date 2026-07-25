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
import 'block_repository.dart';
import 'report_repository.dart';
import 'push_token_repository.dart';
import 'verification_repository.dart';
import '../models/verification_request.dart';
import 'payout_repository.dart';
import '../models/payout_account.dart';
import 'storage_repository.dart';
import '../services/push_service.dart';
import '../services/image_picker_service.dart';
import '../services/payment_service.dart';
import '../services/razorpay_payment_service.dart';
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
import 'firebase/firestore_block_repository.dart';
import 'firebase/firestore_report_repository.dart';
import 'firebase/firestore_push_token_repository.dart';
import 'firebase/firestore_verification_repository.dart';
import 'firebase/firestore_payout_repository.dart';
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

// Filtered here rather than in discoverDeckProvider so the Nearby map drops
// blocked owners' pets too — both surfaces derive from this one.
final nearbyPetsProvider = StreamProvider<List<PetProfile>>((ref) {
  final user = ref.watch(authStateProvider).value;
  final blocked = ref.watch(blockedUidsProvider).value ?? const <String>{};
  return ref.watch(petRepositoryProvider)
      .watchNearbyPets(excludeOwnerId: user?.uid ?? '__none__')
      .map((pets) => pets.where((p) => !blocked.contains(p.ownerId)).toList());
});

final blockRepositoryProvider = Provider<BlockRepository>((ref) => FirestoreBlockRepository());
final reportRepositoryProvider = Provider<ReportRepository>((ref) => FirestoreReportRepository());
final payoutRepositoryProvider =
    Provider<PayoutRepository>((ref) => FirestorePayoutRepository());

final myPayoutAccountProvider = StreamProvider<PayoutAccount?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(payoutRepositoryProvider).watchMyAccount(user.uid);
});

final myPayoutsProvider = StreamProvider<List<Payout>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(payoutRepositoryProvider).watchMyPayouts(user.uid);
});

/// Totals for the earnings card. Empty (not an error) while loading, so a slow
/// read shows ₹0 rather than a broken card.
final myEarningsProvider = Provider<EarningsSummary>((ref) =>
    EarningsSummary.from(ref.watch(myPayoutsProvider).value ?? const []));

final verificationRepositoryProvider =
    Provider<VerificationRepository>((ref) => FirestoreVerificationRepository());

/// The signed-in partner's own KYC application, or null if they've never
/// applied. Only ever their own — the rules deny reading anyone else's.
final myVerificationRequestProvider = StreamProvider<VerificationRequest?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(verificationRepositoryProvider).watchMyRequest(user.uid);
});

final pushServiceProvider = Provider<PushService>((ref) => FirebasePushService());
final pushTokenRepositoryProvider =
    Provider<PushTokenRepository>((ref) => FirestorePushTokenRepository());

/// Uids the signed-in user has blocked. Every surface that renders other users'
/// content filters against this, so a block hides them app-wide rather than only
/// in the place it was applied. Empty (never null) while loading or signed out,
/// so a slow read fails open on visibility rather than blanking the feed.
final blockedUidsProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(<String>{});
  return ref.watch(blockRepositoryProvider).watchBlockedUids(user.uid);
});

/// Blocked users with their names, for the Settings list.
final blockedListProvider = StreamProvider<List<({String uid, String name})>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(blockRepositoryProvider).watchBlocked(user.uid);
});

final swipeRepositoryProvider = Provider<SwipeRepository>((ref) => FirestoreSwipeRepository());

final swipedPetIdsProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(<String>{});
  return ref.watch(swipeRepositoryProvider).watchSwipedPetIds(user.uid);
});

final discoverDeckProvider = Provider<AsyncValue<List<PetProfile>>>((ref) {
  final swiped = ref.watch(swipedPetIdsProvider).value ?? const <String>{};
  // Blocked owners are already gone — nearbyPetsProvider filters them.
  return ref.watch(nearbyPetsProvider).whenData(
      (pets) => pets.where((p) => !swiped.contains(p.id)).toList());
});

final proRepositoryProvider = Provider<ProRepository>((ref) => FirestoreProRepository());

final prosProvider = StreamProvider<List<Pro>>((ref) {
  final blocked = ref.watch(blockedUidsProvider).value ?? const <String>{};
  return ref.watch(proRepositoryProvider).watchPros()
      .map((pros) => pros.where((p) => !blocked.contains(p.uid)).toList());
});

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

final homestaysProvider = StreamProvider<List<Homestay>>((ref) {
  final blocked = ref.watch(blockedUidsProvider).value ?? const <String>{};
  return ref.watch(homestayRepositoryProvider).watchHomestays()
      .map((homes) => homes.where((h) => !blocked.contains(h.uid)).toList());
});

final currentHomestayProvider = StreamProvider<Homestay?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(homestayRepositoryProvider).watchHomestay(user.uid);
});

final homestayBookingRepositoryProvider =
    Provider<HomestayBookingRepository>((ref) => FirestoreHomestayBookingRepository());

final postRepositoryProvider = Provider<PostRepository>((ref) => FirestorePostRepository());

final postsProvider = StreamProvider<List<Post>>((ref) {
  final blocked = ref.watch(blockedUidsProvider).value ?? const <String>{};
  return ref.watch(postRepositoryProvider).watchPosts()
      .map((posts) => posts.where((p) => !blocked.contains(p.authorId)).toList());
});

final commentsProvider = StreamProvider.autoDispose.family<List<Comment>, String>((ref, postId) {
  final blocked = ref.watch(blockedUidsProvider).value ?? const <String>{};
  return ref.watch(postRepositoryProvider).watchComments(postId)
      .map((comments) => comments.where((c) => !blocked.contains(c.authorId)).toList());
});

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
  final blocked = ref.watch(blockedUidsProvider).value ?? const <String>{};
  return ref.watch(chatRepositoryProvider).watchMyChats(user.uid)
      .map((chats) => chats.where((c) => !blocked.contains(c.otherUid(user.uid))).toList());
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

final receivedServiceBookingsProvider = StreamProvider<List<Booking>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null || ref.watch(currentProProvider).value == null) {
    return Stream.value(const []);
  }
  return ref.watch(bookingRepositoryProvider).watchBookingsForPro(user.uid);
});

final receivedStayBookingsProvider = StreamProvider<List<HomestayBooking>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null || ref.watch(currentHomestayProvider).value == null) {
    return Stream.value(const []);
  }
  return ref.watch(homestayBookingRepositoryProvider).watchBookingsForHost(user.uid);
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
    receivedBookings: ref.watch(receivedServiceBookingsProvider).value ?? const [],
    receivedStays: ref.watch(receivedStayBookingsProvider).value ?? const [],
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

final paymentServiceProvider =
    Provider<PaymentService>((ref) => RazorpayPaymentService());
