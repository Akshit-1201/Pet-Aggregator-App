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
}
