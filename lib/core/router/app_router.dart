import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/location_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/home/placeholder_tab.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/pets/create_pet_screen.dart';
import 'go_router_refresh_stream.dart';
import 'routes.dart';

/// Routes that require an authenticated user. Signed-out users hitting any of
/// these are bounced to Welcome. The onboarding/auth funnel entry pages
/// (splash, onboarding, welcome, signup) are intentionally NOT protected;
/// funnel progression and post-login navigation are explicit in the screens.
const _protected = {
  Routes.home, Routes.discover, Routes.services, Routes.community, Routes.profile,
  Routes.location, Routes.createPet,
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
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.discover, builder: (_, _) => const PlaceholderTab(title: 'Discover')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.services, builder: (_, _) => const PlaceholderTab(title: 'Services')),
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
