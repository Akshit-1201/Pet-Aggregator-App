# Pawgo Slice 5a: Homestay — Supply & Browse — Design

> **Status:** approved design (2026-07-12). First of two sub-slices of the Homestay pillar (Phase 5). Built on the live Firebase backend — **no mock data**. Slice 5b (Request → Accepted booking flow) follows and builds on this.

## Goal

Stand up the **supply and browse** side of the Homestay boarding pillar on live Firestore: a Homestay-Host user creates a real home listing, and any signed-in user browses live hosts and views a host's profile. No booking yet — the "Request to book" button lands on a friendly "booking coming next" snackbar, wired to the real Request→Accepted flow in Slice 5b (exactly as Slice 4a left "Book").

Screens match `design/Pawgo Prototype.dc.html` (Homestay list lines 704–723, Host profile 726–742), plus one new **HostSetup** screen (the supply side the prototype omits, mirroring ProSetup for Services).

## Entry point & navigation

Homestay is **not** a bottom-nav tab (the app has five: Home, Discover, Services, Community, Profile). The entry point already exists: the Home **🏡 Homestay quick-action tile** (`home_screen.dart:62`) currently mis-routes to `Routes.services` — repoint it to the new `Routes.homestay`.

The Homestay list is a **pushed full-screen route with a back button**, not a tab — the prototype's homestay screen has a ‹ back button (line 708), confirming it. This matches how `nearby` is reached from Home.

## Scope

**In scope**
- `homestays/{uid}` Firestore collection; `Homestay` + `HomeType` + `Amenity` models; `HomestayRepository` interface + Firestore impl + in-memory fake; providers.
- **HostSetupScreen** — a `homestayHost` user creates/edits their listing (home name, home type, rate/night, about, amenities).
- **HomestayListScreen** — a pushed screen off the Home 🏡 tile; live host cards; a "Set up your homestay" banner for a `homestayHost` without a listing.
- **HostProfileScreen** — view a host (amenities, About, Reviews-empty); bottom bar with "Request to book" (→ `showComingSoon` this slice).
- `firestore.rules` for `homestays` + deploy; routes; repoint the Home 🏡 tile.
- TDD with in-memory fakes; emulator integration test extended for `homestays`.

