import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_buttons.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('PgPrimaryButton shows label and fires onPressed', (tester) async {
    var tapped = false;
    await pumpPg(tester, PgPrimaryButton(label: 'Log in', onPressed: () => tapped = true));
    expect(find.text('Log in'), findsOneWidget);
    await tester.tap(find.text('Log in'));
    expect(tapped, isTrue);
  });
}
