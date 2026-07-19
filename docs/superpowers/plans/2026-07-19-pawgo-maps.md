# Pawgo Slice 9: Maps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A real Google Map on the Nearby screen — pet/pro/homestay pins at area centroids with deterministic jitter, working filter chips, a layer-aware bottom sheet, deep-links — plus an honest area picker on the onboarding LocationScreen.

**Architecture:** All geo/marker logic is pure functions (`area_geo.dart`, `nearby_markers.dart`) with no map-SDK imports; the screen maps `PinSpec`s to `Marker`s. The `GoogleMap` widget is provided through a tiny `mapViewBuilderProvider` seam so widget tests substitute a `SizedBox` (platform views don't render under `flutter_test`). No new packages, no permissions, no rules changes.

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `google_maps_flutter` ^2.17.1 (already a dependency), `flutter_riverpod`, `go_router`. `geoflutterfire_plus` stays unused.

**Spec:** `docs/superpowers/specs/2026-07-19-pawgo-maps-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **`google_maps_flutter` may be imported ONLY in `lib/features/discovery/nearby_map_screen.dart`** (the map feature) and its test. `area_geo.dart` and `nearby_markers.dart` are pure Dart/model files — no SDK import.
- **Coordinates come from `areaCentroids` + deterministic jitter** (±0.0022° ≈ ±250 m, seeded by doc id). Unknown/empty area → `fallbackArea` ('Bandra West') centroid. Never a (0,0) pin, never a crash.
- Layer hues: pets `25.0`, pros `210.0`, homestays `120.0`.
- Chips row (exact labels): `All pets / 🐶 Dogs / 🐱 Cats / ✓ Vaccinated / 🧑 Pros / 🏡 Homestays`. First four select the pets layer + pet filter; last two switch layer. The old `≤ 2 km` chip is dropped.
- Deep-links: pet → `Routes.petProfile` (extra `PetProfile`), pro → `Routes.servicePro` (extra `Pro`), homestay → `Routes.host` (extra `Homestay`).
- Riverpod 3.x (`AsyncValue.value`); `.value ?? const []` idiom for layer sources; screen tests use `pumpPgApp`; async handlers guard `mounted` after `await`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: `area_geo.dart` — centroids, jitter, lookup

**Files:**
- Create: `lib/core/maps/area_geo.dart`
- Test: `test/core/area_geo_test.dart`

**Interfaces:**
- Produces: `typedef GeoPoint = ({double lat, double lng})`; `const Map<String, GeoPoint> areaCentroids`; `const String fallbackArea = 'Bandra West'`; `GeoPoint centroidFor(String area)`; `GeoPoint jitterFor(String id)`; `GeoPoint latLngForArea(String area, String id)`; `List<String> get areaNames`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/area_geo_test.dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/area_geo_test.dart`
Expected: FAIL — `area_geo.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/core/maps/area_geo.dart`**

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/area_geo_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze
git add lib/core/maps/area_geo.dart test/core/area_geo_test.dart
git commit -m "feat: add area centroid table + deterministic jitter (approximate-area geo)"
```

---

### Task 2: `nearby_markers.dart` — pure pin specs for the three layers

**Files:**
- Create: `lib/features/discovery/nearby_markers.dart`
- Test: `test/features/nearby_markers_test.dart`

**Interfaces:**
- Consumes: `latLngForArea` (Task 1); `PetProfile` (`id, name, breed, area, species, vaccinated`), `Pro` (`uid, name, area, serviceType.label, rate, unit`), `Homestay` (`uid, homeName, hostName, area, ratePerNight`); `Routes.petProfile/servicePro/host`.
- Produces: `enum NearbyLayer { pets, pros, homestays }`; `enum PetPinFilter { all, dogs, cats, vaccinated }`; `class PinSpec { String id, title, snippet, route; Object extra; double lat, lng, hue; }`; `const petHue = 25.0; proHue = 210.0; homestayHue = 120.0;`; `List<PinSpec> buildPins({required NearbyLayer layer, required PetPinFilter petFilter, required List<PetProfile> pets, required List<Pro> pros, required List<Homestay> homestays})`.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/nearby_markers_test.dart`
Expected: FAIL — `nearby_markers.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/features/discovery/nearby_markers.dart`**

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/nearby_markers_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze
git add lib/features/discovery/nearby_markers.dart test/features/nearby_markers_test.dart
git commit -m "feat: add pure pin-spec builder for the three nearby layers"
```

---

### Task 3: `LocationScreen` — honest area picker

**Files:**
- Modify: `lib/features/auth/location_screen.dart` (full rewrite below)
- Test: `test/features/location_screen_test.dart` (replace the existing test)

**Interfaces:**
- Consumes: `areaNames`, `fallbackArea` (Task 1); existing `userRepositoryProvider.updateArea`, `authRepositoryProvider`, `PgPrimaryButton`, `Routes.createPet`.

- [ ] **Step 1: Replace the failing test**

Replace the whole of `test/features/location_screen_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('picking an area persists it and continues to Create Pet', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(
        uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com', area: '', role: Role.petParent));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    ], initialLocation: Routes.location);
    await tester.pumpAndSettle();

    expect(find.text('Choose your area'), findsOneWidget);
    await tester.tap(find.text('Khar'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final profile = await users.watchUser(auth.currentUser!.uid).first;
    expect(profile!.area, 'Khar');
    expect(find.text('Add your pet'), findsOneWidget); // Create Pet screen
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/location_screen_test.dart`
Expected: FAIL — screen still says 'Enable location' and has no area rows.

- [ ] **Step 3: Rewrite `lib/features/auth/location_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/maps/area_geo.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../data/repositories/providers.dart';

class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key});
  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  String _selected = fallbackArea;
  bool _saving = false;

  Future<void> _continue() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null || _saving) return;
    setState(() => _saving = true);
    await ref.read(userRepositoryProvider).updateArea(uid, _selected);
    if (mounted) context.go(Routes.createPet);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 24, 30, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(
              width: 96, height: 96, alignment: Alignment.center,
              decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
              child: Icon(Icons.location_on, size: 44, color: c.brand))),
            const SizedBox(height: 18),
            Text('Choose your area', textAlign: TextAlign.center,
              style: PgText.poppins(25, FontWeight.w800, color: c.text, ls: -0.4)),
            const SizedBox(height: 8),
            Text(
              'Pawgo shows pets, pros and homestays near you. We only ever share your approximate area — never your exact address.',
              textAlign: TextAlign.center,
              style: PgText.inter(13.5, FontWeight.w400, color: c.muted, height: 1.5)),
            const SizedBox(height: 18),
            Expanded(child: ListView(children: [
              for (final area in areaNames)
                GestureDetector(
                  onTap: () => setState(() => _selected = area),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 9),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _selected == area ? c.brandSoft : null,
                      border: Border.all(
                        color: _selected == area ? c.brand : c.border,
                        width: _selected == area ? 2 : 1),
                      borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Expanded(child: Text(area,
                        style: PgText.inter(14, FontWeight.w600,
                          color: _selected == area ? c.brand : c.text))),
                      if (_selected == area) Icon(Icons.check_circle, size: 18, color: c.brand),
                    ]),
                  ),
                ),
            ])),
            const SizedBox(height: 12),
            PgPrimaryButton(
              label: _saving ? 'Saving…' : 'Continue',
              onPressed: _saving ? () {} : _continue),
          ]),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/location_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Full suite + analyze + commit**

