import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/features/pets/create_pet_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Create pet shows fields and finish button', (tester) async {
    await pumpPg(tester, const CreatePetScreen());
    expect(find.text('Add your pet'), findsOneWidget);
    expect(find.text('Vaccinated'), findsOneWidget);
    expect(find.text('Finish & explore Pawgo'), findsOneWidget);
  });
}
