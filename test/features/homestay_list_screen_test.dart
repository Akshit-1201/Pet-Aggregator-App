import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _meera = Homestay(uid: 'h1', homeName: "Meera's Home", hostName: 'Meera Iyer',
    area: 'Bandra West', about: 'Spacious 2BHK.', homeType: HomeType.apartment,
    ratePerNight: 900, amenities: [Amenity.nearPark]);

void main() {
  testWidgets('lists live hosts (unverified shows New, no badge)', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository([_meera])),
    ], initialLocation: Routes.homestay);
    await tester.pumpAndSettle();
    expect(find.text('Homestay boarding'), findsOneWidget);
    expect(find.text("Meera's Home"), findsOneWidget);
    expect(find.text('New'), findsWidgets);          // no reviews yet
    expect(find.text('Verified host'), findsNothing); // unverified => no badge
  });

  testWidgets('a verified host shows the Verified badge', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    const verified = Homestay(uid: 'h2', homeName: 'Anjali Stays', hostName: 'Anjali Rao',
        area: 'Pali Hill', about: 'x', homeType: HomeType.villa, ratePerNight: 1100,
        verified: true);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository([verified])),
    ], initialLocation: Routes.homestay);
    await tester.pumpAndSettle();
    expect(find.text('Verified host'), findsOneWidget);
  });

  testWidgets('shows a set-up banner for a homestayHost without a listing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com',
        area: 'Khar', role: Role.homestayHost));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.homestay);
    await tester.pumpAndSettle();
    expect(find.text('Set up your homestay'), findsOneWidget);
  });

  testWidgets('Home Homestay tile opens the Homestay list', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository([_meera])),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Homestay'));
    await tester.pumpAndSettle();
    expect(find.text('Homestay boarding'), findsOneWidget);
  });
}
