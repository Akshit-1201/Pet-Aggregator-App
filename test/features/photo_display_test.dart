import 'package:cached_network_image/cached_network_image.dart';
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

    // Every network image goes through PgNetworkImage, which is a disk-cached
    // CachedNetworkImage carrying a decode hint.
    bool hasNetworkImage(String url) => find
        .byWidgetPredicate((w) => w is CachedNetworkImage && w.imageUrl == url)
        .evaluate()
        .isNotEmpty;

    expect(hasNetworkImage('https://x/bruno.jpg'), isTrue); // pet row
    expect(hasNetworkImage('https://x/me.jpg'), isTrue);    // header avatar
  });
}
