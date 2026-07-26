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
  testWidgets('a pet photo and my avatar render as network images on Home', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent, photoUrl: 'https://x/me.jpg'));
    final pets = InMemoryPetRepository([
      PetProfile(id: 'p1', ownerId: 'someone-else', name: 'Bruno', breed: 'Labrador',
          ageLabel: '2 yrs', sex: 'male', area: 'Bandra West', species: Species.dog,
          vaccinated: true, accentColor: PetProfile.accentFor('Bruno'),
          photoUrls: const ['https://x/bruno.jpg']),
    ]);

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(pets),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();

    // Images now carry a decode hint, so the provider is a ResizeImage wrapping
    // the NetworkImage rather than a bare one — unwrap before comparing.
    String? urlOf(ImageProvider p) => switch (p) {
          ResizeImage(imageProvider: final inner) => urlOf(inner),
          NetworkImage(url: final u) => u,
          _ => null,
        };

    bool hasNetworkImage(String url) => find
        .byWidgetPredicate((w) => w is Image && urlOf(w.image) == url)
        .evaluate()
        .isNotEmpty;

    expect(hasNetworkImage('https://x/bruno.jpg'), isTrue); // pet row
    expect(hasNetworkImage('https://x/me.jpg'), isTrue);    // header avatar
  });
}
