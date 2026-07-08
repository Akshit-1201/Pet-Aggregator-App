import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/app.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('PawgoApp builds a MaterialApp', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
      child: const PawgoApp(),
    ));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
