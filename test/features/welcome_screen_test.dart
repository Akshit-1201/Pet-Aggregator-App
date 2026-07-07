import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/features/auth/welcome_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Welcome shows heading and Log in button', (tester) async {
    await pumpPg(tester, const WelcomeScreen());
    expect(find.text('Welcome back 👋'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.textContaining('Create account'), findsOneWidget);
  });
}
