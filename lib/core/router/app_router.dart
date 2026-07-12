import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/booking.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/pro.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/location_screen.dart';
import '../../features/discovery/discover_screen.dart';
import '../../features/discovery/nearby_map_screen.dart';
import '../../features/discovery/woof_match_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/home/placeholder_tab.dart';
import '../../features/homestay/homestay_list_screen.dart';
import '../../features/homestay/host_setup_screen.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/pets/create_pet_screen.dart';
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
      GoRoute(path: Routes.createPet, builder: (_, _) => const CreatePetScreen()),
      GoRoute(path: Routes.woofMatch, builder: (_, state) => WoofMatchScreen(pet: state.extra as PetProfile?)),
      GoRoute(path: Routes.nearby, builder: (_, _) => const NearbyMapScreen()),
      GoRoute(path: Routes.proSetup, builder: (_, _) => const ProSetupScreen()),
      GoRoute(path: Routes.servicePro, builder: (_, state) => ProProfileScreen(pro: state.extra as Pro?)),
      GoRoute(path: Routes.booking, builder: (_, state) => BookingScreen(pro: state.extra as Pro?)),
      GoRoute(path: Routes.payment, builder: (_, state) => PaymentScreen(draft: state.extra as Booking?)),
      GoRoute(path: Routes.bookingConfirmed, builder: (_, state) => BookingConfirmedScreen(booking: state.extra as Booking?)),
      GoRoute(path: Routes.hostSetup, builder: (_, _) => const HostSetupScreen()),
      GoRoute(path: Routes.homestay, builder: (_, _) => const HomestayListScreen()),
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
            GoRoute(path: Routes.community, builder: (_, _) => const PlaceholderTab(title: 'Community')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.profile, builder: (_, _) => const PlaceholderTab(title: 'Profile')),
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
