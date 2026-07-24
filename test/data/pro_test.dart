import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

void main() {
  test('ServiceType exposes label/emoji/unit and round-trips', () {
    expect(ServiceType.walker.label, 'Dog Walker');
    expect(ServiceType.walker.unit, 'walk');
    expect(ServiceType.fromStorage('groomer'), ServiceType.groomer);
    expect(ServiceType.fromStorage('nonsense'), ServiceType.walker); // safe default
  });

  test('Pro toMap omits uid/updatedAt; fromMap restores', () {
    const p = Pro(uid: 'u1', name: 'Aarav', area: 'Bandra West', bio: 'Friendly walker',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 4);
    final m = p.toMap();
    expect(m.containsKey('uid'), isFalse);
    expect(m.containsKey('updatedAt'), isFalse);
    expect(m['serviceType'], 'walker');
    final back = Pro.fromMap('u1', m);
    expect(back.name, 'Aarav');
    expect(back.rate, 250);
    expect(back.serviceType, ServiceType.walker);
    expect(back.unit, 'walk');
  });

  test('Pro toMap never writes the server-owned trust fields', () {
    // A pro must not be able to grant themselves a verified badge or a rating
    // by editing their own listing; firestore.rules rejects writes containing
    // these keys, so toMap must leave them out entirely (the repository writes
    // with merge:true, so the server's values survive).
    const p = Pro(uid: 'u1', name: 'Aarav', area: 'Bandra West', bio: 'Friendly walker',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 4,
        verified: true, rating: 5.0, reviewCount: 99);
    final m = p.toMap();
    expect(m.containsKey('verified'), isFalse);
    expect(m.containsKey('rating'), isFalse);
    expect(m.containsKey('reviewCount'), isFalse);
  });

  test('Pro reads verified back from Firestore', () {
    expect(Pro.fromMap('u1', {'name': 'Aarav', 'verified': true}).verified, isTrue);
    expect(Pro.fromMap('u1', {'name': 'Aarav'}).verified, isFalse); // absent => not verified
  });
}
