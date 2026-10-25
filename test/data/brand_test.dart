import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/brand.dart';
import '../support/fakes.dart';

const _bones = BrandProduct(id: 'p1', name: 'Peanut butter bones', price: 249);
const _cake = BrandProduct(id: 'p2', name: 'Pup birthday cake', price: 699);

const _barkBake = Brand(uid: 'b1', name: 'Bark & Bake', area: 'Bandra West',
    category: BrandCategory.treats, about: 'Small-batch treats',
    delivery: BrandDelivery.cityWide, sinceYear: 2021, products: [_cake, _bones]);

void main() {
  test('Brand round-trips through toMap/fromMap', () {
    final back = Brand.fromMap('b1', _barkBake.toMap());
    expect(back.name, 'Bark & Bake');
    expect(back.category, BrandCategory.treats);
    expect(back.delivery, BrandDelivery.cityWide);
    expect(back.sinceYear, 2021);
    expect(back.products.map((p) => p.name), ['Pup birthday cake', 'Peanut butter bones']);
    expect(back.products.last.price, 249);
  });

  test('toMap never writes the server-owned verified flag', () {
    const b = Brand(uid: 'b1', name: 'X', area: 'Y', category: BrandCategory.food, verified: true);
    expect(b.toMap().containsKey('verified'), isFalse);
    expect(Brand.fromMap('b1', {'verified': true}).verified, isTrue);
  });

  test('fromPrice is the cheapest product, 0 with none', () {
    expect(_barkBake.fromPrice, 249);
    expect(const Brand(uid: 'b', name: 'n', area: 'a', category: BrandCategory.care).fromPrice, 0);
  });

  test('unknown category and delivery fall back safely; junk products are skipped', () {
    final b = Brand.fromMap('b1', {
      'category': 'nonsense', 'delivery': 'teleport',
      'products': ['junk', {'id': 'p', 'name': 'Bone', 'price': 99}],
    });
    expect(b.category, BrandCategory.treats);
    expect(b.delivery, BrandDelivery.cityWide);
    expect(b.products.single.name, 'Bone');
  });

  test('InMemoryBrandRepository upserts and streams brands', () async {
    final repo = InMemoryBrandRepository();
    expect(await repo.watchBrands().first, isEmpty);
    await repo.upsertBrand(_barkBake);
    expect((await repo.watchBrands().first).single.name, 'Bark & Bake');
    expect((await repo.watchBrand('b1').first)!.products.length, 2);
  });
}
