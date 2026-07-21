# Pawgo Slice 15: Server-owned payments — Design

> **Status:** approved design (2026-07-22). Closes the **hard deploy gate / pre-live-keys blocker** raised by Slice 14's final review. Makes the two payment Cloud Functions the sole authority on *what a booking costs* and *whether it is paid*, for **both** pillars (Services + Homestay). Until this ships, `refundBookingPayment` must not be deployed and live Razorpay keys must not be enabled.

## The problem this fixes

Nothing today binds a Razorpay payment to the booking it supposedly paid for:

- `verifyBookingPayment` checks the HMAC — proving the payment is genuine — and then **returns `true` and writes nothing**. The *client* writes `status` and `paymentId` onto the booking.
- Rules only check *"is this the owner?"*, never *"is that payment real, for this booking, for the right amount?"*. A `paymentId` on a booking is, to the server, a string the client typed.
- Prices are client-written too: a client picks `rate`/`subtotal`/`total` at create time.

Money only ever flowed *in*, so this was self-harm at worst. **Slice 14 added refunds, which reverse the direction** — the server now sends money out against that unverified `paymentId`.

**The exploit (reviewer-traced):** pay for stay A legitimately (obtaining a real captured `pay_…`) → create stay B (nothing forbids `hostId == guestId`) with `subtotal` = A's total and `paymentId` = A's id → cancel B ≥24h out → **the server refunds A's money while A stays `paid`**: a free stay, repeatable up to each payment's captured amount. A host can also read a guest's `paymentId` and reverse their payment.

## Design decisions (settled during brainstorming)

- **Both pillars in one slice.** They share the same two Functions and the same client seam; splitting would change both twice. Services' hole (mint a `confirmed` booking without paying — a pro shows up for an unpaid job) also blocks live keys.
- **One unified contract: you always pay for a booking that already exists.** Services therefore **pre-creates a `pending` (unpaid) booking** before checkout, exactly mirroring Homestay's `accepted` → pay. One server code path instead of two, and it reuses the `awaitingPayment` → `expired` lifecycle Slice 13 already built.
- **Price authority moves to the listing, not the booking.** The server recomputes the amount from `pros/{proId}.rate` (+10% fee) or `homestays/{hostId}.ratePerNight` × nights (+₹150). A client-written `total` is never trusted for charging.
- **The order carries the binding.** `createBookingOrder` stamps Razorpay `notes: {bookingId, kind, uid}`; `verifyBookingPayment` fetches the order and asserts those match before writing. This is what makes "pay for A, attach to B" impossible.
- **`verifyBookingPayment` becomes the only writer of paid state**, with admin, transactionally. The client's ability to say "paid" is removed from rules.
- **This deletes client code, not just adds server code.** With the server writing inside verification, both payment screens lose their post-payment write, the `_paid` cache, the `saving` phase and the "Retry saving" state — the "payment received but saving the booking failed" class stops existing.
- **Deferred:** Razorpay webhooks; refund idempotency keys; per-host pricing overrides; migrating legacy records (they keep working untouched).

## Scope

**In scope**
- `functions/src/index.ts`: `createBookingOrder` and `verifyBookingPayment` rewritten to the unified `{kind, bookingId}` contract (ownership, payable state, server-recomputed price, order `notes` binding, transactional paid-write).
- `firestore.rules`: `bookings` create constrained to `status: 'pending'`; the client `pending → confirmed` and homestay `accepted → paid` arms removed.
- `booking_lifecycle.dart`: service `pending` → `awaitingPayment`/`expired`; new `canPayService(b, now)`.
- `PaymentService` seam: `payForBooking({bookingId, kind, description, onVerifying})` (no `amountRupees`); new `enum PaymentKind { service, homestay }`.
- `BookingScreen` (services): creates the `pending` booking before navigating to payment.
- `PaymentScreen` + `HomestayPaymentScreen`: simplified — pay, then navigate; no post-payment write, no retry-save.
- `BookingRepository.createBooking` writes `status: 'pending'`; `HomestayBookingRepository.markPaid` **removed** (dead once rules reject it).
- Tests incl. an explicit **exploit test** (a payment made for booking A cannot confirm booking B).

**Out of scope**
- No change to the refund Function, the cancellation policy, the request/accept flow, or any UI outside the two payment entry points.
- No data migration: existing `confirmed` service bookings and `paid` stays are untouched and keep working.
- Webhooks, refund idempotency keys, live keys/KYC.

## Unified payment contract

```
Services:  Book → [client writes 'pending' booking] → Pay → server writes 'confirmed'
Homestay:  Request → host accepts → Pay → server writes 'paid'
                                    ↑ same two Functions, same seam
```

### `createBookingOrder({ kind, bookingId })`

`kind` ∈ `'service' | 'homestay'`. No client amount is accepted.

