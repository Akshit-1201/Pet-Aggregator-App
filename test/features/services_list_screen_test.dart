import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/brand.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _aarav = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
    serviceType: ServiceType.walker, rate: 250, experienceYears: 4);

const _kavya = Pro(uid: 'pro2', name: 'Kavya Rao', area: 'Bandra', bio: 'Behaviourist',
    serviceType: ServiceType.behaviourist, rate: 1500, experienceYears: 8,
    specialties: [Specialty.anxiety, Specialty.puppies]);

const _barkBake = Brand(uid: 'b1', name: 'Bark & Bake', area: 'Bandra West',
    category: BrandCategory.treats,
    products: [BrandProduct(id: 'p1', name: 'Bones', price: 249), BrandProduct(id: 'p2', name: 'Cake', price: 699)]);
const _freshBowl = Brand(uid: 'b2', name: 'Fresh Bowl Co.', area: 'Andheri',
    category: BrandCategory.food, products: [BrandProduct(id: 'p1', name: 'Meal', price: 180)]);
// No products yet — nothing to order, so it stays out of the list.
const _empty = Brand(uid: 'b3', name: 'Empty Shelf', area: 'Thane', category: BrandCategory.care);

Future<void> _pumpServices(WidgetTester tester, {Role role = Role.petParent,
    List<Pro> pros = const [_aarav, _kavya], List<Brand> brands = const [_barkBake, _freshBowl, _empty]}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com',
      area: 'Khar', role: role));
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    proRepositoryProvider.overrideWithValue(InMemoryProRepository(pros)),
    brandRepositoryProvider.overrideWithValue(InMemoryBrandRepository(brands)),
  ], initialLocation: Routes.services, providesBrandRepository: true);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows six categories including Behaviourist and Home Brands', (tester) async {
    await _pumpServices(tester);
    for (final label in ['Walker', 'Sitter', 'Groomer', 'Trainer', 'Behaviourist', 'Home Brands']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // "Recommended" lists every pro, behaviourists included, with their tags.
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Kavya Rao'), findsOneWidget);
    expect(find.text('Anxiety'), findsOneWidget);
  });

  testWidgets('the Behaviourist tile filters to behaviourists', (tester) async {
    await _pumpServices(tester);
    await tester.tap(find.text('Behaviourist'));
    await tester.pumpAndSettle();
    expect(find.text('Pet behaviourists'), findsOneWidget);
    expect(find.text('Kavya Rao'), findsOneWidget);
    expect(find.text('Aarav Sharma'), findsNothing);
    expect(find.text('₹1500'), findsOneWidget);
    expect(find.text('/consult'), findsOneWidget);
  });

  testWidgets('Home Brands lists brands with products, from their cheapest price', (tester) async {
    await _pumpServices(tester);
    await tester.tap(find.text('Home Brands'));
    await tester.pumpAndSettle();
    expect(find.text('Homegrown in Mumbai'), findsOneWidget);
    expect(find.text('Bark & Bake'), findsOneWidget);
    expect(find.text('₹249'), findsOneWidget);
    expect(find.text('Fresh Bowl Co.'), findsOneWidget);
    expect(find.text('Empty Shelf'), findsNothing);
    expect(find.text('Aarav Sharma'), findsNothing); // pros are hidden here

    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh Bowl Co.'), findsOneWidget);
    expect(find.text('Bark & Bake'), findsNothing);
  });

  testWidgets('tapping a brand opens its page', (tester) async {
    await _pumpServices(tester);
    await tester.tap(find.text('Home Brands'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bark & Bake'));
    await tester.pumpAndSettle();
    expect(find.text('Message to order'), findsOneWidget);
    expect(find.text('Cake'), findsOneWidget);
  });

  testWidgets('a brand owner without a listing sees a set-up banner', (tester) async {
    await _pumpServices(tester, role: Role.brand, brands: const []);
    await tester.tap(find.text('Home Brands'));
    await tester.pumpAndSettle();
    expect(find.text('Set up your brand'), findsOneWidget);
    expect(find.text('No brands here yet — check back soon.'), findsOneWidget);
    await tester.tap(find.text('Set up your brand'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('List your brand'), findsOneWidget);
  });


  testWidgets('lists live pros', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository([_aarav])),
    ], initialLocation: Routes.services);
    await tester.pumpAndSettle();
    expect(find.text('Services near you'), findsOneWidget);
    expect(find.text('Aarav Sharma'), findsOneWidget);
  });

  testWidgets('shows a set-up banner for a servicePro without a listing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com',
        area: 'Khar', role: Role.servicePro));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    ], initialLocation: Routes.services);
    await tester.pumpAndSettle();
    expect(find.text('Set up your services'), findsOneWidget);
  });
}
