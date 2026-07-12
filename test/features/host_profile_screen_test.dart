import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/features/homestay/host_profile_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the host + New host (unverified); Request to book hints coming soon',
      (tester) async {
    const h = Homestay(uid: 'h1', homeName: "Meera's Home", hostName: 'Meera Iyer',
        area: 'Bandra West', about: 'Spacious 2BHK with a fenced balcony.',
        homeType: HomeType.apartment, ratePerNight: 900,
        amenities: [Amenity.nearPark, Amenity.residentDog]);
    await pumpPg(tester, const HostProfileScreen(homestay: h));
    expect(find.text("Meera's Home"), findsOneWidget);
    expect(find.textContaining('Meera Iyer'), findsOneWidget);
    expect(find.text('Spacious 2BHK with a fenced balcony.'), findsOneWidget);
    expect(find.textContaining('New host'), findsOneWidget); // unverified
    await tester.tap(find.textContaining('Request to book'));
    await tester.pump();
    expect(find.text('Booking is coming soon 🐾'), findsOneWidget);
  });

  testWidgets('a verified host shows the Verified host badge', (tester) async {
    const h = Homestay(uid: 'h2', homeName: 'Anjali Stays', hostName: 'Anjali Rao',
        area: 'Pali Hill', about: 'x', homeType: HomeType.villa, ratePerNight: 1100,
        verified: true);
    await pumpPg(tester, const HostProfileScreen(homestay: h));
    expect(find.text('Pawgo Verified host'), findsOneWidget);
    expect(find.textContaining('New host'), findsNothing);
  });
}
