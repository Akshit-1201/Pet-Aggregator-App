import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../../support/fakes.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('signed-out user is redirected away from /home to Welcome', (tester) async {
    await pumpPgApp(tester,
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
        initialLocation: Routes.home);
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget); // Welcome screen
  });

  testWidgets('signed-in user can load the Home shell', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets); // bottom-nav label
  });
}
