import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/booking.dart';
import '../../data/models/chat.dart';
import '../../data/models/homestay.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/post.dart';
import '../../data/models/pro.dart';
import '../../data/models/review.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/location_screen.dart';
import '../../features/chat/chat_conversation_screen.dart';
import '../../features/chat/chat_list_screen.dart';
import '../../features/community/community_feed_screen.dart';
import '../../features/community/new_post_screen.dart';
import '../../features/community/post_live_screen.dart';
import '../../features/community/thread_screen.dart';
import '../../features/discovery/discover_screen.dart';
import '../../features/discovery/nearby_map_screen.dart';
import '../../features/discovery/woof_match_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/homestay/homestay_list_screen.dart';
import '../../features/homestay/homestay_payment_screen.dart';
import '../../features/homestay/homestay_request_screen.dart';
import '../../features/homestay/host_accepted_screen.dart';
import '../../features/homestay/host_profile_screen.dart';
import '../../features/homestay/host_setup_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/pets/create_pet_screen.dart';
import '../../features/pets/pet_profile_detail_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/settings_screen.dart';
import '../../features/auth/onboarding_arg.dart';
import '../../features/bookings/my_bookings_screen.dart';
import '../../features/reviews/rate_review_screen.dart';
import '../../features/services/booking_confirmed_screen.dart';
import '../../features/services/booking_screen.dart';
import '../../features/services/payment_screen.dart';
import '../../features/services/pro_profile_screen.dart';
import '../../features/services/pro_setup_screen.dart';
import '../../features/services/services_list_screen.dart';
import 'go_router_refresh_stream.dart';
import 'routes.dart';

/// Routes that require an authenticated user. Signed-out users hitting any of
/// these are bounced to Welcome. The onboarding/auth funnel entry pages
/// (splash, onboarding, welcome, signup) are intentionally NOT protected;
/// funnel progression and post-login navigation are explicit in the screens.
const _protected = {
  Routes.home, Routes.discover, Routes.services, Routes.community, Routes.profile,
  Routes.location, Routes.createPet, Routes.nearby, Routes.woofMatch,
  Routes.proSetup, Routes.servicePro,
  Routes.booking, Routes.payment, Routes.bookingConfirmed,
  Routes.homestay, Routes.host, Routes.hostSetup,
  Routes.hostRequest, Routes.hostAccepted, Routes.homestayPayment,
  Routes.newPost, Routes.thread, Routes.postLive,
  Routes.settings, Routes.petProfile,
  Routes.chatList, Routes.chat,
  Routes.bookings, Routes.rate,
  Routes.notifications,
};

GoRouter buildRouter({required AuthRepository auth, String initialLocation = Routes.splash}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: GoRouterRefreshStream(auth.authStateChanges()),
    redirect: (context, state) {
      final loggedIn = auth.currentUser != null;
      if (!loggedIn && _protected.contains(state.matchedLocation)) return Routes.welcome;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.signup, builder: (_, _) => const SignupScreen()),
      GoRoute(path: Routes.location, builder: (_, _) => const LocationScreen()),
      GoRoute(path: Routes.createPet, builder: (_, state) =>
          CreatePetScreen(fromOnboarding: (state.extra as OnboardingArg?)?.fromOnboarding ?? false)),
      GoRoute(path: Routes.woofMatch, builder: (_, state) => WoofMatchScreen(pet: state.extra as PetProfile?)),
      GoRoute(path: Routes.nearby, builder: (_, _) => const NearbyMapScreen()),
      GoRoute(path: Routes.proSetup, builder: (_, state) =>
          ProSetupScreen(fromOnboarding: (state.extra as OnboardingArg?)?.fromOnboarding ?? false)),
      GoRoute(path: Routes.servicePro, builder: (_, state) => ProProfileScreen(pro: state.extra as Pro?)),
      GoRoute(path: Routes.booking, builder: (_, state) => BookingScreen(pro: state.extra as Pro?)),
      GoRoute(path: Routes.payment, builder: (_, state) => PaymentScreen(draft: state.extra as Booking?)),
      GoRoute(path: Routes.bookingConfirmed, builder: (_, state) => BookingConfirmedScreen(booking: state.extra as Booking?)),
      GoRoute(path: Routes.hostSetup, builder: (_, state) =>
          HostSetupScreen(fromOnboarding: (state.extra as OnboardingArg?)?.fromOnboarding ?? false)),
      GoRoute(path: Routes.homestay, builder: (_, _) => const HomestayListScreen()),
      GoRoute(path: Routes.host, builder: (_, state) => HostProfileScreen(homestay: state.extra as Homestay?)),
      GoRoute(path: Routes.hostRequest, builder: (_, state) => HomestayRequestScreen(homestay: state.extra as Homestay?)),
      GoRoute(path: Routes.hostAccepted, builder: (_, state) => HostAcceptedScreen(booking: state.extra as HomestayBooking?)),
      GoRoute(path: Routes.homestayPayment, builder: (_, state) =>
          HomestayPaymentScreen(stay: state.extra as HomestayBooking?)),
      GoRoute(path: Routes.newPost, builder: (_, _) => const NewPostScreen()),
      GoRoute(path: Routes.postLive, builder: (_, state) => PostLiveScreen(post: state.extra as Post?)),
      GoRoute(path: Routes.petProfile, builder: (_, state) => PetProfileDetailScreen(pet: state.extra as PetProfile?)),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: Routes.thread, builder: (_, state) => ThreadScreen(post: state.extra as Post?)),
      GoRoute(path: Routes.chat, builder: (_, state) => ChatConversationScreen(chat: state.extra as Chat?)),
      GoRoute(path: Routes.chatList, builder: (_, _) => const ChatListScreen()),
      GoRoute(path: Routes.notifications, builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: Routes.rate, builder: (_, state) => RateReviewScreen(target: state.extra as ReviewTarget?)),
      GoRoute(path: Routes.bookings, builder: (_, state) =>
          MyBookingsScreen(initialTab: state.extra is int ? state.extra as int : 0)),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.discover, builder: (_, _) => const DiscoverScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.services, builder: (_, _) => const ServicesListScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.community, builder: (_, _) => const CommunityFeedScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter(auth: ref.watch(authRepositoryProvider));
  ref.onDispose(router.dispose);
  return router;
});
