import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('filling the form and saving writes a homestay listing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Meera Iyer',
        email: 'me@x.com', area: 'Bandra West', role: Role.homestayHost));
    final homestays = InMemoryHomestayRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      homestayRepositoryProvider.overrideWithValue(homestays),
    ], initialLocation: Routes.hostSetup);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), "Meera's Home"); // home name
    await tester.enterText(find.byType(TextField).at(1), '900');          // rate/night
    await tester.enterText(find.byType(TextField).at(2), 'Spacious 2BHK, WFH host.'); // about
    await tester.tap(find.textContaining('Near park')); // toggle an amenity
    await tester.pump();
    await tester.tap(find.text('List my home'));
    await tester.pumpAndSettle();

    final mine = await homestays.watchHomestay(auth.currentUser!.uid).first;
    expect(mine!.homeName, "Meera's Home");
    expect(mine.ratePerNight, 900);
    expect(mine.hostName, 'Meera Iyer');
    expect(mine.area, 'Bandra West');
    expect(mine.amenities, contains(Amenity.nearPark));
    expect(mine.verified, isFalse);
  });
}