1. Unauthenticated → `unauthenticated`. Bad/missing `kind`/`bookingId` → `invalid-argument`.
2. Read `bookings/{bookingId}` (service) or `homestayBookings/{bookingId}` (homestay) with admin. Missing → `not-found`.
3. Ownership: service `parentId == uid`, homestay `guestId == uid`, else `permission-denied`.
4. Payable state: service `status == 'pending'`, homestay `status == 'accepted'`, else `failed-precondition('not-payable')`.
5. **Recompute the authoritative total from the listing:**
   - Service: read `pros/{proId}`; `rate = pro.rate`; `fee = round(rate * 0.1)`; `total = rate + fee`.
   - Homestay: read `homestays/{hostId}`; `nights` from the booking's `checkIn`/`checkOut` (date-only, IST — the existing contract); `subtotal = ratePerNight * nights`; `fee = 150`; `total = subtotal + fee`.
   - Missing listing → `failed-precondition('no-listing')`. Non-positive total → `failed-precondition('bad-amount')`.
6. If the booking's stored `total` ≠ the recomputed total → `failed-precondition('amount-mismatch')`. (Protects the user from being charged a number the screen never showed, and surfaces tampering.)
7. Create the Razorpay order for the recomputed amount with **`notes: {bookingId, kind, uid}`** and `receipt` as today.
8. Return `{orderId, amountPaise, keyId}`.

### `verifyBookingPayment({ kind, bookingId, orderId, paymentId, signature })`

The **only** writer of paid state.

