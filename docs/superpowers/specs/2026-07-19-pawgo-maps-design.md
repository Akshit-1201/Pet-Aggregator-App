# Pawgo Slice 9: Maps — Design

> **Status:** approved design (2026-07-19). Second of the deferred integrations. A real Google Map replaces the faux `NearbyMapScreen`, showing nearby pets, pros, and homestays around the user's area. Built on the live backend.

## Goal

Replace the gradient-and-fake-pins Nearby screen with a real **Google Map**: pins for pets (default), pros, and homestays, positioned by **area centroid + deterministic jitter**, with working filter chips, a layer-aware bottom sheet, and deep-links from pins to the right profile screens. Also make the onboarding **LocationScreen honest** — a real area picker instead of hardcoding everyone to 'Bandra West'.

## Design decisions (settled during brainstorming)

- **Coordinates come from an area-centroid lookup, not GPS.** A built-in table of ~10 Mumbai neighbourhoods → `(lat, lng)`; every pet/pro/homestay pins at its area's centre plus a small **deterministic jitter** (±~250 m, seeded by the doc id) so pins don't stack. This makes the app's own privacy copy literal ("we only ever share your approximate area — never your exact address"). No new package, no runtime permission, no data migration — works for every existing doc. Device GPS + blue-dot is deferred to its own later slice.
- **Three pin layers: pets (default), pros, homestays.** The existing static filter row becomes real: `All pets / 🐶 Dogs / 🐱 Cats / ✓ Vaccinated / 🧑 Pros / 🏡 Homestays` — the first four filter the pet layer, the last two switch the layer. The bottom sheet follows the selected layer.
- **Markers are colored default pins** (brand-orange pets, azure pros, green homestays) with an `InfoWindow` (name + detail line); tapping the info window deep-links (pet → `/pet-profile`, pro → `/service-pro`, homestay → `/host`). Custom emoji-bitmap pins are deferred polish.
- **Camera centres on MY area's centroid** (`currentUserProfileProvider.area`, fallback Bandra West), zoom 13.5.
- **All map logic is pure functions** (centroids, jitter, marker building, filtering) in files that do NOT import the map SDK where avoidable — unit-testable without a map.
- **`geoflutterfire_plus` stays unused** this slice (no radius queries needed at Mumbai scale; pins filter client-side). The dependency stays declared (pre-declared like razorpay/fcm).
- **LocationScreen becomes a real area picker** (the centroid table's areas as a selectable list; Continue saves via the existing `updateArea`). The "Allow while using app" button goes away — there is no GPS to allow yet.
- **Deferred:** device GPS/blue-dot; custom emoji marker bitmaps; dark map style JSON; geo/radius queries; map search (bar stays a stub); pro/homestay sub-filters.

## Scope

**In scope**
- `lib/core/maps/area_geo.dart` — pure area→centroid table + `jitterFor` + `latLngForArea` (plain `(double, double)` records, no SDK import).
- `lib/features/discovery/nearby_markers.dart` — pure marker-spec building for the three layers + pet filters (species/vaccinated), returning plain data the screen maps to `Marker`s.
- `NearbyMapScreen` rebuild: real `GoogleMap`, real chips, layer-aware bottom sheet, deep-links (incl. fixing the pets row's "coming soon" → real Pet-profile).
- `LocationScreen` area picker (saves the real choice).
- Android manifest `com.google.android.geo.API_KEY` + owner-side Maps SDK enablement + a restricted API key (automated via REST if permitted; console walkthrough otherwise).
- TDD on the pure layer + screen chrome; manual on-device map verification.

**Out of scope (later)**
- Device GPS, the my-location blue dot, and the runtime permission flow.
- Custom marker bitmaps (emoji pins), marker clustering, dark-mode map styling.
- Geo/radius queries (`geoflutterfire_plus`), map search, distance labels ("0.6 km" stays derived-from-nothing nowhere — distance chips like "≤ 2 km" are dropped from the row since we have no real distances).
- Storing lat/lng on documents (a future GPS slice may add it).

## Area geo table (`lib/core/maps/area_geo.dart`)

```dart
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
```

- `GeoPoint centroidFor(String area)` — exact-match lookup, else `areaCentroids[fallbackArea]`.
- `GeoPoint jitterFor(String id)` — deterministic offsets in ±0.0022° (~±250 m) on each axis, derived from `id.hashCode`-style folding of the id's code units (stable across runs; empty id → zero jitter).
- `GeoPoint latLngForArea(String area, String id)` — centroid + jitter.
- `List<String> get areaNames` — the table's keys, for the LocationScreen picker.

## Marker specs (`lib/features/discovery/nearby_markers.dart`)

Pure data layer between repositories and the map widget (imports models + `area_geo`, NOT the map SDK):

```dart
enum NearbyLayer { pets, pros, homestays }
enum PetPinFilter { all, dogs, cats, vaccinated }

class PinSpec {
  final String id, title, snippet, route; // route = Routes.petProfile | servicePro | host
  final Object extra;                     // the PetProfile | Pro | Homestay for the route
  final double lat, lng;
  final double hue;                       // BitmapDescriptor hue (pets 25 orange, pros 210 azure, homestays 120 green)
}

List<PinSpec> buildPins({
  required NearbyLayer layer,
  required PetPinFilter petFilter,
  required List<PetProfile> pets,     // already excludes my own (nearbyPetsProvider)
  required List<Pro> pros,
  required List<Homestay> homestays,
});
```

- Pets layer: applies `petFilter` (dogs/cats by `species`, vaccinated by flag), title `pet.name`, snippet `'${breed} · ${area}'`.
- Pros layer: title `pro.name`, snippet `'${serviceType.label} · ₹${rate}/${unit}'`.
- Homestays layer: title `homeName`, snippet `'${hostName} · ₹${ratePerNight}/night'`.
- Positions via `latLngForArea(x.area, x.id/uid)`.

## `NearbyMapScreen` rebuild

- Replace the gradient `Positioned.fill` + 4 fake `_Pin`s with a `GoogleMap`:
  - `initialCameraPosition`: my area centroid (`currentUserProfileProvider.value?.area`, fallback), zoom 13.5.
  - `markers`: mapped from `buildPins(...)` — `Marker(markerId, position, icon: BitmapDescriptor.defaultMarkerWithHue(spec.hue), infoWindow: InfoWindow(title, snippet, onTap: () => context.push(spec.route, extra: spec.extra)))`.
  - `myLocationEnabled: false`, `zoomControlsEnabled: false` (prototype look).
- Screen becomes a `ConsumerStatefulWidget` holding `NearbyLayer _layer` + `PetPinFilter _petFilter`; chips row: `All pets / 🐶 Dogs / 🐱 Cats / ✓ Vaccinated / 🧑 Pros / 🏡 Homestays` (selected chip = brand fill, matching the current styling; tapping a pet-filter chip also switches the layer back to pets). The old `≤ 2 km` chip is dropped (no real distances).
- Bottom sheet follows the layer (same visual shell):
  - **Pets:** existing rows + Woof button; header `'${n} pets nearby'`; row tap → `context.push(Routes.petProfile, extra: pet)` (replaces the Slice-3 "coming soon").
  - **Pros:** rows (avatar, name, `serviceType.label · ₹rate`) → `Routes.servicePro`.
  - **Homestays:** rows (avatar 🏡, homeName, `hostName · ₹rate/night`) → `Routes.host`.
  - Keep `take(4)` and the "Swipe view →" link (pets layer only).
- Data: `nearbyPetsProvider` (existing), `prosProvider`/`watchPros` (existing), `homestaysProvider` (existing) — no new repositories.

## `LocationScreen` area picker

- Keep the header art + title ('Enable location' → **'Choose your area'**) and the privacy line.
- Body: the `areaNames` list as selectable rows/chips (single-select, default `fallbackArea`).
- One primary button **Continue** → `updateArea(uid, selectedArea)` → `/create-pet` (unchanged navigation). The ghost "Set location manually" button is removed (the picker *is* manual).
- Settings/profile area editing stays out of scope (tracked follow-up).

## API key & Android config (owner-side, automated if possible)

- Enable **Maps SDK for Android** (`maps-android-backend.googleapis.com`) on `pet-aggregator-app` and create an API key **restricted to Android apps + package `com.example.pet_aggregator_app` + the debug-keystore SHA-1**.
- First attempt via REST with the CLI's owner credentials (`serviceusage` enable + `apikeys.googleapis.com` key create with `androidKeyRestrictions`); if the classifier or API refuses, a 5-minute console walkthrough (console.cloud.google.com → APIs & Services → Credentials).
- Key lands in `android/app/src/main/AndroidManifest.xml` inside `<application>`:
  `<meta-data android:name="com.google.android.geo.API_KEY" android:value="…" />`
- A properly restricted Android key is safe to commit. Note in the manifest comment that release builds need the release SHA-1 added to the key's restriction.

## Error handling

- Unknown/empty `area` anywhere → `fallbackArea` centroid (never a crash, never a (0,0) pin).
- Providers already yield `AsyncValue`; the screen uses the established `.value ?? const []` idiom — an unloaded layer simply contributes no pins.
- If the API key is missing/invalid the map renders blank tiles (SDK behaviour) — the chips/sheet still work; the manual walkthrough catches this before merge.

## Testing

TDD with fakes via `pumpPgApp`; the map itself is a platform view (blank in widget tests — if `GoogleMap` misbehaves under `flutter_test`, the plan wraps it behind a trivial injectable builder so tests substitute a `SizedBox`; production code path unchanged):
- **area_geo:** known centroid exact-match; unknown/empty area → fallback; `jitterFor` deterministic (same id → same offset), bounded (±0.0022), different ids differ; `latLngForArea` composes.
- **nearby_markers:** pets layer respects each `PetPinFilter` (dogs/cats/vaccinated/all); pros/homestays layers map title/snippet/route/extra correctly; hues per layer; positions = centroid+jitter of the right area.
- **NearbyMapScreen:** chips render + switch layer/filter (selected styling); bottom sheet shows the right rows per layer; pet row tap → Pet-profile (no more "coming soon"); pro/homestay row taps → their screens; Woof still records a swipe.
- **LocationScreen:** renders the area list; selecting `Khar` + Continue persists `area == 'Khar'` (fake user repo) and navigates on.
- **Manual (emulator, real key):** map tiles render centred on my area; pins appear per layer; info-window tap deep-links; chip switching updates pins.

## Prerequisites

- Owner-side: Maps SDK for Android enabled + a restricted API key (billing is already active). Automated attempt first; console fallback.

## Deliverable / definition of done

The Nearby screen shows a real Google Map centred on my area with pet pins (jittered per area), chips that filter species/vaccinated and switch to pro/homestay layers, a bottom sheet matching the layer, and pins/rows that deep-link to the right profile screens; onboarding lets me actually pick my area and it persists. `flutter analyze` clean, `flutter test` green (pure layer + screens), debug APK builds, and the map renders correctly on the emulator with the restricted key.
