import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';
import 'package:pet_aggregator_app/features/home/home_screen.dart';

void main() {
  testWidgets('Home shows greeting and a nearby pet', (tester) async {
    // Tall phone viewport so the lazy ListView builds the pet rows.
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: PgTheme.light(), home: const HomeScreen()),
    ));
    expect(find.text('Hey Radhika 👋'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Woof!'), findsWidgets);
  });
}