Run `flutter test` (the signup funnel navigates through this screen — confirm no regression; if another test taps the removed 'Allow while using app' button, update that tap to select an area + 'Continue' without weakening its assertions) and `flutter analyze`.
```bash
git add lib/features/auth/location_screen.dart test/features/location_screen_test.dart
git commit -m "feat: LocationScreen becomes a real area picker (persists the chosen area)"
```

---

### Task 4: `NearbyMapScreen` rebuild — real map, chips, layer sheet, deep-links

**Files:**
- Modify: `lib/features/discovery/nearby_map_screen.dart` (full rewrite below)
- Test: `test/features/nearby_map_screen_test.dart` (replace the existing test)

**Interfaces:**
- Consumes: `buildPins`/`NearbyLayer`/`PetPinFilter`/`PinSpec` + hues (Task 2), `centroidFor` (Task 1), `nearbyPetsProvider`, `prosProvider`, `homestaysProvider`, `currentUserProfileProvider`, `swipeRepositoryProvider`, `authRepositoryProvider`, `Routes`.
- Produces: `typedef MapViewBuilder = Widget Function(CameraPosition initialCamera, Set<Marker> markers)`; `final mapViewBuilderProvider = Provider<MapViewBuilder>(...)` (in the same file; tests override it with a stub).

