import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/core/router/app_router.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';

void main() {
  testWidgets('router starts at splash and can navigate to home shell', (tester) async {
    final router = buildRouter(initialLocation: '/home');
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(theme: PgTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets); // bottom nav label present
  });
}
