import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/auth/onboarding_arg.dart';
import 'package:pet_aggregator_app/features/pets/create_pet_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Finish with a blank name shows an error and writes nothing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pets = InMemoryPetRepository();
    await pumpPg(tester, ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        petRepositoryProvider.overrideWithValue(pets),
        storageRepositoryProvider.overrideWithValue(InMemoryStorageRepository()),
      ],
      child: const CreatePetScreen(fromOnboarding: true),
    ));
    await tester.tap(find.text('Finish & explore Pawgo'));
    await tester.pumpAndSettle();
    expect(find.text("Please enter your pet's name."), findsOneWidget);
    expect(await pets.watchMyPets('uid_me@x.com').first, isEmpty);
  });

  testWidgets('onboarding shows Skip for now; non-onboarding does not', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPg(tester, ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: const CreatePetScreen(fromOnboarding: true),
    ));
    expect(find.text('Skip for now'), findsOneWidget);

    await pumpPg(tester, ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: const CreatePetScreen(fromOnboarding: false),
    ));
    expect(find.text('Skip for now'), findsNothing);
  });

  testWidgets('Skip for now (onboarding) reaches Home writing no pet', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pets = InMemoryPetRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(pets),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.createPet, extra: const OnboardingArg(fromOnboarding: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('Skip for now'), findsNothing); // left the screen
    expect(await pets.watchMyPets('uid_me@x.com').first, isEmpty);
  });
}
