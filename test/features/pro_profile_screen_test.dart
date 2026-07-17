import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the pro and shows New rating; chat button opens a conversation', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    const pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West',
        bio: 'Friendly reliable walker.', serviceType: ServiceType.walker,
        rate: 250, experienceYears: 4);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
    ], initialLocation: Routes.servicePro, extra: pro);
    await tester.pumpAndSettle();

    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Friendly reliable walker.'), findsOneWidget);
    expect(find.textContaining('New'), findsWidgets); // no reviews yet

    await tester.tap(find.text('💬'));
    await tester.pumpAndSettle();
    expect(find.text('Message…'), findsOneWidget); // conversation composer hint
  });
}
