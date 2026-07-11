import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_snackbar.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('showComingSoon shows a labelled snackbar', (tester) async {
    await pumpPg(tester, Builder(builder: (context) {
      return TextButton(onPressed: () => showComingSoon(context, 'Chat'), child: const Text('go'));
    }));
    await tester.tap(find.text('go'));
    await tester.pump(); // let the snackbar appear
    expect(find.text('Chat is coming soon 🐾'), findsOneWidget);
  });
}
