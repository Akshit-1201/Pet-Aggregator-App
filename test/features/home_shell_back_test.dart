import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pet_aggregator_app/core/navigation/exit_confirm.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _systemBack(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

Future<FakeAuthRepository> _signedIn() async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  return auth;
}

// The Home and Profile branches are both real screens reading live
// repositories (nearbyPetsProvider, currentUserProfileProvider, Profile's
// stats row, etc). pumpPgApp only defaults the cross-cutting ones (block,
// report, verification, payout, posts, notifications); anything a specific
// screen reads has to be supplied here or it falls through to the real
// Firebase-backed provider, which throws with no Firebase test setup and
// sends Riverpod into an endless retry loop that pumpAndSettle never
// settles. This mirrors the override sets already used by
// test/features/home_screen_test.dart and test/features/profile_screen_test.dart.
List<Override> _screenOverrides(FakeAuthRepository auth) => [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ];

void main() {
  setUp(PgExitConfirm.reset);

  testWidgets('back on a non-Home tab returns to Home', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t,
        overrides: _screenOverrides(auth),
        initialLocation: Routes.profile);
    await t.pumpAndSettle();

    await _systemBack(t);
    expect(find.text('Home'), findsWidgets); // the Home tab is selected
    expect(find.text('Press back again to exit'), findsNothing);
  });

  testWidgets('first back on Home shows the toast and does not exit', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t,
        overrides: _screenOverrides(auth),
        initialLocation: Routes.home);
    await t.pumpAndSettle();

    await _systemBack(t);
    expect(find.text('Press back again to exit'), findsOneWidget);
  });

  testWidgets('second back on Home inside the window requests an exit', (t) async {
    final auth = await _signedIn();
    await pumpPgApp(t,
        overrides: _screenOverrides(auth),
        initialLocation: Routes.home);
    await t.pumpAndSettle();

    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (c) async {
        calls.add(c);
        return null;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _systemBack(t);
    await _systemBack(t);

    expect(calls.any((c) => c.method == 'SystemNavigator.pop'), isTrue);
  });
}
