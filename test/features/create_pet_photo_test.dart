import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

/// A pet now needs 3–5 photos, uploaded as they are picked (the same shape host
/// setup uses) rather than one held in memory until save.

final _bytes = Uint8List.fromList([1, 2, 3]);

class _Harness {
  final auth = FakeAuthRepository();
  final users = InMemoryUserRepository();
  final pets = InMemoryPetRepository();
  final storage = InMemoryStorageRepository();
  late final String uid;

  Future<List<Override>> ready({Uint8List? picked}) async {
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    uid = auth.currentUser!.uid;
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    return [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(pets),
      storageRepositoryProvider.overrideWithValue(storage),
      imagePickerServiceProvider.overrideWithValue(FakeImagePickerService(picked)),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ];
  }
}

Future<void> _addPhotos(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.tap(find.byKey(const Key('add-pet-photo')));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('each picked photo uploads immediately and the pet saves the gallery',
      (tester) async {
    final h = _Harness();
    await pumpPgApp(tester, overrides: await h.ready(picked: _bytes),
        initialLocation: Routes.createPet);
    await tester.pumpAndSettle();

    await _addPhotos(tester, PetProfile.minPhotos);
    // Uploaded on pick, not deferred to save — so a saved pet never points at
    // an object that failed to upload.
    expect(h.storage.uploads.length, PetProfile.minPhotos);
    expect(find.text('${PetProfile.minPhotos}/${PetProfile.maxPhotos}'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Bruno');
    await tester.tap(find.text('Finish & explore Pawgo'));
    await tester.pumpAndSettle();

    final saved = (await h.pets.watchMyPets(h.uid).first).single;
    expect(saved.name, 'Bruno');
    expect(saved.photoUrls.length, PetProfile.minPhotos);
    expect(saved.photoUrl, startsWith('https://fake.storage/pets/${h.uid}'));
  });

  testWidgets('saving is refused below the minimum, and nothing is written',
      (tester) async {
    final h = _Harness();
    await pumpPgApp(tester, overrides: await h.ready(picked: _bytes),
        initialLocation: Routes.createPet);
    await tester.pumpAndSettle();

    await _addPhotos(tester, 1); // short of the minimum
    await tester.enterText(find.byType(TextField).first, 'Bruno');
    await tester.tap(find.text('Finish & explore Pawgo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Add at least ${PetProfile.minPhotos} photos'), findsOneWidget);
    expect(await h.pets.watchMyPets(h.uid).first, isEmpty);

    // Adding the missing photos must clear the complaint. It used to linger,
    // so the counter read "3/5" in brand orange with a red "(1 so far)"
    // underneath it — which reads as broken.
    await _addPhotos(tester, PetProfile.minPhotos - 1);
    expect(find.textContaining('Add at least ${PetProfile.minPhotos} photos'), findsNothing);
  });

  testWidgets('cancelling the picker adds nothing and uploads nothing', (tester) async {
    final h = _Harness();
    await pumpPgApp(tester, overrides: await h.ready(), // picker returns null
        initialLocation: Routes.createPet);
    await tester.pumpAndSettle();

    await _addPhotos(tester, 1);
    expect(find.text('0/${PetProfile.maxPhotos}'), findsOneWidget);
    expect(h.storage.uploads, isEmpty);
  });

  testWidgets('the add tile disappears at the maximum', (tester) async {
    final h = _Harness();
    await pumpPgApp(tester, overrides: await h.ready(picked: _bytes),
        initialLocation: Routes.createPet);
    await tester.pumpAndSettle();

    await _addPhotos(tester, PetProfile.maxPhotos);
    expect(find.text('${PetProfile.maxPhotos}/${PetProfile.maxPhotos}'), findsOneWidget);
    expect(find.byKey(const Key('add-pet-photo')), findsNothing);
  });
}
