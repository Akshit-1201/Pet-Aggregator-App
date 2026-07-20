import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _pro = Pro(uid: 'pro1', name: 'Aarav', area: 'Khar', bio: 'Walker',
    serviceType: ServiceType.walker, rate: 250, experienceYears: 3);
const _home = Homestay(uid: 'h1', homeName: "Meera's", hostName: 'Meera', area: 'Khar',
    about: '', homeType: HomeType.apartment, ratePerNight: 900);

Future<void> _pump(WidgetTester tester, String route, Object extra,
    {required bool withPet}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final uid = auth.currentUser!.uid;
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    petRepositoryProvider.overrideWithValue(
        withPet ? InMemoryPetRepository(fixturePets(uid)) : InMemoryPetRepository()),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
  ], initialLocation: route, extra: extra);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('booking: petless shows Add a pet CTA that opens Create Pet', (tester) async {
    await _pump(tester, Routes.booking, _pro, withPet: false);
    expect(find.text('Add a pet'), findsOneWidget);
    expect(find.text('Continue to payment'), findsNothing);
    await tester.tap(find.text('Add a pet'));
    await tester.pumpAndSettle();
    expect(find.text('Add your pet'), findsOneWidget); // Create Pet
  });

  testWidgets('booking: with a pet shows the normal Continue button', (tester) async {
    await _pump(tester, Routes.booking, _pro, withPet: true);
    expect(find.text('Continue to payment'), findsOneWidget);
    expect(find.text('Add a pet'), findsNothing);
  });

  testWidgets('homestay request: petless shows Add a pet CTA', (tester) async {
    await _pump(tester, Routes.hostRequest, _home, withPet: false);
    expect(find.text('Add a pet'), findsOneWidget);
    await tester.tap(find.text('Add a pet'));
    await tester.pumpAndSettle();
    expect(find.text('Add your pet'), findsOneWidget);
  });
}
