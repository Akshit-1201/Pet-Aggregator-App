import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/brand.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

typedef _Setup = ({InMemoryBrandRepository brands, InMemoryStorageRepository storage, String uid});

Future<_Setup> _pumpSetup(WidgetTester tester, {Brand? seed}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final uid = auth.currentUser!.uid;
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(uid: uid, name: 'Neha Shah',
      email: 'me@x.com', area: 'Bandra West', role: Role.brand));
  final brands = InMemoryBrandRepository([
    if (seed != null) Brand.fromMap(uid, seed.toMap()),
  ]);
  final storage = InMemoryStorageRepository();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    brandRepositoryProvider.overrideWithValue(brands),
    proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    imagePickerServiceProvider.overrideWithValue(FakeImagePickerService(Uint8List.fromList([1, 2, 3]))),
    storageRepositoryProvider.overrideWithValue(storage),
  ], initialLocation: Routes.brandSetup, providesBrandRepository: true);
  await tester.pumpAndSettle();
  return (brands: brands, storage: storage, uid: uid);
}

/// The form is a lazy ListView, so rows below the fold aren't built until
/// scrolled to — ensureVisible alone can't find them.
Future<void> _scrollTo(WidgetTester tester, Finder f) =>
    tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);

Future<void> _addProduct(WidgetTester tester, String name, String price, {bool photo = false}) async {
  await _scrollTo(tester, find.byKey(const Key('add-product')));
  await tester.tap(find.byKey(const Key('add-product')));
  await tester.pumpAndSettle();
  if (photo) {
    await tester.tap(find.byKey(const Key('product-photo')));
    await tester.pumpAndSettle();
  }
  final fields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), price);
  await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Add product')));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save brand'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('filling the form and adding products saves a brand', (tester) async {
    final s = await _pumpSetup(tester);

    await tester.tap(find.byKey(const Key('brand-logo')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Bark & Bake'); // name
    await tester.enterText(find.byType(TextField).at(1), '2021'); // since
    await tester.enterText(find.byType(TextField).at(2), 'Small-batch treats.'); // about
    await tester.tap(find.text('🥣 Food'));
    await tester.tap(find.text('Pickup only'));
    await tester.pump();
    await _addProduct(tester, 'Chicken meal', '180', photo: true);
    await _addProduct(tester, 'Fish meal', '220');
    await _save(tester);

    final mine = (await s.brands.watchBrand(s.uid).first)!;
    expect(mine.name, 'Bark & Bake');
    expect(mine.area, 'Bandra West');
    expect(mine.category, BrandCategory.food);
    expect(mine.delivery, BrandDelivery.pickup);
    expect(mine.sinceYear, 2021);
    expect(mine.about, 'Small-batch treats.');
    expect(mine.products.map((p) => p.name), ['Chicken meal', 'Fish meal']);
    expect(mine.fromPrice, 180);
    expect(mine.verified, isFalse);
    // Logo + one product photo, both under the owner's own Storage folder.
    expect(s.storage.uploads.keys, hasLength(2));
    expect(s.storage.uploads.keys.every((k) => k.startsWith('brands/${s.uid}/')), isTrue);
    expect(mine.logoUrl, startsWith('https://fake.storage/brands/${s.uid}/logo_'));
    expect(mine.products.first.photoUrl, startsWith('https://fake.storage/brands/${s.uid}/p_'));
  });

  testWidgets('a brand needs a name and at least one product', (tester) async {
    final s = await _pumpSetup(tester);
    await _save(tester);
    expect(find.text('Enter your brand name.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Bark & Bake');
    await _save(tester);
    expect(find.text('Add at least one product.'), findsOneWidget);
    expect(await s.brands.watchBrand(s.uid).first, isNull);
  });

  testWidgets('an impossible founding year is refused', (tester) async {
    await _pumpSetup(tester);
    await tester.enterText(find.byType(TextField).at(0), 'Bark & Bake');
    await tester.enterText(find.byType(TextField).at(1), '3021');
    await _addProduct(tester, 'Bones', '249');
    await _save(tester);
    expect(find.text('Enter the year you started, like 2021.'), findsOneWidget);
  });

  testWidgets('a product needs a price above 0', (tester) async {
    await _pumpSetup(tester);
    await _addProduct(tester, 'Bones', '0');
    expect(find.text('Enter a price greater than 0.'), findsOneWidget);
  });

  testWidgets('an existing brand loads for editing, and a product can be removed', (tester) async {
    const existing = Brand(uid: 'x', name: 'Knotty Tails', area: 'Thane',
        category: BrandCategory.accessories, products: [
          BrandProduct(id: 'p1', name: 'Rope toy', price: 399),
          BrandProduct(id: 'p2', name: 'Collar', price: 499),
        ]);
    final s = await _pumpSetup(tester, seed: existing);
    expect(find.text('Knotty Tails'), findsOneWidget);
    await _scrollTo(tester, find.text('Rope toy'));
    expect(find.text('Rope toy'), findsOneWidget);

    await _scrollTo(tester, find.byKey(const Key('remove-product-0')));
    await tester.tap(find.byKey(const Key('remove-product-0')));
    await tester.pumpAndSettle();
    await _save(tester);
    final mine = (await s.brands.watchBrand(s.uid).first)!;
    expect(mine.products.single.name, 'Collar');
    expect(mine.category, BrandCategory.accessories);
  });
}
