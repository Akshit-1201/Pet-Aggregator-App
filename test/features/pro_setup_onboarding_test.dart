import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/auth/onboarding_arg.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<(FakeAuthRepository, InMemoryProRepository)> _pump(WidgetTester tester,
    {required bool onboarding}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Me',
      email: 'me@x.com', area: 'Khar', role: Role.servicePro));
  final pros = InMemoryProRepository();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    proRepositoryProvider.overrideWithValue(pros),
    petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
    homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
    homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
  ], initialLocation: Routes.proSetup,
     extra: onboarding ? const OnboardingArg(fromOnboarding: true) : null);
  await tester.pumpAndSettle();
  return (auth, pros);
}

void main() {
  testWidgets('onboarding shows Set up later and reaches Home writing no listing', (tester) async {
    final (auth, pros) = await _pump(tester, onboarding: true);
    expect(find.text('Set up later'), findsOneWidget);
    await tester.tap(find.text('Set up later'));
    await tester.pumpAndSettle();
    expect(find.text('Set up later'), findsNothing);
    expect(await pros.watchPro(auth.currentUser!.uid).first, isNull);
  });

  testWidgets('non-onboarding entry does not show Set up later', (tester) async {
    await _pump(tester, onboarding: false);
    expect(find.text('Set up later'), findsNothing);
  });
}
