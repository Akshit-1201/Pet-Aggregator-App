import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/widgets/pg_toggle.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('dark-mode toggle flips theme mode and persists', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final prefs = InMemoryPreferencesRepository(); // system
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      // Settings now reads the profile for the notification toggles.
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      preferencesRepositoryProvider.overrideWithValue(prefs),
    ], initialLocation: Routes.settings);
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsOneWidget);
    // Dark mode is the first toggle; the notification categories follow it.
    await tester.tap(find.byType(PgToggle).first);
    await tester.pumpAndSettle();
    expect(prefs.themeMode, ThemeMode.dark); // persisted via the notifier
  });

  testWidgets('shows only real settings — no coming-soon placeholder rows', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      // Settings now reads the profile for the notification toggles.
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      preferencesRepositoryProvider.overrideWithValue(InMemoryPreferencesRepository()),
    ], initialLocation: Routes.settings);
    await tester.pumpAndSettle();
    // Every row must do something. "Booking updates" is now real — it gates a
    // server-side push category — so it is expected here. The two still absent
    // have no feature behind them: there is no location-sharing setting, and
    // chat safety is a client-side phone mask with nothing to configure.
    expect(find.text('Booking updates'), findsOneWidget);
    expect(find.text('Location sharing'), findsNothing);
    expect(find.text('Chat safety'), findsNothing);
    expect(find.text('About Pawgo'), findsOneWidget);
  });
}
