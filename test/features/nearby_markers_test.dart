// test/features/nearby_markers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/maps/area_geo.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/features/discovery/nearby_markers.dart';

PetProfile _pet(String id, String name, Species s, {bool vax = true, String area = 'Khar'}) =>
    PetProfile(id: id, ownerId: 'o', name: name, breed: 'B', ageLabel: '2 yrs', sex: 'male',
        area: area, species: s, vaccinated: vax, accentColor: PetProfile.accentFor(name));

void main() {
  final pets = [
    _pet('p1', 'Bruno', Species.dog),
    _pet('p2', 'Mochi', Species.cat, vax: false),
  ];
  const pro = Pro(uid: 'pro1', name: 'Aarav', area: 'Juhu', bio: 'b',
      serviceType: ServiceType.walker, rate: 250, experienceYears: 4);
  const home = Homestay(uid: 'h1', homeName: "Meera's Home", hostName: 'Meera', area: 'Worli',
      about: 'a', homeType: HomeType.apartment, ratePerNight: 900);

  List<PinSpec> pins(NearbyLayer l, [PetPinFilter f = PetPinFilter.all]) => buildPins(
      layer: l, petFilter: f, pets: pets, pros: const [pro], homestays: const [home]);

  test('pets layer maps + respects each filter', () {
    expect(pins(NearbyLayer.pets).length, 2);
    expect(pins(NearbyLayer.pets, PetPinFilter.dogs).single.title, 'Bruno');
    expect(pins(NearbyLayer.pets, PetPinFilter.cats).single.title, 'Mochi');
    expect(pins(NearbyLayer.pets, PetPinFilter.vaccinated).single.title, 'Bruno');
    final b = pins(NearbyLayer.pets, PetPinFilter.dogs).single;
    expect(b.route, Routes.petProfile);
    expect(b.extra, pets.first);
    expect(b.hue, petHue);
    expect(b.snippet, 'B · Khar');
    final expected = latLngForArea('Khar', 'p1');
    expect((lat: b.lat, lng: b.lng), expected);
  });

  test('pros layer maps title/snippet/route/hue', () {
    final p = pins(NearbyLayer.pros).single;
    expect(p.title, 'Aarav');
    expect(p.snippet, 'Dog Walker · ₹250/walk');
    expect(p.route, Routes.servicePro);
    expect(p.extra, pro);
    expect(p.hue, proHue);
  });

  test('homestays layer maps title/snippet/route/hue', () {
    final h = pins(NearbyLayer.homestays).single;
    expect(h.title, "Meera's Home");
    expect(h.snippet, 'Meera · ₹900/night');
    expect(h.route, Routes.host);
    expect(h.extra, home);
    expect(h.hue, homestayHue);
  });
}
