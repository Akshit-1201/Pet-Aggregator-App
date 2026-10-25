enum BrandCategory {
  treats('treats', 'Treats', '🍪'),
  food('food', 'Food', '🥣'),
  accessories('accessories', 'Accessories', '🧶'),
  care('care', 'Care', '🧴');

  final String storageKey, label, emoji;
  const BrandCategory(this.storageKey, this.label, this.emoji);

  static BrandCategory fromStorage(String key) =>
      BrandCategory.values.firstWhere((c) => c.storageKey == key, orElse: () => BrandCategory.treats);
}

/// Where a brand can get an order to. [short] fills the facts row on the brand
/// page ("City-wide" over "delivery").
enum BrandDelivery {
  cityWide('cityWide', 'Delivers across Mumbai', 'City-wide'),
  nearby('nearby', 'Delivers to nearby areas', 'Nearby'),
  pickup('pickup', 'Pickup only', 'Pickup');

  final String storageKey, label, short;
  const BrandDelivery(this.storageKey, this.label, this.short);

  static BrandDelivery fromStorage(String key) =>
      BrandDelivery.values.firstWhere((d) => d.storageKey == key, orElse: () => BrandDelivery.cityWide);
}

class BrandProduct {
  /// Stable within its brand, so editing one product doesn't shuffle the rest.
  final String id, name, photoUrl;
  final int price;

  const BrandProduct({required this.id, required this.name, required this.price, this.photoUrl = ''});

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'price': price, 'photoUrl': photoUrl};

  factory BrandProduct.fromMap(Map<String, dynamic> m) => BrandProduct(
        id: (m['id'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        price: ((m['price'] ?? 0) as num).toInt(),
        photoUrl: (m['photoUrl'] ?? '') as String,
      );
}

/// A homegrown pet business. v1 is a catalogue: parents order by messaging the
/// brand, so there is no stock, cart or checkout here.
class Brand {
  /// firestore.rules checks each product photo individually and rules can't
  /// loop, so this cap is also written into the rules.
  static const int maxProducts = 10;

  final String uid, name, area, about, logoUrl;
  final BrandCategory category;
  final BrandDelivery delivery;

  /// Year the brand started; 0 when not given.
  final int sinceYear;
  final List<BrandProduct> products;
  final bool verified;

  const Brand({
    required this.uid, required this.name, required this.area, required this.category,
    this.about = '', this.logoUrl = '', this.delivery = BrandDelivery.cityWide,
    this.sinceYear = 0, this.products = const [], this.verified = false,
  });

  /// The cheapest product, for "from ₹X" on the list card; 0 with no products.
  int get fromPrice => products.isEmpty
      ? 0
      : products.map((p) => p.price).reduce((a, b) => a < b ? a : b);

  /// The brand's own editable fields — deliberately **excludes** `verified`,
  /// which only staff grant (Admin SDK). firestore.rules rejects any client
  /// write that touches it, and the repository merges, so the server's value
  /// survives a save.
  Map<String, dynamic> toMap() => {
        'ownerId': uid,
        'name': name,
        'area': area,
        'about': about,
        'logoUrl': logoUrl,
        'category': category.storageKey,
        'delivery': delivery.storageKey,
        'sinceYear': sinceYear,
        'products': products.map((p) => p.toMap()).toList(),
      };

  factory Brand.fromMap(String uid, Map<String, dynamic> m) => Brand(
        uid: uid,
        name: (m['name'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        about: (m['about'] ?? '') as String,
        logoUrl: (m['logoUrl'] ?? '') as String,
        category: BrandCategory.fromStorage((m['category'] ?? 'treats') as String),
        delivery: BrandDelivery.fromStorage((m['delivery'] ?? 'cityWide') as String),
        sinceYear: ((m['sinceYear'] ?? 0) as num).toInt(),
        products: ((m['products'] ?? const []) as List)
            .whereType<Map>()
            .map((p) => BrandProduct.fromMap(Map<String, dynamic>.from(p)))
            .toList(),
        verified: (m['verified'] ?? false) as bool,
      );
}