- [ ] **Step 1: Replace the failing test**

Replace the whole of `test/features/nearby_map_screen_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/discovery/nearby_map_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  Future<InMemoryProRepository> seededPros() async {
    final r = InMemoryProRepository();
    await r.upsertPro(const Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Juhu', bio: 'b',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 4));
    return r;
  }

  const meera = Homestay(uid: 'h1', homeName: "Meera's Home", hostName: 'Meera Iyer',
      area: 'Worli', about: 'a', homeType: HomeType.apartment, ratePerNight: 900);

  Future<void> pump(WidgetTester tester, {required InMemoryProRepository pros}) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('owner-b'))),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
      proRepositoryProvider.overrideWithValue(pros),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository([meera])),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      mapViewBuilderProvider.overrideWithValue((cam, markers) => const SizedBox.expand()),
    ], initialLocation: Routes.nearby);
    await tester.pumpAndSettle();
  }

  testWidgets('pets layer lists nearby pets; a row opens the Pet profile', (tester) async {
    await pump(tester, pros: await seededPros());
    expect(find.textContaining('pets nearby'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);

    await tester.tap(find.text('Bruno'));
    await tester.pumpAndSettle();
    expect(find.text('Send a Woof 👋'), findsOneWidget); // Pet-profile screen
  });

  testWidgets('chips switch to pros and homestays layers', (tester) async {
    await pump(tester, pros: await seededPros());

    await tester.tap(find.text('🧑 Pros'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pros nearby'), findsOneWidget);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Bruno'), findsNothing);

    await tester.tap(find.text('🏡 Homestays'));
    await tester.pumpAndSettle();
    expect(find.textContaining('homestays nearby'), findsOneWidget);
    expect(find.text("Meera's Home"), findsOneWidget);

    await tester.tap(find.text('🐱 Cats'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pets nearby'), findsOneWidget);
    expect(find.text('Mochi'), findsOneWidget);   // the cat fixture
    expect(find.text('Bruno'), findsNothing);     // dogs filtered out
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/nearby_map_screen_test.dart`
Expected: FAIL — `mapViewBuilderProvider` undefined / chips-layer behaviour missing.

