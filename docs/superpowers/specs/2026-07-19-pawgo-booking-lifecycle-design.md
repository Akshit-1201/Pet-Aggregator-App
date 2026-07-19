# Pawgo Slice 10: Booking Lifecycle — Design

> **Status:** approved design (2026-07-19). Makes bookings a two-sided, honest lifecycle: hosts accept/decline homestay requests, guests can cancel, completion is derived from dates, and Rate is gated on it. Built on the live backend — **no mock data**. Payments (Razorpay) remain deferred; this slice gives them a real lifecycle to attach to later.

## Goal

Close the booking loop that Slices 4b/5b left open. Today a homestay request stays `requested` forever, a service booking is born `confirmed` and never ends, the supply side has no view of its own bookings, and any booking can be rated at any time. After this slice: hosts see incoming requests and **Accept/Decline** them, pros see their bookings, guests/parents can **cancel** upcoming bookings, every booking surfaces an honest **status**, and **Rate unlocks only after the booking actually completed**.

## Design decisions (settled during brainstorming)

- **Full loop, both pillars, + guest cancellation.** Homestay gets the decision loop (accept/decline); services get a pro-side ledger (service bookings stay auto-`confirmed` — no accept step); both get guest/parent cancellation and derived completion.
- **Thin writes + derived status.** Only real human decisions are written to Firestore: host → `accepted`/`declined`, guest/parent → `cancelled`. Each transition updates exactly `['status', 'updatedAt']`. **`completed` is never stored** — a pure function derives it once the booking's date passes. A booking nobody reopens still completes; nothing can be gamed by forgetting a button.
- **`updatedAt` on every transition** (server timestamp, same stale-`serverTimestamp` → 0 handling as `createdAt`). It exists so the notifications feed can order and unread-mark "accepted/declined/cancelled" events — there is no other timestamp for a decision.
- **New service bookings store a real ISO `date`** (`yyyy-MM-dd`). The booking screen already holds the `DateTime`; today it only saves a display label. **Legacy service bookings (no `date` field) are grandfathered as rateable** so existing data keeps working.
- **The Bookings screen becomes a two-tab hub** — "My bookings" (demand side, existing) and "Received" (supply side, only rendered when the user has a pro or homestay listing). No new route.
- **Rules enforce actor + fields + transition** (who may write which arrow, `hasOnly(['status','updatedAt'])`). Date-based guards ("only cancel before check-in") are client-side UX, consistent with the codebase's current rules posture (tracked in the existing rules-hardening follow-up).
- **Deferred:** payments/refunds on cancel (no money moves yet); FCM push for lifecycle events (in-app derived feed only); a stored audit/history trail; an explicit "in progress" mid-stay phase; host-initiated cancellation of an accepted stay.

## Scope

**In scope**
- `lib/data/models/booking_lifecycle.dart` — pure phase/permission module (no SDK imports, `now` injected).
- Model tweaks: `Booking.date` (ISO, default `''`) + `Booking.updatedAt`; `HomestayBooking.updatedAt`.
- Repository additions (interface + Firestore impl + test fakes): pro/host "received" streams and explicit transition methods.
- `firestore.rules`: unlock `update` on `bookings` and `homestayBookings` along the valid arrows only; deploy via CLI; emulator integration test for the matrix.
- Bookings hub UI: tabs, status chips, gated Rate, Cancel with confirm dialog, host Accept/Decline, empty states.
- Notifications: three new derived item types (request received / request decided / booking cancelled).

**Out of scope (later)**
- Razorpay & refunds (Phase 10 of the product plan) — cancel moves no money because none was taken.
- FCM push (its own later phase); the feed stays in-app and derived.
- Host cancelling an accepted stay, rescheduling/date changes, calendar/availability blocking.
- Server-enforced date guards + server-owned writes (Cloud Functions — deferred project-wide).

## Lifecycle model

### Stored statuses (the only writes)

- `homestayBookings.status`: `requested` → `accepted` | `declined` (host only) · `requested`/`accepted` → `cancelled` (guest only).
- `bookings.status`: `confirmed` → `cancelled` (parent only). Pros never write service bookings.
- Every transition writes exactly `status` + `updatedAt` (server timestamp). `createdAt` and all other fields are immutable.

