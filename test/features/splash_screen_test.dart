import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';
import 'package:pet_aggregator_app/features/onboarding/splash_screen.dart';

void main() {
  testWidgets('SplashScreen shows brand name and tagline, then advances', (tester) async {
    // SplashScreen auto-navigates via context.go, so give it a real router.
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const Scaffold(body: Text('onboarding'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(theme: PgTheme.light(), routerConfig: router));

    expect(find.text('Pawgo'), findsOneWidget);
    expect(find.text("Your pet's whole world, nearby"), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1700)); // fire the 1600ms timer
    await tester.pumpAndSettle(); // settle the navigation transition
    expect(find.text('onboarding'), findsOneWidget);
  });
}
