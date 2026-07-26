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
  /// Set when [overrides] already contains a `postRepositoryProvider`.
  ///
  /// Riverpod 3 THROWS on a duplicate override rather than taking the last one,
  /// and the override list gives no public way to inspect what is in it — so a
  /// test that supplies its own post repository has to say so.
  bool providesPostRepository = false,
  /// Set when [overrides] already contains a `notificationRepositoryProvider`.
  /// See [providesPostRepository] for why this flag exists.
  bool providesNotificationRepository = false,
}) async {
  tester.view.physicalSize = const Size(420, 920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Cross-cutting repositories that almost every screen reaches indirectly:
  // block/report (every list filters blocked users), verification + payout
  // (both setup screens embed those cards), posts (Home shows the newest one
  // under "Community picks"), and notifications (Home's bell icon watches
  // hasUnreadNotificationsProvider on every render). Without defaults, each of
  // ~20 unrelated tests would have to override them purely to avoid hitting
  // real Firestore.
  //
  // No test overrides the first four, so they are always safe to default.
  final container = ProviderContainer(overrides: [
    blockRepositoryProvider.overrideWithValue(InMemoryBlockRepository()),
    reportRepositoryProvider.overrideWithValue(InMemoryReportRepository()),
    verificationRepositoryProvider.overrideWithValue(InMemoryVerificationRepository()),
    payoutRepositoryProvider.overrideWithValue(InMemoryPayoutRepository()),
    if (!providesPostRepository)
      postRepositoryProvider.overrideWithValue(InMemoryPostRepository()),
    if (!providesNotificationRepository)
      notificationRepositoryProvider.overrideWithValue(FakeNotificationRepository()),
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
