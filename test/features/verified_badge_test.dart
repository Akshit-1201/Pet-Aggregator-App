// The verified checkmark used to be drawn unconditionally on both the Services
// list and the Pro profile, and `Pro` had no `verified` field at all — so every
// pro in the marketplace displayed as Pawgo-verified regardless of any vetting.
// These tests pin the badge to the real field in both directions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _base = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West',
    bio: 'Friendly reliable walker.', serviceType: ServiceType.walker,
    rate: 250, experienceYears: 4);

Future<void> _pumpProfile(WidgetTester tester, Pro pro) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
  ], initialLocation: Routes.servicePro, extra: pro);
  await tester.pumpAndSettle();
}

Future<void> _pumpList(WidgetTester tester, Pro pro) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final pros = InMemoryProRepository();
  await pros.upsertPro(pro);
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    proRepositoryProvider.overrideWithValue(pros),
  ], initialLocation: Routes.services);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Pro profile hides the badge for an unverified pro', (tester) async {
    await _pumpProfile(tester, _base);
    expect(find.byIcon(Icons.verified), findsNothing);
    expect(find.text('New pro · not yet Pawgo-verified'), findsOneWidget);
  });

  testWidgets('Pro profile shows the badge only when the server says verified', (tester) async {
    await _pumpProfile(tester, Pro(uid: _base.uid, name: _base.name, area: _base.area,
        bio: _base.bio, serviceType: _base.serviceType, rate: _base.rate,
        experienceYears: _base.experienceYears, verified: true));
    expect(find.byIcon(Icons.verified), findsOneWidget);
    expect(find.text('Pawgo Verified pro'), findsOneWidget);
    expect(find.text('New pro · not yet Pawgo-verified'), findsNothing);
  });

  testWidgets('Services list hides the badge for an unverified pro', (tester) async {
    await _pumpList(tester, _base);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsNothing);
  });

  testWidgets('Services list shows the badge for a verified pro', (tester) async {
    await _pumpList(tester, Pro(uid: _base.uid, name: _base.name, area: _base.area,
        bio: _base.bio, serviceType: _base.serviceType, rate: _base.rate,
        experienceYears: _base.experienceYears, verified: true));
    expect(find.byIcon(Icons.verified), findsOneWidget);
  });
}
