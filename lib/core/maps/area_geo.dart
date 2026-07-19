/// Approximate-area geography for the Mumbai market.
///
/// Pawgo never stores exact addresses — every pin is its area's centroid plus
/// a small deterministic jitter, which makes the onboarding privacy promise
/// ("we only ever share your approximate area") literal.
typedef GeoPoint = ({double lat, double lng});

const Map<String, GeoPoint> areaCentroids = {
  'Bandra West':  (lat: 19.0596, lng: 72.8295),
  'Khar':         (lat: 19.0728, lng: 72.8326),
  'Pali Hill':    (lat: 19.0672, lng: 72.8258),
  'Juhu':         (lat: 19.1075, lng: 72.8263),
  'Santacruz':    (lat: 19.0790, lng: 72.8390),
  'Andheri West': (lat: 19.1364, lng: 72.8296),
  'Versova':      (lat: 19.1352, lng: 72.8146),
  'Worli':        (lat: 19.0176, lng: 72.8118),
  'Dadar':        (lat: 19.0178, lng: 72.8478),
  'Powai':        (lat: 19.1176, lng: 72.9060),
};

const String fallbackArea = 'Bandra West';

List<String> get areaNames => areaCentroids.keys.toList();

GeoPoint centroidFor(String area) => areaCentroids[area] ?? areaCentroids[fallbackArea]!;

/// Deterministic offset within ±[_jitterSpan] degrees (~±250 m) per axis.
const double _jitterSpan = 0.0022;

GeoPoint jitterFor(String id) {
  if (id.isEmpty) return (lat: 0.0, lng: 0.0);
  var h1 = 0, h2 = 0;
  for (final u in id.codeUnits) {
    h1 = (h1 * 31 + u) & 0x7fffffff;
    h2 = (h2 * 37 + u) & 0x7fffffff;
  }
  final dLat = (h1 % 1000) / 999.0 * 2 * _jitterSpan - _jitterSpan;
  final dLng = (h2 % 1000) / 999.0 * 2 * _jitterSpan - _jitterSpan;
  return (lat: dLat, lng: dLng);
}

GeoPoint latLngForArea(String area, String id) {
  final c = centroidFor(area);
  final j = jitterFor(id);
  return (lat: c.lat + j.lat, lng: c.lng + j.lng);
}
