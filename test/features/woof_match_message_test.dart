import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Woof-match "Send a message" opens a conversation with the pet owner', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Radhika',
        email: 'me@x.com', area: 'Bandra West', role: Role.petParent));
    await users.createUser(const UserProfile(uid: 'owner1', name: 'Karan Mehta',
        email: 'k@x.com', area: 'Khar', role: Role.petParent));
    const pet = PetProfile(id: 'p1', ownerId: 'owner1', name: 'Simba', breed: 'Beagle',
        ageLabel: '3 yrs', sex: 'male', area: 'Khar', species: Species.dog,
        vaccinated: true, accentColor: Color(0xFF6B8DE0));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
    ], initialLocation: Routes.woofMatch, extra: pet);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send a message 💬'));
    await tester.pumpAndSettle();
    expect(find.text('Karan Mehta'), findsOneWidget); // conversation header (owner name via userByIdProvider)
    expect(find.text('Message…'), findsOneWidget);
  });
}
