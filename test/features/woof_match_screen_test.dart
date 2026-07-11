import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/features/discovery/woof_match_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('shows the match heading and both actions; Send a message hints coming soon',
      (tester) async {
    final pet = PetProfile(
        id: 'p1', ownerId: 'B', name: 'Bruno', breed: 'Labrador', ageLabel: '2 yrs',
        sex: 'male', area: 'Bandra West', species: Species.dog, vaccinated: true,
        accentColor: PetProfile.accentFor('Bruno'));
    await pumpPg(tester, WoofMatchScreen(pet: pet));
    expect(find.text("It's a Woof match! 🎉"), findsOneWidget);
    expect(find.text('Keep swiping'), findsOneWidget);
    await tester.tap(find.text('Send a message 💬'));
    await tester.pump();
    expect(find.text('Chat is coming soon 🐾'), findsOneWidget);
  });
}