- [ ] **Step 3: Rewrite `lib/features/discovery/nearby_map_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/maps/area_geo.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/homestay.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/pro.dart';
import '../../data/models/swipe.dart';
import '../../data/repositories/providers.dart';
import 'nearby_markers.dart';

/// Builds the map view — swapped for a stub in widget tests (GoogleMap is a
/// platform view that cannot render under flutter_test).
typedef MapViewBuilder = Widget Function(CameraPosition initialCamera, Set<Marker> markers);

final mapViewBuilderProvider = Provider<MapViewBuilder>((ref) =>
    (initialCamera, markers) => GoogleMap(
          initialCameraPosition: initialCamera,
          markers: markers,
          myLocationEnabled: false,
          zoomControlsEnabled: false,
        ));

class NearbyMapScreen extends ConsumerStatefulWidget {
  const NearbyMapScreen({super.key});
  @override
  ConsumerState<NearbyMapScreen> createState() => _NearbyMapScreenState();
}

class _NearbyMapScreenState extends ConsumerState<NearbyMapScreen> {
  NearbyLayer _layer = NearbyLayer.pets;
  PetPinFilter _petFilter = PetPinFilter.all;

  static const _chips = <(String, NearbyLayer, PetPinFilter?)>[
    ('All pets', NearbyLayer.pets, PetPinFilter.all),
    ('🐶 Dogs', NearbyLayer.pets, PetPinFilter.dogs),
    ('🐱 Cats', NearbyLayer.pets, PetPinFilter.cats),
    ('✓ Vaccinated', NearbyLayer.pets, PetPinFilter.vaccinated),
    ('🧑 Pros', NearbyLayer.pros, null),
    ('🏡 Homestays', NearbyLayer.homestays, null),
  ];

  void _woof(PetProfile pet) {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    ref.read(swipeRepositoryProvider).recordSwipe(Swipe(
        fromUid: me.uid, petId: pet.id, ownerId: pet.ownerId, direction: SwipeDirection.woof));
  }

  bool _chipSelected((String, NearbyLayer, PetPinFilter?) chip) =>
      chip.$2 == _layer && (chip.$3 == null || chip.$3 == _petFilter);

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final pets = ref.watch(nearbyPetsProvider).value ?? const <PetProfile>[];
    final pros = ref.watch(prosProvider).value ?? const <Pro>[];
    final homestays = ref.watch(homestaysProvider).value ?? const <Homestay>[];
    final myArea = ref.watch(currentUserProfileProvider).value?.area ?? fallbackArea;

    final specs = buildPins(
        layer: _layer, petFilter: _petFilter, pets: pets, pros: pros, homestays: homestays);
    final markers = {
      for (final s in specs)
        Marker(
          markerId: MarkerId(s.id),
          position: LatLng(s.lat, s.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(s.hue),
          infoWindow: InfoWindow(
            title: s.title, snippet: s.snippet,
            onTap: () => context.push(s.route, extra: s.extra)),
        ),
    };
    final c0 = centroidFor(myArea);
    final initialCamera = CameraPosition(target: LatLng(c0.lat, c0.lng), zoom: 13.5);
    final mapBuilder = ref.watch(mapViewBuilderProvider);

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: mapBuilder(initialCamera, markers)),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => context.go(Routes.discover),
                  child: Container(
                    width: 42, height: 42, alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(13)),
                    child: Icon(Icons.chevron_left, color: c.text))),
                const SizedBox(width: 12),
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(16), boxShadow: c.shadow),
                  child: Text('🔍  Search pets near you',
                    style: PgText.inter(14, FontWeight.w500, color: c.muted)))),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: _chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 9),
                itemBuilder: (_, i) {
                  final chip = _chips[i];
                  final sel = _chipSelected(chip);
                  return GestureDetector(
                    onTap: () => setState(() {
                      _layer = chip.$2;
                      if (chip.$3 != null) _petFilter = chip.$3!;
                    }),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      decoration: BoxDecoration(
                        color: sel ? c.brand : c.surface,
                        border: sel ? null : Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(20)),
                      child: Text(chip.$1,
                        style: PgText.inter(12.5, FontWeight.w600,
                          color: sel ? Colors.white : c.text))),
                  );
                },
              ),
            ),
            const Spacer(),
            _sheet(c, pets, pros, homestays),
          ]),
        ),
      ]),
    );
  }

  Widget _sheet(PgColors c, List<PetProfile> pets, List<Pro> pros, List<Homestay> homestays) {
    final filteredPets = [
      for (final p in pets)
        if (switch (_petFilter) {
          PetPinFilter.all => true,
          PetPinFilter.dogs => p.species == Species.dog,
          PetPinFilter.cats => p.species == Species.cat,
          PetPinFilter.vaccinated => p.vaccinated,
        }) p,
    ];
    final (String header, int count) = switch (_layer) {
      NearbyLayer.pets => ('pets nearby', filteredPets.length),
      NearbyLayer.pros => ('pros nearby', pros.length),
      NearbyLayer.homestays => ('homestays nearby', homestays.length),
    };

    return Container(
      decoration: BoxDecoration(
        color: c.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 30, offset: Offset(0, -10))]),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(3)))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$count $header', style: PgText.poppins(16, FontWeight.w700, color: c.text)),
          if (_layer == NearbyLayer.pets)
            GestureDetector(onTap: () => context.go(Routes.discover),
              child: Text('Swipe view →', style: PgText.inter(12.5, FontWeight.w700, color: c.brand))),
        ]),
        const SizedBox(height: 12),
        if (_layer == NearbyLayer.pets)
          for (final p in filteredPets.take(4))
            _row(c, emoji: '🐾', imageUrl: p.photoUrl, title: p.name,
              subtitle: '${p.breed} · ${p.area}',
              onTap: () => context.push(Routes.petProfile, extra: p),
              trailing: GestureDetector(
                onTap: () => _woof(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.brand, c.brand2]),
                    borderRadius: BorderRadius.circular(12)),
                  child: Text('Woof!', style: PgText.poppins(12.5, FontWeight.w700, color: Colors.white))))),
        if (_layer == NearbyLayer.pros)
          for (final p in pros.take(4))
            _row(c, emoji: '🧑', imageUrl: null, title: p.name,
              subtitle: '${p.serviceType.label} · ₹${p.rate}/${p.unit}',
              onTap: () => context.push(Routes.servicePro, extra: p)),
        if (_layer == NearbyLayer.homestays)
          for (final h in homestays.take(4))
            _row(c, emoji: '🏡', imageUrl: null, title: h.homeName,
              subtitle: '${h.hostName} · ₹${h.ratePerNight}/night',
              onTap: () => context.push(Routes.host, extra: h)),
      ]),
    );
  }

  Widget _row(PgColors c, {required String emoji, String? imageUrl, required String title,
      required String subtitle, required VoidCallback onTap, Widget? trailing}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          PgImageSlot(size: 50, circle: true, emoji: emoji, imageUrl: imageUrl),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
          ])),
          if (trailing != null) trailing,
        ]),
      ),
    );
  }
}
```
(The old `_Pin` widget, the gradient fill, and the `pg_snackbar` import are gone — pet rows now navigate for real. The pets sheet row also gains the Slice-8 `photoUrl` thumbnail for free.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/nearby_map_screen_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/discovery/nearby_map_screen.dart test/features/nearby_map_screen_test.dart
git commit -m "feat: real Google Map on Nearby (3 pin layers, live chips, layer sheet, deep-links)"
```
Expected: whole suite green, analyze clean.

---

### Task 5: Maps SDK enablement + restricted API key + manifest (controller-run)

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

> This task is executed by the controller (owner-credential REST, like the Storage setup), NOT a coding subagent. Console fallback documented below.

- [ ] **Step 1: Get the debug-keystore SHA-1**

```powershell
& "$env:JAVA_HOME\bin\keytool.exe" -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android | Select-String "SHA1"
```
(If `JAVA_HOME` is unset, use the JDK bundled with Android Studio: `$env:LOCALAPPDATA\Android\..` or `flutter doctor -v` shows the Java path.) Note the SHA-1, strip the colons for the API call.

- [ ] **Step 2: Enable the APIs (REST with CLI owner creds; console fallback)**

POST `https://serviceusage.googleapis.com/v1/projects/pet-aggregator-app/services/maps-android-backend.googleapis.com:enable` and the same for `apikeys.googleapis.com`.
Console fallback: console.cloud.google.com → APIs & Services → Library → "Maps SDK for Android" → Enable.

- [ ] **Step 3: Create a restricted API key**

POST `https://apikeys.googleapis.com/v2/projects/pet-aggregator-app/locations/global/keys` with:
```json
{
  "displayName": "Pawgo Android Maps",
  "restrictions": {
    "androidKeyRestrictions": {
      "allowedApplications": [{
        "packageName": "com.example.pet_aggregator_app",
        "sha1Fingerprint": "<DEBUG_SHA1_NO_COLONS>"
      }]
    },
    "apiTargets": [{ "service": "maps-android-backend.googleapis.com" }]
  }
}
```
Poll the returned operation; read `response.keyString`.
Console fallback: APIs & Services → Credentials → Create credentials → API key → Edit → restrict to Android apps (package + SHA-1) + API restriction "Maps SDK for Android".

- [ ] **Step 4: Add the key to the manifest**

In `android/app/src/main/AndroidManifest.xml`, inside `<application>` (after the `flutterEmbedding` meta-data):
```xml
        <!-- Restricted to this package + debug SHA-1; add the release SHA-1
             to the key's restriction before a Play release. -->
        <meta-data
            android:name="com.google.android.geo.API_KEY"
            android:value="<KEY_STRING>" />
```

- [ ] **Step 5: Build to verify the native config + commit**

```bash
flutter build apk --debug
git add android/app/src/main/AndroidManifest.xml
git commit -m "chore: add restricted Google Maps API key to the Android manifest"
```
Expected: APK builds (Maps native plugin + key wired).

---

### Task 6: On-device verification + final gate (controller-run)

- [ ] **Step 1: Run on the emulator**

Boot Pixel_10 (lock-cleanup + cold-boot if offline), `flutter install`/`adb install` the fresh debug APK, launch.

- [ ] **Step 2: Manual walkthrough**

Nearby (from Discovery): real tiles render centred on my area; pet pins appear (jittered, not stacked); chips switch Dogs/Cats/Vaccinated/Pros/Homestays and the pins + sheet follow; info-window tap deep-links; pet row → Pet-profile; Woof still records. Onboarding (fresh account): area picker shows, chosen area persists, and the map centres on it.

- [ ] **Step 3: Full green gate**

```bash
flutter test
flutter analyze
flutter build apk --debug
```
Expected: all green. Then final whole-branch review → ff-merge to main.

---

## Self-Review

**Spec coverage:**
- Centroid table + jitter + fallback (`area_geo`) → Task 1. ✓
- Pure pin specs, 3 layers, pet filters, hues, deep-link routes → Task 2. ✓
- LocationScreen honest area picker (saves real choice, removes fake buttons) → Task 3. ✓
- Real GoogleMap, camera on my area, chips (exact labels, `≤ 2 km` dropped), layer-aware sheet, pet-row "coming soon" fixed, info-window deep-links, map-builder test seam → Task 4. ✓
- Maps SDK + restricted key + manifest (+ release-SHA note) → Task 5. ✓
- Manual on-device verification + gate → Task 6. ✓
- Deferred items (GPS, custom pins, dark style, geo queries, search) → none implemented. ✓

**Placeholder scan:** `<DEBUG_SHA1_NO_COLONS>` / `<KEY_STRING>` in Task 5 are runtime-obtained secrets for the controller step, with exact commands to obtain them — not plan gaps. All code steps are complete.

**Type consistency:**
- `GeoPoint`/`centroidFor`/`jitterFor`/`latLngForArea`/`areaNames`/`fallbackArea` defined Task 1, consumed Tasks 2 (positions), 3 (picker list + default), 4 (camera). ✓
- `NearbyLayer`/`PetPinFilter`/`PinSpec`/`buildPins`/hues defined Task 2, consumed Task 4 (markers + sheet filter). Snippet formats in Task 2 tests match Task 4's sheet subtitles. ✓
- `MapViewBuilder`/`mapViewBuilderProvider` defined + consumed Task 4 (screen + test override). ✓
- Existing APIs verified against source: `prosProvider`/`homestaysProvider`/`nearbyPetsProvider`/`currentUserProfileProvider`, `Pro.unit`, `Homestay` fields, `PetProfile` fields + `photoUrl` (Slice 8), `PgImageSlot(imageUrl:)`, `InMemoryHomestayRepository([seed])`, `InMemoryProRepository.upsertPro`, `fixturePets` (Bruno dog / Mochi cat / Simba dog — 'Mochi' is the cats-filter fixture ✓), Pet-profile's `'Send a Woof 👋'` button text (other-owner pet ✓ since fixture owner is 'owner-b'), routes `petProfile`/`servicePro`/`host`. ✓