### Derived phases (`lib/data/models/booking_lifecycle.dart`)

```dart
enum BookingPhase { pending, upcoming, completed, declined, cancelled, expired }

BookingPhase servicePhase(Booking b, DateTime now);
BookingPhase stayPhase(HomestayBooking b, DateTime now);
bool canRate(BookingPhase p);            // p == completed
bool canCancelService(Booking b, DateTime now);
bool canCancelStay(HomestayBooking b, DateTime now);
bool canDecide(HomestayBooking b, DateTime now);  // host may accept/decline
```

All comparisons are **date-only** (calendar days, device-local):

| Pillar | Stored status | Date condition | Phase |
|---|---|---|---|
| Service | `cancelled` | — | `cancelled` |
| Service | `confirmed` | no `date` (legacy) | `completed` (grandfathered) |
| Service | `confirmed` | `date` ≥ today | `upcoming` |
| Service | `confirmed` | `date` < today | `completed` |
| Homestay | `declined` / `cancelled` | — | `declined` / `cancelled` |
| Homestay | `requested` | `checkIn` ≥ today | `pending` |
| Homestay | `requested` | `checkIn` < today | `expired` (no write — shown honestly, not actionable) |
| Homestay | `accepted` | `checkOut` ≥ today | `upcoming` |
| Homestay | `accepted` | `checkOut` < today | `completed` |

