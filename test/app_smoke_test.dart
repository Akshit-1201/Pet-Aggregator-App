import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/app.dart';

void main() {
  testWidgets('PawgoApp builds a MaterialApp', (tester) async {
    await tester.pumpWidget(const PawgoApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
