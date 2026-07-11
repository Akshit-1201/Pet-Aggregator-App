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
    expect(m['rating'], 0.0);
    final back = Pro.fromMap('u1', m);
    expect(back.name, 'Aarav');
    expect(back.rate, 250);
    expect(back.serviceType, ServiceType.walker);
    expect(back.unit, 'walk');
  });
}
