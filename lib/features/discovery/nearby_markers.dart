import '../../core/maps/area_geo.dart';
import '../../core/router/routes.dart';
import '../../data/models/homestay.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/pro.dart';

enum NearbyLayer { pets, pros, homestays }

enum PetPinFilter { all, dogs, cats, vaccinated }

const double petHue = 25.0;
const double proHue = 210.0;
const double homestayHue = 120.0;

/// Plain pin data the map screen turns into google_maps Markers.
/// Pure Dart on purpose — unit-testable without the map SDK.
class PinSpec {
  final String id, title, snippet, route;
  final Object extra;
  final double lat, lng, hue;
  const PinSpec({
    required this.id, required this.title, required this.snippet,
    required this.route, required this.extra,
    required this.lat, required this.lng, required this.hue,
  });
}

List<PinSpec> buildPins({
  required NearbyLayer layer,
  required PetPinFilter petFilter,
  required List<PetProfile> pets,
  required List<Pro> pros,
  required List<Homestay> homestays,
}) {
  switch (layer) {
    case NearbyLayer.pets:
      final filtered = pets.where((p) => switch (petFilter) {
            PetPinFilter.all => true,
            PetPinFilter.dogs => p.species == Species.dog,
            PetPinFilter.cats => p.species == Species.cat,
            PetPinFilter.vaccinated => p.vaccinated,
          });
      return [
        for (final p in filtered)
          _spec('pet_${p.id}', p.name, '${p.breed} · ${p.area}', Routes.petProfile, p,
              p.area, p.id, petHue),
      ];
    case NearbyLayer.pros:
      return [
        for (final p in pros)
          _spec('pro_${p.uid}', p.name, '${p.serviceType.label} · ₹${p.rate}/${p.unit}',
              Routes.servicePro, p, p.area, p.uid, proHue),
      ];
    case NearbyLayer.homestays:
      return [
        for (final h in homestays)
          _spec('home_${h.uid}', h.homeName, '${h.hostName} · ₹${h.ratePerNight}/night',
              Routes.host, h, h.area, h.uid, homestayHue),
      ];
  }
}

PinSpec _spec(String id, String title, String snippet, String route, Object extra,
    String area, String seedId, double hue) {
  final pos = latLngForArea(area, seedId);
  return PinSpec(id: id, title: title, snippet: snippet, route: route, extra: extra,
      lat: pos.lat, lng: pos.lng, hue: hue);
}