1. Auth + argument validation as above.
2. HMAC check `orderId|paymentId` (unchanged) → mismatch `permission-denied('signature-mismatch')`.
3. **Order binding:** `rzp.orders.fetch(orderId)`; assert `notes.bookingId === bookingId`, `notes.kind === kind`, `notes.uid === uid`, else `permission-denied('order-booking-mismatch')`. A fetch failure → `internal('order-fetch-failed')`.
4. Re-read the booking and re-assert ownership + payable state (it may have changed since the order).
5. **Transactionally** write, asserting the payable state inside the transaction (so a double-submit is a no-op):
   - Service: `{status: 'confirmed', paymentId, updatedAt}` (+ the server's `rate`/`fee`/`total` so stored amounts become server-authoritative).
   - Homestay: `{status: 'paid', paymentId, updatedAt}` (+ server `subtotal`/`fee`/`total`).
6. Return `{confirmed: true, paymentId}`.

## Firestore rules

```
match /bookings/{id} {
  // create: unpaid only — the server owns 'confirmed'
  allow create: if request.auth != null
              && request.resource.data.parentId == request.auth.uid
              && request.resource.data.status == 'pending';
  // update: the client may only cancel (pending or confirmed); paid state is server-written
  allow update: if request.auth != null
              && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt'])
              && resource.data.parentId == request.auth.uid
              && resource.data.status in ['pending', 'confirmed']
              && request.resource.data.status == 'cancelled';
  allow delete: if false;   // read unchanged
}

match /homestayBookings/{id} {
  // the guest accepted->paid arm is REMOVED; only host accept/decline + guest cancel remain
  allow update: if request.auth != null
              && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt'])
              && (
                (resource.data.hostId == request.auth.uid
                  && resource.data.status == 'requested'
                  && request.resource.data.status in ['accepted', 'declined'])
                || (resource.data.guestId == request.auth.uid
                  && resource.data.status in ['requested', 'accepted']
                  && request.resource.data.status == 'cancelled')
              );
  // create + delete + read unchanged
}
```

Admin writes (both Functions and the refund Function) bypass rules, so nothing else is needed.

## Lifecycle (`booking_lifecycle.dart`)

Services gains what Homestay already has:

```dart
BookingPhase servicePhase(Booking b, DateTime now) {
  if (b.status == 'cancelled') return BookingPhase.cancelled;
  final d = DateTime.tryParse(b.date);
  if (d == null) return BookingPhase.completed;              // legacy, grandfathered
  if (b.status == 'pending') {                                // unpaid
    return _day(d).isBefore(_day(now)) ? BookingPhase.expired : BookingPhase.awaitingPayment;
  }
  return _day(d).isBefore(_day(now)) ? BookingPhase.completed : BookingPhase.upcoming;
}

bool canPayService(Booking b, DateTime now) {
  final d = DateTime.tryParse(b.date);
  return b.status == 'pending' && d != null && !_day(d).isBefore(_day(now));
}
```

`canCancelService` extends to `status in ['pending','confirmed']` before the date. `canRate` stays `completed`-only — so an unpaid service booking is never rateable, mirroring homestay. Homestay phases/permissions unchanged.

## Client changes

**Seam** (`payment_service.dart`):
```dart
enum PaymentKind { service, homestay }

Future<PaymentResult> payForBooking({
  required String bookingId,
  required PaymentKind kind,
  required String description,
  void Function()? onVerifying,
});
```
`RazorpayPaymentService` passes `{kind: kind.name, bookingId}` to both callables. `RefundResult`/`refundStay` and the error taxonomy (`cancelled`/`failed`/`unverified`) are unchanged — `unverified` now means "charged, but the server didn't confirm the booking", which is exactly the case worth escalating.

**Screens — simplified, not just rewired.** Both payment screens drop the post-payment write, the `_paid` cache, the `saving`/`retrySave` phases and the "Retry saving" copy. The phase machine becomes `idle → opening → verifying`, then navigate. `BookingScreen` (services) writes the `pending` booking on "Continue to payment" and navigates with its id; a create failure shows `Couldn't start this booking — try again.` and does not navigate.

**Repositories:** `BookingRepository.createBooking` writes `status: 'pending'`. `HomestayBookingRepository.markPaid` is **removed** (interface, Firestore impl, fake) — the server owns that write now.

## Test migration (consequences of removing the client paid-write)

Removing `markPaid` and the client `accepted → paid` rules arm invalidates existing tests that exercised them. These are **expected, planned changes** — several become *stronger* assertions of the new guarantee:

| File | Today | After |
|---|---|---|
| `integration_test/firebase_repos_test.dart` (Slice-13 homestay matrix) | Guest **can** write `accepted → paid` via `markPaid`; host can't; extra fields denied | The guest write is now **denied** — flip that row to assert `accepted → paid` is rejected for the client. This becomes the direct proof of the fix. Host accept/decline + guest cancel rows are unchanged. |
| `integration_test/functions_test.dart` (Slice-14 refund test) | Seeds a `paid` stay via `markPaid` to reach `permission-denied` | Drop the seeding: `permission-denied` is asserted before the status check, so it can be pinned on the existing `requested` booking. `not-paid` already uses a requested booking. No paid seed needed. |
| `test/data/homestay_pay_test.dart` | Tests `markPaid` writes status/updatedAt/paymentId | Delete that test; keep the `paymentId`/`refundAmount` round-trip tests. |
| `test/features/homestay_payment_test.dart` | `_FailOnceHomestayRepo` overrides `markPaid` for the retry-save test | Delete the retry-save test and the helper — that failure class no longer exists. Keep success/cancelled/failed/unverified. |
| `test/support/fakes.dart` | `InMemoryHomestayBookingRepository.markPaid` | Remove. |

The services side has an analogous shift: tests that asserted a client-created `confirmed` booking now assert `pending`, and the paid state arrives only via the Function.

## Error handling

- Order creation rejected (not owner / not payable / amount mismatch / no listing) → the existing `PaymentException(failed)` path; nothing charged, booking untouched.
- Payment succeeds but verification fails (signature, order-binding, or the transactional write) → existing `unverified` path: the user is told they were charged and given the payment id; the booking stays unpaid. This is the honest, pre-existing behaviour and is now the *only* post-charge failure mode.
- Double-submit of verify → the in-transaction state assertion makes the second a no-op success/`failed-precondition`; no double write.

## Testing

- **Functions (emulator):** ownership and payable-state rejections for both kinds; server price recompute (a booking whose stored `total` was tampered → `amount-mismatch`); **the exploit test — an order created for booking A cannot verify booking B (`order-booking-mismatch`)**, the single most important assertion in this slice; a successful verify writes `confirmed`/`paid` + `paymentId` + server amounts; a repeated verify doesn't double-write.
- **Rules (emulator):** a client cannot create a service booking with `status: 'confirmed'`; a client cannot write homestay `paid`; the cancel arms still work.
- **Lifecycle (unit):** `pending` → `awaitingPayment` before the date / `expired` after; `canPayService`; `canCancelService` for both `pending` and `confirmed`; legacy no-date bookings unchanged.
- **Widget:** BookingScreen creates a `pending` booking then navigates (and does not navigate on failure); both payment screens call `payForBooking` with the right `kind`/`bookingId` and navigate on success; cancelled/failed/unverified copy unchanged; no "Retry saving" affordance remains anywhere.
- `flutter analyze` clean, `tsc` builds, full suite green, debug APK builds.

## Prerequisites

The owner's Razorpay test setup (account + `RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET` secrets) — already pending from Slice 11; no new secrets. Code and unit tests need none of it.

## Deliverable / definition of done

The client can no longer state a price or declare a booking paid. Paying is: create/accept a booking → the server prices it from the listing and issues an order bound to that booking → the server verifies the payment against that binding and writes the paid state itself. A payment made for one booking cannot confirm another (emulator-proven), a tampered price is rejected before checkout, and the "paid but not saved" failure class no longer exists. `flutter analyze` clean, `tsc` exit 0, `flutter test` green, APK builds. **On merge + deploy this lifts the Slice-14 deploy gate**: `refundBookingPayment` becomes safe to deploy and live keys become safe to enable.
