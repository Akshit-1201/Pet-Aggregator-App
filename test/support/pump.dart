import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';

/// Pumps [child] inside a themed Scaffold on a phone-sized surface.
///
/// The default test surface (800x600) is too short for Pawgo's tall,
/// device-oriented layouts and triggers spurious overflow errors, so we
/// emulate a typical phone viewport.
Future<void> pumpPg(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light,
    Size surfaceSize = const Size(420, 920)}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: brightness == Brightness.dark ? PgTheme.dark() : PgTheme.light(),
    home: Scaffold(body: child),
  ));
}
