import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_text_field.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('PgTextField shows label and accepts input', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpPg(tester, PgTextField(label: 'Email', controller: controller));
    expect(find.text('Email'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'r@x.com');
    expect(controller.text, 'r@x.com');
  });

  testWidgets('maxLines passes through to the inner TextField', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpPg(tester, PgTextField(label: 'Details', controller: controller, maxLines: 6));
    expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 6);
  });

  testWidgets('it sizes to its content even when offered more height',
      (tester) async {
    // Forms hand this unbounded height, where a max-sized Column looks the same
    // as a min-sized one. Somewhere with bounded height — an AlertDialog's
    // content — a max-sized Column stretches to fill it, which is how the
    // delete-account password prompt ended up nearly full-screen.
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpPg(tester, SizedBox(
      height: 600,
      child: Align(
        alignment: Alignment.topCenter,
        child: PgTextField(label: 'Password', controller: controller),
      ),
    ));
    expect(tester.getSize(find.byType(PgTextField)).height, lessThan(120));
  });
}
