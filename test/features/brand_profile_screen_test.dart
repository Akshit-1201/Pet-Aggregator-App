import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/brand.dart';
import 'package:pet_aggregator_app/data/models/report.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _barkBake = Brand(uid: 'brand1', name: 'Bark & Bake', area: 'Bandra West',
    category: BrandCategory.treats, about: 'Small-batch treats baked in Bandra.',
    delivery: BrandDelivery.cityWide, sinceYear: 2021, verified: true,
    products: [
      BrandProduct(id: 'p1', name: 'Peanut butter bones', price: 249),
      BrandProduct(id: 'p2', name: 'Pup birthday cake', price: 699),
      BrandProduct(id: 'p3', name: 'Chicken jerky', price: 349),
    ]);

Future<void> _pump(WidgetTester tester, {Brand? brand = _barkBake}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Radhika',
      email: 'me@x.com', area: 'Khar', role: Role.petParent));
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
  ], initialLocation: Routes.brand, extra: brand);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the brand, its facts and every product with its price', (tester) async {
    await _pump(tester);
    expect(find.text('Bark & Bake'), findsOneWidget);
    expect(find.text('Treats · Bandra West'), findsOneWidget);
    expect(find.text('City-wide'), findsOneWidget);
    expect(find.text('Since 2021'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // product count
    expect(find.text('Pawgo Verified brand'), findsOneWidget);
    for (final p in _barkBake.products) {
      await tester.dragUntilVisible(find.text(p.name), find.byType(Scrollable).first, const Offset(0, -120));
      expect(find.text('₹${p.price}'), findsOneWidget);
    }
  });

  testWidgets('"Message to order" opens a chat with the brand', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Message to order'));
    await tester.pumpAndSettle();
    expect(find.text('Message…'), findsOneWidget); // conversation composer
    expect(find.text('Bark & Bake'), findsOneWidget); // conversation header
  });

  testWidgets('the ⋯ button reports the brand listing', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Report or block this brand'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report this ${ReportTargetType.brand.noun}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ReportReason.spam.label));
    await tester.pumpAndSettle();
    expect(find.text('Thanks — the Pawgo Pets team will take a look.'), findsOneWidget);
  });

  testWidgets('a missing brand shows a not-found page', (tester) async {
    await _pump(tester, brand: null);
    expect(find.text('Brand not found'), findsOneWidget);
  });
}
