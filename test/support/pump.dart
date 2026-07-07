import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';

Future<void> pumpPg(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light}) async {
  await tester.pumpWidget(MaterialApp(
    theme: brightness == Brightness.dark ? PgTheme.dark() : PgTheme.light(),
    home: Scaffold(body: child),
  ));
}
