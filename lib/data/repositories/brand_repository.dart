import '../models/brand.dart';

abstract interface class BrandRepository {
  Future<void> upsertBrand(Brand brand);
  Stream<Brand?> watchBrand(String uid);
  Stream<List<Brand>> watchBrands();
}
