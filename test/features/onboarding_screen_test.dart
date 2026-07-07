import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/features/onboarding/onboarding_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Onboarding shows first page title and a Next action', (tester) async {
    await pumpPg(tester, const OnboardingScreen());
    expect(find.text('Find playmates just around the corner'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });
}
