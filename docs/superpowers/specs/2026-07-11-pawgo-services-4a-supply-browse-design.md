# Pawgo Slice 4a: Services — Supply & Browse — Design

> **Status:** approved design (2026-07-11). First of two sub-slices of the Services pillar (Phase 4). Built on the live Firebase backend — **no mock data**. Slice 4b (booking & payment) follows and builds on this.

## Goal

Stand up the **supply and browse** side of the Services marketplace on live Firestore: a Service-Professional user creates a real listing, and pet parents browse live pros by category and view a pro's profile. No booking yet (the "Book" button lands on a friendly "booking coming next" snackbar, wired to the real flow in Slice 4b).

Screens match `design/Pawgo Prototype.dc.html` (Services list lines 549–589, Pro profile 591–628), plus one new **Pro-setup** screen (the supply side the prototype omits).

## Scope

**In scope**
- `pros/{uid}` Firestore collection; `Pro` + `ServiceType` models; `ProRepository` interface + Firestore impl + in-memory fake; providers.
- **ProSetupScreen** — a `servicePro` user creates/edits their listing (service type, rate, experience, bio).
- **ServicesListScreen** — replaces the Services tab placeholder; category filter tiles + live pro cards; a "Set up your services" banner for a servicePro without a listing.
- **ProProfileScreen** — view a pro (stats, About, Reviews-empty); bottom bar with chat + "Book" (both → `showComingSoon` this slice).
- `firestore.rules` for `pros` + deploy; routes.
- TDD with in-memory fakes; emulator integration test extended for `pros`.

**Out of scope (Slice 4b or later)**
- Booking, payment, confirmation, and the `bookings` collection (Slice 4b).
- Review writing + the Rate&Review screen, real rating aggregation (a pro's `rating`/`reviewCount` stay 0 → shown as "New").
- Chat, pro photos/Storage, real geo distance (cards omit distance or show area).

## Firestore data model

```
pros/{uid}                 // doc id == the servicePro user's uid (one listing per pro)
  ownerId         : string // == uid
  name            : string // denormalised from the user profile
  area            : string // denormalised from the user profile
  serviceType     : string // "walker" | "sitter" | "groomer" | "trainer"
  rate            : int    // ₹ per unit
  experienceYears : int
  bio             : string
  rating          : double // 0 until reviews exist (shown as "New")
  reviewCount     : int    // 0
  updatedAt       : timestamp
```

`upsertPro` uses `set(..., merge: true)`; the setup screen pre-fills from the existing listing (`currentProProvider`) so `rating`/`reviewCount` are preserved across edits. `unit` (walk/visit/session) is derived from `serviceType`, not stored.

## Models (`lib/data/models/`)

- `enum ServiceType { walker, sitter, groomer, trainer }` with `String get label` (e.g. "Dog Walker"), `String get emoji`, `String get unit` (e.g. "walk"), `String get storageKey`, and `static ServiceType fromStorage(String)`.
- `class Pro { final String uid, name, area, bio; final ServiceType serviceType; final int rate, experienceYears, reviewCount; final double rating; const Pro({...}); Map<String,dynamic> toMap(); factory Pro.fromMap(String uid, Map<String,dynamic>); }` — `toMap` omits `uid`/`updatedAt` (repo adds `updatedAt`).

## Repository seam (same pattern as pets/swipes)

`lib/data/repositories/pro_repository.dart`:
```dart
abstract interface class ProRepository {
  Future<void> upsertPro(Pro pro);
  Stream<Pro?> watchPro(String uid);
  Stream<List<Pro>> watchPros();
}
```
- `FirestoreProRepository` under `repositories/firebase/` (`pros` collection, doc id = uid, `watchPros` orders by `updatedAt` desc).
- `InMemoryProRepository` fake in `test/support/fakes.dart`.
- Providers (`providers.dart`): `proRepositoryProvider`; `prosProvider` → `StreamProvider<List<Pro>>` (all pros); `currentProProvider` → `StreamProvider<Pro?>` (the signed-in user's own listing via `watchPro(uid)`, null if none).

## Screens (`features/services/`)

1. **ProSetupScreen** (`ConsumerStatefulWidget`) — title "Offer your services"; a 4-way `ServiceType` selector (chips), `PgTextField`s for rate (number), experience (number), and a multiline bio. Pre-fills from `currentProProvider` when editing. **Save** → `upsertPro(Pro(uid, name+area from profile, serviceType, rate, experienceYears, bio, rating/reviewCount preserved-or-0))` → `context.go(Routes.services)`. Basic validation (rate > 0).
2. **ServicesListScreen** (`ConsumerStatefulWidget`, replaces `PlaceholderTab(title:'Services')`) — peach header "Services near you / Verified walkers, sitters & groomers"; a row of 4 category tiles (tapping toggles a local `ServiceType? _filter` in state); a "Recommended" section listing pro cards from `prosProvider` filtered by the selected category. Each card (avatar placeholder, name + ✓, `serviceType.label · {exp} yrs`, rating "★ {rating} ({reviewCount})" or "New", `₹{rate}/{unit}`, "Book" chip) → tap navigates to **ProProfile** (`context.push(Routes.servicePro, extra: pro)`); the "Book" chip → `showComingSoon(context, 'Booking')`. Empty state ("No pros nearby yet"). If `currentProProvider` is null **and** the user's role is `servicePro`, show a "Set up your services →" banner → `Routes.proSetup`.
3. **ProProfileScreen** (`ConsumerWidget`, `Pro` via `state.extra`) — amber header + a card (name + ✓, `serviceType.label · {area}`, rating badge: "New" when `reviewCount == 0` else "★ {rating} · {reviewCount} reviews"); a stats row (experience / rate); an "About" section (`bio`); a "Reviews" section ("No reviews yet"). Bottom bar: a chat button → `showComingSoon(context, 'Chat')` and a "Book · ₹{rate}" button → `showComingSoon(context, 'Booking')` (Slice 4b rewires this to `/booking`).

## Routing

- Services branch builder → `ServicesListScreen` (replaces `PlaceholderTab`).
- Add `Routes.proSetup = '/pro-setup'` and `Routes.servicePro = '/service-pro'` as top-level **protected** routes; `/service-pro` reads the `Pro` from `state.extra`.

## Security rules (`firestore.rules`, deploy via CLI)

```
match /pros/{uid} {
  allow read: if request.auth != null;
  allow write: if request.auth != null && request.auth.uid == uid;
}
```

## Testing

TDD with in-memory fakes via `pumpPgApp` overrides:
- `Pro`/`ServiceType` serialization round-trip.
- `InMemoryProRepository` (upsert; watchPro; watchPros emits).
- `ProSetupScreen`: filling the form + Save calls `upsertPro` with the right fields.
- `ServicesListScreen`: renders live pro cards; category filter narrows the list; the setup banner appears for a servicePro with no listing; "Book" shows the coming-soon snackbar.
- `ProProfileScreen`: renders the pro + "New" rating; "Book"/chat show coming-soon.
- Extend `integration_test/firebase_repos_test.dart`: `upsertPro` then `watchPro`/`watchPros` round-trip against the Firestore emulator with the new rules.

## Prerequisites

None new — Firestore + Email/Password are live. New rules deploy via the CLI (authenticated).

## Deliverable / definition of done

A Service-Professional account sets up a listing (persists in `pros`); any signed-in user browses the Services tab, filters by category, and opens a pro's profile — all live from Firestore. `flutter analyze` clean, `flutter test` green (fakes), emulator integration test passes with the new rules, debug APK builds.
