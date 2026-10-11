import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the pro and shows New rating; chat button opens a conversation', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    const pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West',
        bio: 'Friendly reliable walker.', serviceType: ServiceType.walker,
        rate: 250, experienceYears: 4);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    ], initialLocation: Routes.servicePro, extra: pro);
    await tester.pumpAndSettle();

    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Friendly reliable walker.'), findsOneWidget);
    expect(find.textContaining('New'), findsWidgets); // no reviews yet

    await tester.tap(find.text('💬'));
    await tester.pumpAndSettle();
    expect(find.text('Message…'), findsOneWidget); // conversation composer hint
  });

  // Client report: "once you open the profile page of a dog walker the buttons
  // on top become unresponsive". The info card is pulled up 40px with
  // Transform.translate, which moves its hit area too; with a fixed 120px
  // header, a notched iPhone's ~59px safe area pushed the back/⋯ buttons into
  // that band and the card swallowed the taps.
  testWidgets('top buttons stay tappable under a notched-iPhone safe area', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 59);
    addTearDown(tester.view.resetPadding);
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    const pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West',
        bio: 'b', serviceType: ServiceType.walker, rate: 250, experienceYears: 4);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    ], initialLocation: Routes.servicePro, extra: pro);
    await tester.pumpAndSettle();

    // A tap that lands on the card instead would warn and open nothing.
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Report or block'), findsOneWidget);
  });

  testWidgets('messaging your own listing explains instead of doing nothing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final me = auth.currentUser!.uid;
    final pro = Pro(uid: me, name: 'Me', area: 'Bandra West',
        bio: 'b', serviceType: ServiceType.walker, rate: 250, experienceYears: 4);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    ], initialLocation: Routes.servicePro, extra: pro);
    await tester.pumpAndSettle();

    await tester.tap(find.text('💬'));
    await tester.pump();
    expect(find.textContaining('your own listing'), findsOneWidget);
    expect(find.text('Message…'), findsNothing);
  });
}
