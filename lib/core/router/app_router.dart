import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/home_shell.dart';
import '../../features/home/placeholder_tab.dart';
import 'routes.dart';

// Temporary stub until onboarding/auth screens land (Tasks 10-15).
Widget _stub(String name) => Scaffold(body: Center(child: Text(name)));

GoRouter buildRouter({String initialLocation = Routes.splash}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => _stub('Splash')),
      GoRoute(path: Routes.onboarding, builder: (_, _) => _stub('Onboarding')),
      GoRoute(path: Routes.welcome, builder: (_, _) => _stub('Welcome')),
      GoRoute(path: Routes.signup, builder: (_, _) => _stub('Signup')),
      GoRoute(path: Routes.location, builder: (_, _) => _stub('Location')),
      GoRoute(path: Routes.createPet, builder: (_, _) => _stub('Create Pet')),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const PlaceholderTab(title: 'Home')),
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

final appRouter = buildRouter();
