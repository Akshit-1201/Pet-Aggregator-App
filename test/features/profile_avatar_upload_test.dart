import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/widgets/pg_image_slot.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('tapping the avatar uploads the pick and persists photoUrl', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final storage = InMemoryStorageRepository();
    final picker = FakeImagePickerService(Uint8List.fromList([7, 7]));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      storageRepositoryProvider.overrideWithValue(storage),
      imagePickerServiceProvider.overrideWithValue(picker),
    ], initialLocation: Routes.profile);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PgImageSlot).first); // the header avatar
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(storage.uploads.keys.single, 'users/$uid/avatar.jpg');
    expect((await users.watchUser(uid).first)!.photoUrl,
        'https://fake.storage/users/$uid/avatar.jpg');
  });

  testWidgets('cancelling the picker leaves photoUrl untouched', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final storage = InMemoryStorageRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      storageRepositoryProvider.overrideWithValue(storage),
      imagePickerServiceProvider.overrideWithValue(FakeImagePickerService()), // null
    ], initialLocation: Routes.profile);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PgImageSlot).first);
    await tester.pumpAndSettle();

    expect(storage.uploads, isEmpty);
    expect((await users.watchUser(uid).first)!.photoUrl, '');
  });

  testWidgets('a throwing picker shows a failure snackbar and leaves photoUrl untouched',
      (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: uid, name: 'Radhika', email: 'me@x.com',
        area: 'Bandra West', role: Role.petParent));
    final storage = InMemoryStorageRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      storageRepositoryProvider.overrideWithValue(storage),
      imagePickerServiceProvider.overrideWithValue(FakeImagePickerService.throwing()),
    ], initialLocation: Routes.profile);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PgImageSlot).first);
    await tester.pumpAndSettle();

    expect(find.text("Couldn't upload the photo. Please try again."), findsOneWidget);
    expect(storage.uploads, isEmpty);
    expect((await users.watchUser(uid).first)!.photoUrl, '');
  });
}
