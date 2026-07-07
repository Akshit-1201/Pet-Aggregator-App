import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/features/auth/location_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Location screen shows heading and allow button', (tester) async {
    await pumpPg(tester, const LocationScreen());
    expect(find.text('Enable location'), findsOneWidget);
    expect(find.text('Allow while using app'), findsOneWidget);
    expect(find.text('Set location manually'), findsOneWidget);
  });
}
