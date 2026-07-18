import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/widgets/pg_image_slot.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('picking a photo previews it; Finish uploads and saves photoUrl', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final pets = InMemoryPetRepository();
    final storage = InMemoryStorageRepository();
    final picker = FakeImagePickerService(Uint8List.fromList([1, 2, 3]));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(pets),
      storageRepositoryProvider.overrideWithValue(storage),
      imagePickerServiceProvider.overrideWithValue(picker),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.createPet);
    await tester.pumpAndSettle();

    // Tap the photo slot -> picker runs -> the picked bytes preview.
    await tester.tap(find.byType(PgImageSlot));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(find.text('Tap to change photo'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget); // Image.memory preview

    await tester.enterText(find.byType(TextField).first, 'Bruno');
    await tester.tap(find.text('Finish & explore Pawgo'));
    await tester.pumpAndSettle();

    final saved = (await pets.watchMyPets(uid).first).single;
    expect(saved.name, 'Bruno');
    expect(saved.photoUrl, startsWith('https://fake.storage/pets/$uid'));
    expect(storage.uploads.length, 1);
  });

  testWidgets('cancelling the picker leaves the placeholder and saves without a photo', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final pets = InMemoryPetRepository();
    final storage = InMemoryStorageRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(pets),
      storageRepositoryProvider.overrideWithValue(storage),
      imagePickerServiceProvider.overrideWithValue(FakeImagePickerService()), // returns null
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.createPet);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PgImageSlot));
    await tester.pumpAndSettle();
    expect(find.text('Upload a cute photo 📸'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Mochi');
    await tester.tap(find.text('Finish & explore Pawgo'));
    await tester.pumpAndSettle();

    expect((await pets.watchMyPets(uid).first).single.photoUrl, '');
    expect(storage.uploads, isEmpty);
  });
}
