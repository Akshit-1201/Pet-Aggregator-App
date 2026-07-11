# Pawgo Slice 4b: Services — Booking & Payment — Design

> **Status:** approved design (2026-07-12). Second of two sub-slices of the Services pillar (Phase 4); builds on Slice 4a (supply & browse). Built on the live Firebase backend — **no mock data**. Payment gateway (Razorpay) is deferred to Phase 10, so "Pay" writes a real booking but does not charge.

## Goal

Let a pet parent book a service pro end to end: from a pro's profile → pick a date, time, and which of their pets it's for → a faithful (UI-only) payment step → a **real `bookings` doc** in Firestore → a confirmation screen. Wires the "Book" buttons that Slice 4a left as coming-soon.

Screens match `design/Pawgo Prototype.dc.html` (Booking 630–662, Payment 664–686, Booking confirmed 688–701).

## Scope

**In scope**
- `bookings/{id}` Firestore collection; `Booking` model; `BookingRepository` interface + Firestore impl + in-memory fake; providers.
- **BookingScreen** — pick date / time / pet + price breakdown.
- **PaymentScreen** — faithful card/UPI/wallet UI (visual), "Pay" writes the booking.
- **BookingConfirmedScreen** — celebration + summary.
- Rewire the "Book" buttons (Pro profile + Services-list card) to `/booking`.
- `firestore.rules` for `bookings` + deploy; routes.
- A `myPetsProvider` (the signed-in user's own pets) for the pet selector.
- TDD with in-memory fakes; emulator integration test extended for `bookings`.

**Out of scope (later)**
- Real payment charge / Razorpay (Phase 10) — payment screen is visual; the booking is created with `status: 'confirmed'` and no money moves.
- A "My bookings" / pro-side bookings list UI (the docs are written; surfacing them is a later slice). `watchMyBookings` is added on the repo for that future use.
- Reviews, chat, real calendar/scheduling/reminders (date is a display label this slice).

## Firestore data model

```
bookings/{bookingId}        // auto id
  parentId    : string      // == auth.uid (the pet parent)
  proId       : string      // the pro's uid
  proName     : string      // denormalised for display
  petId       : string
  petName     : string
  serviceType : string      // "walker" | "sitter" | "groomer" | "trainer"
  rate        : int         // ₹ per unit
  fee         : int         // Pawgo fee = round(rate * 0.1)
  total       : int         // rate + fee
  dateLabel   : string      // e.g. "Tue 15 Jul"
  timeSlot    : string      // e.g. "5:00 PM"
  status      : string      // "confirmed"
  createdAt   : timestamp
```

## Models (`lib/data/models/booking.dart`)

```
class Booking {
  final String id, parentId, proId, proName, petId, petName;
  final ServiceType serviceType;   // reuse from pro.dart
  final int rate, fee, total;
  final String dateLabel, timeSlot, status;
  const Booking({ ..., this.id = '', this.status = 'confirmed' });
  Map<String,dynamic> toMap();      // omits id/createdAt; serviceType -> storageKey
  factory Booking.fromMap(String id, Map<String,dynamic>);
  static int feeFor(int rate) => (rate * 0.1).round();
}
```
The draft passed between screens is a `Booking` with `id == ''`; the repository assigns the doc id on create.

## Repository seam (same pattern)

`lib/data/repositories/booking_repository.dart`:
```dart
abstract interface class BookingRepository {
  Future<void> createBooking(Booking booking);
  Stream<List<Booking>> watchMyBookings(String parentId);
}
```
- `FirestoreBookingRepository` under `repositories/firebase/` (`bookings` collection, `add` with `createdAt` server timestamp; `watchMyBookings` = `where('parentId', ==, uid)`).
- `InMemoryBookingRepository` fake in `test/support/fakes.dart`.
- Providers (`providers.dart`): `bookingRepositoryProvider`; `myPetsProvider` → `StreamProvider<List<PetProfile>>` (`petRepository.watchMyPets(currentUid)`).

## Screens (`features/services/`)

1. **BookingScreen** (`ConsumerStatefulWidget`, `Pro` via `extra`) — `PgAppBar('Book a ${pro.serviceType.label}')`; **date** = 4 tiles for today..+3 days (weekday + day-of-month, computed from `DateTime.now()`, no `intl`; first selected by default); **time** = 3 slots ("8:00 AM", "5:00 PM", "6:30 PM"; first selected); **"For"** = a selector over `myPetsProvider` (default the first pet; if the list is empty, show "Add a pet to book" and disable Continue); a price-breakdown card (service `₹rate`, Pawgo fee `₹fee`, Total `₹total`). Sticky "Continue to payment" → `context.push(Routes.payment, extra: draftBooking)` where the draft is a `Booking(parentId, proId, proName, petId, petName, serviceType, rate, fee, total, dateLabel, timeSlot)`.
2. **PaymentScreen** (`ConsumerStatefulWidget`, `Booking` draft via `extra`) — `PgAppBar('Payment')`; a stylised saved-card block + UPI / Pawgo Wallet option rows (visual only, no real selection logic required); a bottom bar with Total + "Pay ₹{total}" → `bookingRepository.createBooking(draft)` → `context.go(Routes.bookingConfirmed, extra: draft)`. Loading state on the button.
3. **BookingConfirmedScreen** (`StatelessWidget`, `Booking` via `extra`) — a checkmark celebration ("Booking confirmed! 🎉"), a summary line ("{proName} will {service} {petName} on {dateLabel}, {timeSlot}"), a summary card (pro, service · ₹total paid), "Message {proFirstName}" → `showComingSoon(context,'Chat')`, and "Back to home" → `context.go(Routes.home)`.

## Wiring, routes, rules

- **Rewire "Book"**: in `pro_profile_screen.dart` the "Book · ₹{rate}" button and in `services_list_screen.dart` the card "Book" chip change from `showComingSoon(context,'Booking')` to `context.push(Routes.booking, extra: pro)`.
- Add `Routes.booking = '/booking'`, `Routes.payment = '/payment'`, `Routes.bookingConfirmed = '/booking-confirmed'` as top-level **protected** routes; `/booking` reads a `Pro` from `extra`, `/payment` and `/booking-confirmed` read a `Booking` from `extra`.
- `firestore.rules`:
```
match /bookings/{id} {
  allow read: if request.auth != null
              && (resource.data.parentId == request.auth.uid || resource.data.proId == request.auth.uid);
  allow create: if request.auth != null
              && request.resource.data.parentId == request.auth.uid;
  allow update, delete: if false;
}
```
Deploy with `firebase deploy --only firestore:rules`.

## Testing

TDD with in-memory fakes via `pumpPgApp` overrides:
- `Booking` serialization round-trip + `feeFor`.
- `InMemoryBookingRepository` (create; watchMyBookings emits).
- `myPetsProvider` streams the signed-in user's pets.
- `BookingScreen`: renders date/time/pet + total; empty-pets state disables Continue; Continue passes a draft to Payment (assert Payment renders).
- `PaymentScreen`: "Pay" calls `createBooking` (assert the fake received it) and navigates to Confirmed.
- `BookingConfirmedScreen`: renders the summary; "Message" → coming-soon; "Back to home".
- `ProProfileScreen`/`ServicesListScreen`: "Book" navigates to the Booking screen (router harness).
- Extend `integration_test/firebase_repos_test.dart`: `createBooking` then `watchMyBookings` round-trip against the Firestore emulator with the new rules.

## Prerequisites

None new — Firestore + Email/Password are live. New rules deploy via the CLI.

## Deliverable / definition of done

From a pro's profile, a signed-in pet parent picks date/time/pet, "pays" (UI-only), and a real `bookings/{id}` doc is written (owner-scoped by rules); the confirmation screen shows the summary. `flutter analyze` clean, `flutter test` green (fakes), emulator integration test passes with the new rules, debug APK builds.
