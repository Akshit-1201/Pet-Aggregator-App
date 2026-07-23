import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

/// Taps "Add" [n] times; each tap picks + uploads one photo.
Future<void> _addPhotos(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.tap(find.byKey(const Key('add-home-photo')));
    await tester.pumpAndSettle();
  }
}

Future<InMemoryHomestayRepository> _pumpSetup(WidgetTester tester, FakeAuthRepository auth) async {
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Meera Iyer',
      email: 'me@x.com', area: 'Bandra West', role: Role.homestayHost));
  final homestays = InMemoryHomestayRepository();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    homestayRepositoryProvider.overrideWithValue(homestays),
    imagePickerServiceProvider.overrideWithValue(FakeImagePickerService(Uint8List.fromList([1, 2, 3]))),
    storageRepositoryProvider.overrideWithValue(InMemoryStorageRepository()),
  ], initialLocation: Routes.hostSetup);
  await tester.pumpAndSettle();
  return homestays;
}

Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), "Meera's Home"); // home name
  await tester.enterText(find.byType(TextField).at(1), '900');          // rate/night
  await tester.enterText(find.byType(TextField).at(2), 'Spacious 2BHK, WFH host.'); // about
  await tester.tap(find.textContaining('Near park')); // toggle an amenity
  await tester.pump();
}

void main() {
  testWidgets('filling the form and saving writes a homestay listing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final homestays = await _pumpSetup(tester, auth);

    await _fillForm(tester);
    await _addPhotos(tester, Homestay.minPhotos);
    await tester.tap(find.text('List my home'));
    await tester.pumpAndSettle();

    final mine = await homestays.watchHomestay(auth.currentUser!.uid).first;
    expect(mine!.homeName, "Meera's Home");
    expect(mine.ratePerNight, 900);
    expect(mine.hostName, 'Meera Iyer');
    expect(mine.area, 'Bandra West');
    expect(mine.amenities, contains(Amenity.nearPark));
    expect(mine.verified, isFalse);
    expect(mine.photoUrls.length, Homestay.minPhotos);
  });

  testWidgets('a listing with fewer than 3 photos is refused', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final homestays = await _pumpSetup(tester, auth);

    await _fillForm(tester);
    await _addPhotos(tester, 2); // one short of the minimum
    await tester.tap(find.text('List my home'));
    await tester.pumpAndSettle();

    expect(find.textContaining('at least ${Homestay.minPhotos} photos'), findsOneWidget);
    expect(await homestays.watchHomestay(auth.currentUser!.uid).first, isNull); // nothing saved
  });

  testWidgets('the Add button disappears once 5 photos are attached', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await _pumpSetup(tester, auth);

    await _addPhotos(tester, Homestay.maxPhotos);
    expect(find.byKey(const Key('add-home-photo')), findsNothing); // capped at 5

    await tester.tap(find.byKey(const Key('remove-photo-0'))); // removing frees a slot
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-home-photo')), findsOneWidget);
  });
}
