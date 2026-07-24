import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pet_aggregator_app/core/router/app_router.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/theme/app_theme.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'fakes.dart';

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
  Object? extra,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(420, 920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // blockRepositoryProvider is consumed indirectly by nearly every list
  // provider (posts, pros, homestays, chats, nearby pets all filter blocked
  // users), so without a default fake every screen test would have to override
  // it just to avoid reaching real Firestore. Caller overrides still win —
  // Riverpod takes the last matching entry.
  final container = ProviderContainer(overrides: [
    blockRepositoryProvider.overrideWithValue(InMemoryBlockRepository()),
    reportRepositoryProvider.overrideWithValue(InMemoryReportRepository()),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  final AuthRepository auth = container.read(authRepositoryProvider);
  final router = buildRouter(auth: auth, initialLocation: initialLocation);
  addTearDown(router.dispose);

  // initialLocation can't carry `extra`; re-navigate before the first frame.
  if (extra != null) router.go(initialLocation, extra: extra);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? PgTheme.dark() : PgTheme.light(),
      routerConfig: router,
    ),
  ));
}