Permissions: `canCancelService` = `confirmed` && today < `date` (legacy no-date bookings are not cancellable — they're already completed). `canCancelStay` = (`requested` && not expired) or (`accepted` && today < `checkIn`) — never mid-stay. `canDecide` = `requested` && not expired. No function reads `DateTime.now()` internally; callers pass `now` (screens use a small provider-free helper, tests inject fixed dates).

## Repositories

```dart
// BookingRepository +=
Stream<List<Booking>> watchBookingsForPro(String proId);
Future<void> cancelBooking(String id);

// HomestayBookingRepository +=
Stream<List<HomestayBooking>> watchBookingsForHost(String hostId);
Future<void> acceptRequest(String id);
Future<void> declineRequest(String id);
Future<void> cancelStay(String id);
```

Firestore impls: `where('proId'/'hostId', isEqualTo: uid)` ordered by `createdAt` desc; transitions are `doc.update({'status': …, 'updatedAt': FieldValue.serverTimestamp()})`. Providers: `receivedServiceBookingsProvider` / `receivedStayBookingsProvider` — empty stream when the user has no listing (guarded by `currentProProvider` / `currentHomestayProvider`), so the feed and hub can watch them unconditionally. In-memory fakes mirror the new API for widget tests.

## Firestore rules

`update: false` becomes, on both collections (delete stays `false`, create unchanged):

```
// homestayBookings/{id}
allow update: if request.auth != null
  && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt'])
  && (
    (resource.data.hostId == request.auth.uid
      && resource.data.status == 'requested'
      && request.resource.data.status in ['accepted', 'declined'])
    ||
    (resource.data.guestId == request.auth.uid
      && resource.data.status in ['requested', 'accepted']
      && request.resource.data.status == 'cancelled')
  );

// bookings/{id}
allow update: if request.auth != null
  && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt'])
  && resource.data.parentId == request.auth.uid
  && resource.data.status == 'confirmed'
  && request.resource.data.status == 'cancelled';
```

Deployed via the Firebase CLI. An emulator integration test (same harness as the existing `createdAt` round-trip test) covers the matrix: host can accept and decline a `requested` stay; host cannot cancel or re-decide a decided one; guest can cancel `requested` and `accepted` but not `declined`; guest cannot accept; parent can cancel a `confirmed` service booking; nobody can touch any other field.

## Bookings hub (`/bookings`, evolves `MyBookingsScreen`)

- **Tabs:** "My bookings" / "Received". The tab bar renders only when `currentProProvider` or `currentHomestayProvider` has a listing; otherwise the screen is the single demand-side list exactly as today. The screen accepts an optional initial-tab value via `go_router` `extra` so notifications can land on Received.
- **Status chips** on every row, colored by phase: `pending` muted, `upcoming` brand orange, `completed` green, `declined`/`cancelled` red/grey, `expired` grey. Rows keep the existing card design (`PgImageSlot` + name + detail line).
- **My bookings tab:** Rate button only when `canRate(phase)` && not already rated (the `myReviewedBookingIdsProvider` set, as today); otherwise the chip sits in its place. Cancellable rows get a "Cancel" text action behind a confirm dialog ("Cancel this booking? This can't be undone."). Homestay detail line gains the check-in date.
- **Received tab:** sections for whichever listings exist. Homestay requests in `pending` show pet name, dates, nights, ₹ total, and the guest's note, with **Accept** / **Decline** buttons (Decline behind the same confirm dialog). Everything else (accepted, completed, cancelled stays; all service bookings) renders read-only with its chip — the supply side is a ledger, not an action list. Empty state: "No bookings for your listing yet."
- Async handlers guard `mounted` after `await`; failures surface as a SnackBar. Optimistic UI is unnecessary — the streams re-emit on the write.

## Notifications (extends the pure `buildNotifications`)

Three new derived types, fed by the two "received" streams plus the existing demand-side streams (signature grows accordingly):

- Host: 🏡 "New booking request from {petName}'s parent" — `requested` stays addressed to me, timestamp `createdAt`.
- Guest: ✅/❌ "{homeName} accepted/declined your request" — my stays with status `accepted`/`declined`, timestamp `updatedAt`.
- Host/pro: ↩️ "{petName}'s stay/booking was cancelled" — received bookings with status `cancelled`, timestamp `updatedAt`.

Each deep-links to `/bookings` (Received tab for supply-side items). Unread follows the existing `notifsSeenAt` mechanism; `updatedAt == 0` (stale server timestamp) falls back to `createdAt` so an item never sorts to 1970.

## Review gating

`canRate` = phase `completed` && not yet rated. Pending/upcoming/declined/cancelled/expired bookings can never be rated. Legacy service bookings (no `date`) remain rateable — existing reviews and the "★ Rated" state keep working unchanged. `RateReviewScreen` itself is untouched; only the entry point is gated.

## Error handling

- Transition write fails (offline, rules denial, e.g. the other side changed status first) → SnackBar "Couldn't update the booking — try again."; the stream re-emits the true state either way.
- Malformed/missing dates parse to the epoch fallback already in `fromMap` → phase degrades to `completed`/`expired` rather than crashing.
- Both received streams are empty (listing deleted mid-session) → the tab simply shows its empty state.

## Testing

TDD throughout; fakes via `pumpPgApp`, dates always injected:

- **booking_lifecycle:** every row of the phase table (boundary days: today, yesterday, tomorrow); every `can*` permission incl. mid-stay no-cancel, expired no-decide, legacy no-cancel-but-rateable.
- **Repositories (fakes + emulator):** received streams filter by `proId`/`hostId`; transitions write only `status`+`updatedAt`; the emulator rules-matrix test above.
- **Bookings hub:** tab bar hidden for plain parents, shown for pros/hosts; chips per phase; Rate hidden until completed, shown once completed & unrated; Cancel/Decline confirm dialogs (confirm ✓ writes, dismiss ✗ doesn't); Accept writes `accepted`; Received sections + empty states.
- **Notifications:** builder emits the three new types with the right timestamps, unread flags, and `/bookings` deep-link.
- `flutter analyze` clean; all existing tests stay green (model additions are backward-compatible defaults).

## Deliverable / definition of done

A host opens Bookings → Received, sees a pending request with the pet's details, taps Accept — the guest's My-bookings row flips to "Upcoming" and their notification feed shows "accepted". After checkout the row shows "Completed" and Rate appears; before check-in the guest can cancel (with confirmation) and the host is notified. Service bookings show Upcoming until their date passes, then unlock Rate; parents can cancel upcoming ones; pros see their ledger. Rules block every invalid transition (verified on the emulator). `flutter analyze` clean, `flutter test` green, debug APK builds.
