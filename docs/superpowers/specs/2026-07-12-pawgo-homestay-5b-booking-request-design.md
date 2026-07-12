# Pawgo Slice 5b: Homestay — Request → Accepted — Design

> **Status:** approved design (2026-07-12). Second of two sub-slices of the Homestay pillar (Phase 5); builds on Slice 5a (supply & browse). Built on the live Firebase backend — **no mock data**. There is **no payment screen** — a Homestay booking is a *request* (payments are deferred to Phase 10), and the host-side accept is deferred to a later slice.

## Goal

Let a pet parent request a homestay end to end: from a Host profile → pick a **date range**, which **pet**, and an optional **note to host** → see a **price breakdown** → "Send request" writes a **real `homestayBookings` doc (`status: 'requested'`)** → an honest "Request sent!" confirmation. Wires the "Request to book" button that Slice 5a left as a coming-soon snackbar.

Screens match `design/Pawgo Prototype.dc.html` (Homestay request 745–757, Host accepted 759–770).

## Design decisions (settled during brainstorming)

- **Honest request semantics.** The doc is written with `status: 'requested'` and the confirmation reads "Request sent! … {host} will confirm your dates soon" — **not** "accepted". There is no host to accept yet (a host-side inbox + notifications belong to Phase 7), so claiming acceptance would be a white lie — consistent with Slice 5a's honest-verification choice.
- **Material date-range picker.** Check-in/check-out are chosen via Flutter's built-in `showDateRangePicker` (no new package); nights = range length. Most faithful to the prototype's check-in/check-out cards and the natural boarding UX.
- **No payment screen.** The prototype flows request → accepted directly; payment (Razorpay) is Phase 10.
- **Flat ₹150 service fee** to match the prototype's shown numbers (₹900 × 3 = ₹2,700, fee ₹150, total ₹2,850) — not the 10% used by Services.
- **Real ISO dates stored** (`checkIn`/`checkOut` as `yyyy-MM-dd`), not display-only labels — the host will need the actual dates.

## Scope

**In scope**
- `homestayBookings/{id}` Firestore collection; `HomestayBooking` model; `HomestayBookingRepository` interface + Firestore impl + in-memory fake; provider.
- **HomestayRequestScreen** — date range / pet / note + price breakdown; "Send request" writes the booking.
- **HostAcceptedScreen** — honest "Request sent" celebration + summary.
- Rewire the Host-profile "Request to book" button to `/host-request`.
- `firestore.rules` for `homestayBookings` (create-only) + deploy; routes.
- Reuse the existing `myPetsProvider` (from Slice 4b) for the pet selector.
- TDD with in-memory fakes; emulator integration test extended for `homestayBookings`.

**Out of scope (later)**
- Real payment charge / Razorpay (Phase 10) — no money moves; the request is created with `status: 'requested'`.
- Host-side accept/decline UI + the `update` transition to `accepted`, host inbox, notifications (a later slice / Phase 7). Rules stay create-only this slice.
- A "My homestay bookings" list UI (the docs are written; surfacing them is later). `watchMyHomestayBookings` is added on the repo for that future use.
- Chat, reviews, real calendar/availability/conflict checks (any date range is allowed this slice).

## Firestore data model

```
homestayBookings/{bookingId}   // auto id
  guestId      : string        // == auth.uid (the pet parent)
  hostId       : string        // the host's uid
  homeName     : string        // denormalised for display
  hostName     : string        // denormalised
  petId        : string
  petName      : string
  ratePerNight : int
  checkIn      : string        // ISO "yyyy-MM-dd"
  checkOut     : string        // ISO "yyyy-MM-dd"
  nights       : int
  subtotal     : int           // ratePerNight * nights
  fee          : int           // flat 150 (HomestayBooking.serviceFee)
  total        : int           // subtotal + fee
  note         : string        // note to host (may be empty)
  status       : string        // "requested"
  createdAt    : timestamp
```

## Models (`lib/data/models/homestay_booking.dart`)

```
class HomestayBooking {
  final String id, guestId, hostId, homeName, hostName, petId, petName, note, status;
  final DateTime checkIn, checkOut;              // date-only (time component ignored)
  final int ratePerNight, nights, subtotal, fee, total;
  const HomestayBooking({ ..., this.id = '', this.note = '', this.status = 'requested' });

  static const int serviceFee = 150;
  static int nightsBetween(DateTime checkIn, DateTime checkOut) =>
      checkOut.difference(checkIn).inDays;
  static String fmtDay(DateTime d);              // "Fri, 12 Jul" — const weekday/month arrays, no intl

  Map<String,dynamic> toMap();                   // omits id/createdAt; checkIn/checkOut -> ISO yyyy-MM-dd
  factory HomestayBooking.fromMap(String id, Map<String,dynamic>);
}
```
The draft passed between screens has `id == ''`; the repository assigns the doc id on create. The caller computes `nights`/`subtotal`/`total` (using `nightsBetween` and `serviceFee`) and constructs the draft — mirroring how Slice 4b's `Booking` was built.

