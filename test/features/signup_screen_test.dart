import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/features/auth/signup_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Signup shows the three roles and Continue', (tester) async {
    await pumpPg(tester, const SignupScreen());
    expect(find.text('Pet Parent'), findsOneWidget);
    expect(find.text('Service Professional'), findsOneWidget);
    expect(find.text('Homestay Host'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('Tapping a role selects it', (tester) async {
    await pumpPg(tester, const SignupScreen());
    await tester.tap(find.text('Homestay Host'));
    await tester.pump();
    expect(find.byIcon(Icons.check), findsOneWidget); // only the selected card shows a check
  });
}
