// test/data/homestay_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';

void main() {
  test('HomeType + Amenity expose label/emoji and round-trip', () {
    expect(HomeType.apartment.label, 'Apartment');
    expect(HomeType.fromStorage('villa'), HomeType.villa);
    expect(HomeType.fromStorage('nonsense'), HomeType.apartment); // safe default
    expect(Amenity.nearPark.label, 'Near park');
    expect(Amenity.fromStorageList(['nearPark', 'residentDog', 'bogus']),
        [Amenity.nearPark, Amenity.residentDog]); // unknown keys ignored
  });

  test('Homestay toMap omits uid/updatedAt, writes ownerId; fromMap restores', () {
    const h = Homestay(uid: 'u1', homeName: "Meera's Home", hostName: 'Meera Iyer',
        area: 'Bandra West', about: 'Spacious 2BHK.', homeType: HomeType.apartment,
        ratePerNight: 900, amenities: [Amenity.nearPark, Amenity.residentDog]);
    final m = h.toMap();
    expect(m.containsKey('uid'), isFalse);
    expect(m.containsKey('updatedAt'), isFalse);
    expect(m['ownerId'], 'u1');
    expect(m['homeType'], 'apartment');
    expect(m['amenities'], ['nearPark', 'residentDog']);
    expect(m['verified'], false);
    expect(m['rating'], 0.0);
    final back = Homestay.fromMap('u1', m);
    expect(back.homeName, "Meera's Home");
    expect(back.hostName, 'Meera Iyer');
    expect(back.ratePerNight, 900);
    expect(back.homeType, HomeType.apartment);
    expect(back.amenities, [Amenity.nearPark, Amenity.residentDog]);
    expect(back.verified, isFalse);
  });
}
