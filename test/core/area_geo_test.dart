import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/maps/area_geo.dart';

void main() {
  test('centroidFor returns the table entry, and the fallback for unknowns', () {
    expect(centroidFor('Khar'), (lat: 19.0728, lng: 72.8326));
    expect(centroidFor('Atlantis'), areaCentroids[fallbackArea]);
    expect(centroidFor(''), areaCentroids[fallbackArea]);
  });

  test('jitterFor is deterministic, bounded, and varies by id', () {
    final a1 = jitterFor('pet-abc');
    final a2 = jitterFor('pet-abc');
    final b = jitterFor('pet-xyz');
    expect(a1, a2);                                  // deterministic
    expect(a1 == b, isFalse);                        // different ids differ
    expect(a1.lat.abs(), lessThanOrEqualTo(0.0022)); // bounded
    expect(a1.lng.abs(), lessThanOrEqualTo(0.0022));
    expect(jitterFor(''), (lat: 0.0, lng: 0.0));     // empty id -> no jitter
  });

  test('latLngForArea composes centroid + jitter', () {
    final c = centroidFor('Juhu');
    final j = jitterFor('p1');
    expect(latLngForArea('Juhu', 'p1'), (lat: c.lat + j.lat, lng: c.lng + j.lng));
  });

  test('areaNames lists every centroid area', () {
    expect(areaNames, containsAll(['Bandra West', 'Khar', 'Juhu', 'Powai']));
    expect(areaNames.length, areaCentroids.length);
  });
}