## Repository seam (same pattern as BookingRepository)

`lib/data/repositories/homestay_booking_repository.dart`:
```dart
abstract interface class HomestayBookingRepository {
  Future<void> createHomestayBooking(HomestayBooking booking);
  Stream<List<HomestayBooking>> watchMyHomestayBookings(String guestId);
}
```
- `FirestoreHomestayBookingRepository` under `repositories/firebase/` (`homestayBookings` collection, `add` with `createdAt` server timestamp; `watchMyHomestayBookings` = `where('guestId', ==, uid)`).
- `InMemoryHomestayBookingRepository` fake in `test/support/fakes.dart`.
- Provider (`providers.dart`): `homestayBookingRepositoryProvider`. Reuse the existing `myPetsProvider` for the pet selector.

## Screens (`features/homestay/`)

1. **HomestayRequestScreen** (`ConsumerStatefulWidget`, `Homestay` via `extra`) — `PgAppBar('Request booking')`; a host summary card (homeName, "{area} · ★ rating-or-New"); a **Dates** row → `showDateRangePicker` (default: check-in = tomorrow, check-out = +3 days → **3 nights**; `firstDate` = today), displaying "{fmtDay(checkIn)} → {fmtDay(checkOut)} · {nights} nights"; a **pet selector** over `myPetsProvider` (default the first pet; if the list is empty, show "Add a pet to book" and disable "Send request"); an optional **note-to-host** `PgTextField`; a **price-breakdown** card (`₹{rate} × {nights} nights` = `₹{subtotal}`, `Service fee ₹{fee}`, `Total ₹{total}`). Sticky **"Send request to {hostFirstName}"** → `createHomestayBooking(HomestayBooking(guestId, hostId, homeName, hostName, petId, petName, ratePerNight, checkIn, checkOut, nights, subtotal, fee, total, note, status:'requested'))` → `context.go(Routes.hostAccepted, extra: booking)`. Loading state on the button.
2. **HostAcceptedScreen** (`StatelessWidget`, `HomestayBooking` via `extra`) — a celebration (🏡, `pg-pop`-style) reading **"Request sent! 🎉"**; a line "{hostName} will confirm {petName}'s stay for {fmtDay(checkIn)} – {fmtDay(checkOut)} soon."; a summary card ({hostName}, "{nights} nights · ₹{total}"); a **"Message {hostFirstName}"** button → `showComingSoon(context, 'Chat')`; a **"Back to home"** button → `context.go(Routes.home)`.

## Wiring, routes, rules

- **Rewire "Request to book"**: in `host_profile_screen.dart` the bottom "Request to book" button changes from `showComingSoon(context,'Booking')` to `context.push(Routes.hostRequest, extra: homestay)`.
- Add `Routes.hostRequest = '/host-request'` and `Routes.hostAccepted = '/host-accepted'` as top-level **protected** routes; `/host-request` reads a `Homestay` from `extra`, `/host-accepted` reads a `HomestayBooking` from `extra`.
- `firestore.rules` (deploy via CLI) — **create-only** (host-accept `update` is a later slice):
```
match /homestayBookings/{id} {
  allow read: if request.auth != null
              && (resource.data.guestId == request.auth.uid
                  || resource.data.hostId == request.auth.uid);
  allow create: if request.auth != null
              && request.resource.data.guestId == request.auth.uid;
  allow update, delete: if false;
}
```

## Testing

TDD with in-memory fakes via `pumpPgApp`/`pumpPg` overrides:
- `HomestayBooking` serialization round-trip (incl. `checkIn`/`checkOut` ISO strings) + `nightsBetween` + `fmtDay` + `serviceFee`.
- `InMemoryHomestayBookingRepository` (create; `watchMyHomestayBookings` emits).
- `HomestayRequestScreen`: renders the default range/pet/total; empty-pets state disables "Send request"; "Send request" calls `createHomestayBooking` with a `requested` booking carrying the right fields, and navigates to HostAccepted (assert HostAccepted renders). (The `showDateRangePicker` dialog interaction itself is not unit-tested — tests assert the **default** computed range/total, the same way Slice 4b tested default date/time selections.)
- `HostAcceptedScreen`: renders the "Request sent" summary; "Message" → coming-soon; "Back to home".
- `HostProfileScreen`: "Request to book" navigates to the Request screen (router harness).
- Extend `integration_test/firebase_repos_test.dart`: `createHomestayBooking` then `watchMyHomestayBookings` round-trip against the Firestore emulator with the new rules.

## Prerequisites

None new — Firestore + Email/Password are live. New rules deploy via the CLI (authenticated).

## Deliverable / definition of done

From a Host profile, a signed-in pet parent picks a date range/pet/note, taps "Send request", and a real `homestayBookings/{id}` doc is written with `status: 'requested'` (owner-scoped by rules); the honest "Request sent!" screen shows the summary. `flutter analyze` clean, `flutter test` green (fakes), emulator integration test passes with the new rules, debug APK builds.
