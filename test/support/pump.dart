import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pet_aggregator_app/core/router/app_router.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';

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

/// Pumps the full app (router + providers) on a phone-sized surface, with
/// [overrides] (inject fakes) and a starting [initialLocation].
Future<void> pumpPgApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
  String initialLocation = Routes.splash,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(420, 920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  final AuthRepository auth = container.read(authRepositoryProvider);
  final router = buildRouter(auth: auth, initialLocation: initialLocation);
  addTearDown(router.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? PgTheme.dark() : PgTheme.light(),
      routerConfig: router,
    ),
  ));
}
