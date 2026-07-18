import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _pumpWelcome(WidgetTester tester, FakeAuthRepository auth) =>
    pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.welcome);

void main() {
  testWidgets('successful login navigates to Home', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'r@x.com', password: 'secret1');
    await auth.signOut();
    await _pumpWelcome(tester, auth);

    await tester.enterText(find.byType(TextField).at(0), 'r@x.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret1');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('wrong password shows an error', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'r@x.com', password: 'secret1');
    await auth.signOut();
    await _pumpWelcome(tester, auth);

    await tester.enterText(find.byType(TextField).at(0), 'r@x.com');
    await tester.enterText(find.byType(TextField).at(1), 'nope');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect email or password.'), findsOneWidget);
  });
}
