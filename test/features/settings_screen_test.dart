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
      preferencesRepositoryProvider.overrideWithValue(prefs),
    ], initialLocation: Routes.settings);
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsOneWidget);
    await tester.tap(find.byType(PgToggle));
    await tester.pumpAndSettle();
    expect(prefs.themeMode, ThemeMode.dark); // persisted via the notifier
  });

  testWidgets('a coming-soon settings row shows the snackbar', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      preferencesRepositoryProvider.overrideWithValue(InMemoryPreferencesRepository()),
    ], initialLocation: Routes.settings);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Booking updates'));
    await tester.pump();
    expect(find.textContaining('coming soon'), findsOneWidget);
  });
}