**Out of scope (Slice 5b or later)**
- The Request booking screen, "Send request", the Host-accepted celebration, and the `homestayBookings` collection (Slice 5b).
- Real date-range selection: the list's date/pet bar is a **non-interactive stub** in 5a ("Add dates · 1 pet"); the range picker and per-night total arrive in 5b.
- Real host verification: `verified` defaults to `false` and is only flipped later via the Phase 12 admin/moderation panel. No self-verification.
- Review writing + real rating aggregation (a host's `rating`/`reviewCount` stay 0 → shown as "New").
- Chat, home photos/Storage, real geo distance (cards show area, not distance).

## Firestore data model

```
homestays/{uid}              // doc id == the homestayHost user's uid (one listing per host)
  ownerId      : string      // == uid
  homeName     : string      // "Meera's Home"
  hostName     : string      // denormalised from the user profile ("Meera Iyer")
  area         : string      // denormalised from the user profile
  homeType     : string      // "apartment" | "house" | "villa"
  ratePerNight : int         // ₹ per night
  about        : string
  amenities    : [string]    // subset of the fixed Amenity set (storageKeys)
  verified     : bool        // false by default; the ✓ badge is gated on this
  rating       : double      // 0 until reviews exist (shown as "New")
  reviewCount  : int         // 0
  updatedAt    : timestamp
```

`upsertHomestay` uses `set(..., merge: true)`; the setup screen pre-fills from the existing listing (`currentHomestayProvider`) so `verified`/`rating`/`reviewCount` are preserved across edits. `hostName`/`area` are denormalised from the user profile at save time.

## Models (`lib/data/models/homestay.dart`)

- `enum HomeType { apartment, house, villa }` with `String get label` (e.g. "Apartment"), `String get emoji` (🏡), `String get storageKey`, and `static HomeType fromStorage(String)`.
- `enum Amenity { nearPark, fencedBalcony, residentDog, wfhHost, airConditioned, dailyWalks }` with `String get label` (e.g. "Near park"), `String get emoji`, `String get storageKey`, `static Amenity fromStorage(String)`, and a helper to map a `List<String>` ↔ `List<Amenity>` (unknown keys ignored).
- `class Homestay { final String uid, homeName, hostName, area, about; final HomeType homeType; final int ratePerNight, reviewCount; final List<Amenity> amenities; final bool verified; final double rating; const Homestay({...}); Map<String,dynamic> toMap(); factory Homestay.fromMap(String uid, Map<String,dynamic>); }` — following 4a's `Pro`, the class carries only `uid` (no separate `ownerId` field); `toMap` writes `'ownerId': uid` and omits `uid`/`updatedAt` (repo adds `updatedAt`); `amenities` serialised as a list of `storageKey`s.

## Repository seam (same pattern as pros)

`lib/data/repositories/homestay_repository.dart`:
```dart
abstract interface class HomestayRepository {
  Future<void> upsertHomestay(Homestay homestay);
  Stream<Homestay?> watchHomestay(String uid);
  Stream<List<Homestay>> watchHomestays();
}
```
- `FirestoreHomestayRepository` under `repositories/firebase/` (`homestays` collection, doc id = uid, `watchHomestays` orders by `updatedAt` desc).
- `InMemoryHomestayRepository` fake in `test/support/fakes.dart`.
- Providers (`providers.dart`): `homestayRepositoryProvider`; `homestaysProvider` → `StreamProvider<List<Homestay>>` (all hosts); `currentHomestayProvider` → `StreamProvider<Homestay?>` (the signed-in user's own listing via `watchHomestay(uid)`, null if none).

## Screens (`features/homestay/`)

1. **HostSetupScreen** (`ConsumerStatefulWidget`) — title "List your home"; a home-name `PgTextField`; a `HomeType` chip selector (3-way); a rate/night `PgTextField` (number); a multiline About `PgTextField`; an `Amenity` multi-select chip row. Pre-fills from `currentHomestayProvider` when editing. **Save** → `upsertHomestay(Homestay(uid, homeName, hostName+area from profile, homeType, ratePerNight, about, amenities, verified/rating/reviewCount preserved-or-default))` → `context.go(Routes.homestay)`. Validation: home name non-empty, rate > 0.
2. **HomestayListScreen** (`ConsumerStatefulWidget`) — peach header "Homestay boarding / Verified hosts in {area}" with a back button; a **non-interactive date/pet stub bar** ("Add dates · 1 pet", wired in 5b); host cards from `homestaysProvider`: home photo placeholder, a ✓ "Verified host" badge **only when `verified`**, home name, "{hostName} · {area}", rating "★ {rating}" or "New", "₹{ratePerNight} / night". Each card → `context.push(Routes.host, extra: homestay)`. Empty state ("No hosts nearby yet"). If `currentHomestayProvider` is null **and** the user's role is `homestayHost`, show a "Set up your homestay →" banner → `Routes.hostSetup`.
3. **HostProfileScreen** (`ConsumerWidget`, `Homestay` via `state.extra`) — a home photo header with a back button; a card (homeName + ✓ **only when `verified`**, "Hosted by {hostName} · {area}", "₹{ratePerNight} / night"); an amenity chip row (`homeType.label` + each `amenity.label`); an "About this home" section (`about`); a Pawgo-Verified-host info badge **only when `verified`** (otherwise a subtle "New host" line); a "Recent reviews" section ("No reviews yet"). Bottom bar: "₹{ratePerNight} / night" + a "Request to book" button → `showComingSoon(context, 'Booking')` (Slice 5b rewires this to `/host-request`).

## Routing

- Add `Routes.homestay = '/homestay'`, `Routes.host = '/host'`, and `Routes.hostSetup = '/host-setup'` as top-level **protected** routes; `/host` reads the `Homestay` from `state.extra`.
- Repoint the Home 🏡 Homestay quick-action tile (`home_screen.dart`) from `Routes.services` to `Routes.homestay`.

## Security rules (`firestore.rules`, deploy via CLI)

```
match /homestays/{uid} {
  allow read: if request.auth != null;
  allow write: if request.auth != null && request.auth.uid == uid;
}
```

## Testing

TDD with in-memory fakes via `pumpPgApp` overrides:
- `Homestay`/`HomeType`/`Amenity` serialization round-trip (including the amenities list ↔ storageKeys mapping, unknown keys ignored).
- `InMemoryHomestayRepository` (upsert; watchHomestay; watchHomestays emits).
- `HostSetupScreen`: filling the form + Save calls `upsertHomestay` with the right fields; validation blocks empty name / rate ≤ 0.
- `HomestayListScreen`: renders live host cards; the ✓ badge shows only for `verified` hosts; the setup banner appears for a `homestayHost` with no listing; empty state.
- `HostProfileScreen`: renders the host + "New host" (unverified) and amenity chips; "Request to book" shows the coming-soon snackbar.
- Home 🏡 tile navigates to the Homestay list (router harness).
- Extend `integration_test/firebase_repos_test.dart`: `upsertHomestay` then `watchHomestay`/`watchHomestays` round-trip against the Firestore emulator with the new rules.

## Prerequisites

None new — Firestore + Email/Password are live. New rules deploy via the CLI (authenticated).

## Deliverable / definition of done

A Homestay-Host account sets up a listing (persists in `homestays`); any signed-in user opens the Home 🏡 tile, browses live hosts, filters nothing (browse-all in 5a), and opens a host's profile — all live from Firestore. `flutter analyze` clean, `flutter test` green (fakes), emulator integration test passes with the new rules, debug APK builds.
