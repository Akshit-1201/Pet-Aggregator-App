# Pawgo Slice 13: Homestay pay-to-confirm — Design

> **Status:** approved design (2026-07-21). Slice A of the homestay-payments pair. After a host accepts a stay request, the guest pays (real Razorpay test-mode checkout) to confirm it — reusing the entire `PaymentService`/Cloud-Functions machinery from Slice 11 (Services payments). Slice B (cancellation policy + server-computed refunds) is a separate follow-up spec; this slice deliberately leaves paid stays non-self-cancellable as a temporary placeholder that Slice B replaces.

## Goal

Today a homestay stay goes `requested → accepted` with **no money moving** — the host accepts and the stay is "confirmed" for free. This slice adds the honest confirm step: a host-accepted stay is *not* a real booking until the guest **pays to confirm**. Paying charges the total via Razorpay and moves the stay to a new `paid` status; only then is it an Upcoming/confirmed stay that can later be rated. An accepted stay never paid before check-in simply expires.

## Design decisions (settled during brainstorming)

- **Payment confirms the stay.** `accepted` (host said yes, unpaid) is an *action-needed* state for the guest, phase **`awaitingPayment` ("Pay to confirm")**. Only paying (→ status `paid`) makes it a real Upcoming stay. An `accepted` stay whose check-in passes unpaid → **`expired`** (never happened, never rateable). `canRate` stays `completed`-only, and `completed` is now only reachable via `paid` — so rating automatically requires payment.
- **No self-cancel once paid — temporary.** The guest can still cancel a `requested` or `accepted` (unpaid) stay freely (no money involved). A `paid` stay has **no in-app Cancel this slice**; the row shows a passive "Contact host to cancel" note. This is a deliberate placeholder: **Slice B** (cancellation policy + tiered server-computed refunds) replaces it with a real refund-cancel flow. Refunds are out of scope here.
- **Reuse everything from Slice 11.** The generic `PaymentService` seam (`payForBooking({amountRupees, description, onVerifying})`), the `createBookingOrder`/`verifyBookingPayment` Cloud Functions, the `PaymentException`/`PaymentErrorType` taxonomy, and the payment-screen phase machine + copy are reused verbatim. No new packages, no new Functions.
- **`markPaid` is the only new write** — the guest's `accepted → paid` transition, carrying `status`+`updatedAt`+`paymentId`. It's the one homestay transition that writes a `paymentId`.
- **Same honest client-trust posture as Services.** The client sends the amount and performs the `paid` update after server-verified payment; server-owned pricing/writes remain the tracked project-wide follow-up. (Money-*out* refunds in Slice B will instead be server-computed — a deliberately stricter posture.)
- **One new derived host notification** ("stay is confirmed & paid"), following the Slice-10 derived-feed pattern — no new collection.
- **Deferred:** cancellation/refunds (Slice B); host-side "mark stay complete"; partial payment; per-host cancellation policies; live Razorpay/KYC (test mode, same as Slice 11).

## Scope

**In scope**
- `HomestayBooking.paymentId` (additive `String`, default `''`).
- `booking_lifecycle.dart`: new `BookingPhase.awaitingPayment`; reworked `stayPhase` (paid/accepted/requested); new `canPay(stay, now)`. `canCancelStay` is left unchanged (it already excludes `paid`).
- `HomestayBookingRepository.markPaid(id, paymentId)` (interface + Firestore impl + fake).
- `firestore.rules`: a third `update` branch for the guest `accepted → paid` transition (allows the extra `paymentId` key); emulator matrix test.
- `HomestayPaymentScreen` (new) — reuses `PaymentService`; on verified payment calls `markPaid`.
- My-bookings row: "Pay to confirm" affordance for `awaitingPayment`; no Cancel for `paid` (passive "Contact host to cancel").
- Router: `/homestay-payment` route carrying a `HomestayBooking`.
- One new derived host notification (received stay reaches `paid`).

**Out of scope (Slice B / later)**
- Cancelling a paid stay + any refund (partial or full), the refund Cloud Function, refund state/fields — all Slice B.
- Host "mark complete", partial/deposit payments, per-host cancellation policies, live keys/KYC.
- No change to the Services payment flow, the `Booking` model, or the request-creation flow.

## Lifecycle (after this slice)

```
requested ──host accept──▶ accepted ──guest pay──▶ paid
    │                          │                      │
 (guest cancel)          (guest cancel)          (NO self-cancel this slice)
    ▼                          ▼                      ▼
cancelled                 cancelled            upcoming → completed (rateable)

Derived phases (stayPhase):
  requested : pending (before check-in) | expired (check-in passed)
  accepted  : awaitingPayment (before check-in) | expired (check-in passed, never paid)
  paid      : upcoming (before checkout) | completed (checkout passed)
  declined  : declined      cancelled : cancelled
```

## `booking_lifecycle.dart` changes

Add the phase and rework `stayPhase` (pure, `now` injected — unchanged discipline):

```dart
enum BookingPhase {
  pending('Pending'),
  awaitingPayment('Pay to confirm'),
  upcoming('Upcoming'),
  completed('Completed'),
  declined('Declined'),
  cancelled('Cancelled'),
  expired('Expired');
  final String label;
  const BookingPhase(this.label);
}

BookingPhase stayPhase(HomestayBooking b, DateTime now) {
  switch (b.status) {
    case 'declined':
      return BookingPhase.declined;
    case 'cancelled':
      return BookingPhase.cancelled;
    case 'paid':
      return _day(b.checkOut).isBefore(_day(now)) ? BookingPhase.completed : BookingPhase.upcoming;
    case 'accepted':
      return _day(b.checkIn).isBefore(_day(now)) ? BookingPhase.expired : BookingPhase.awaitingPayment;
    default: // 'requested'
      return _day(b.checkIn).isBefore(_day(now)) ? BookingPhase.expired : BookingPhase.pending;
  }
}

bool canPay(HomestayBooking b, DateTime now) =>
    b.status == 'accepted' && !_day(b.checkIn).isBefore(_day(now));
```

- **`canCancelStay` is UNCHANGED** from Slice 10 — it already matches only `requested`/`accepted` (never `paid`), so "no self-cancel once paid" holds with zero edits. Keeping it verbatim also preserves its existing window semantics (requested cancellable through the check-in day; accepted only strictly before check-in), which a Slice-10 test pins:
  ```dart
  bool canCancelStay(HomestayBooking b, DateTime now) =>
      (b.status == 'requested' && !_day(b.checkIn).isBefore(_day(now))) ||
      (b.status == 'accepted' && _day(now).isBefore(_day(b.checkIn)));
  ```
- `servicePhase`, `canRate`, `canCancelService`, `canDecide` unchanged. `canRate` remains `p == completed` — now only reachable through `paid`.
- **Note:** the old `stayPhase` treated `accepted` past checkout as `completed`; now an `accepted` (unpaid) stay past check-in is `expired`. This is the intended semantic change (unpaid ≠ completed). Legacy data: any pre-slice stay already in `accepted` becomes `awaitingPayment`/`expired` — surfacing the (correct) fact that it was never paid. Acceptable; there is no production data yet (payments not live).

## Model: `HomestayBooking.paymentId`

Additive `String paymentId` (default `''`), in `toMap`/`fromMap` (`(m['paymentId'] ?? '') as String`), mirroring `Booking.paymentId` from Slice 11. All existing/requested/accepted stays keep `''`; written only by `markPaid`.

## Repository: `markPaid`

```dart
// HomestayBookingRepository +=
Future<void> markPaid(String id, String paymentId);
```

Firestore impl: `_col.doc(id).update({'status': 'paid', 'updatedAt': DateTime.now().millisecondsSinceEpoch, 'paymentId': paymentId})` (client millis, matching the `createdAt`/`updatedAt` convention). Fake mirrors it (rebuild via `fromMap({...toMap(), status:'paid', updatedAt:…, paymentId:…})`). No new provider — reuse `homestayBookingRepositoryProvider`.

## Firestore rules

The `homestayBookings` `update` rule gains a third allowed transition (guest pay), which needs the extra `paymentId` key — so the `hasOnly` guard differs per branch:

```
allow update: if request.auth != null && (
    // accept/decline/cancel: only status + updatedAt
    ( request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt'])
      && (
        (resource.data.hostId == request.auth.uid
          && resource.data.status == 'requested'
          && request.resource.data.status in ['accepted', 'declined'])
        || (resource.data.guestId == request.auth.uid
          && resource.data.status in ['requested', 'accepted']
          && request.resource.data.status == 'cancelled')
      )
    )
    // guest pay: accepted -> paid, may also set paymentId
    || ( resource.data.guestId == request.auth.uid
      && resource.data.status == 'accepted'
      && request.resource.data.status == 'paid'
      && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt', 'paymentId'])
    )
  );
```

`create` (status must be `requested`) and `delete: false` unchanged. Deployed via CLI. Emulator matrix test: guest pays an `accepted` stay (→ `paid`, paymentId set); guest cannot pay a `requested` or `declined` stay; host cannot pay; the guest cancel-of-`accepted` arrow still works; a `paid` stay cannot be cancelled by the guest (no matching branch); no write may touch any field beyond the allowed keys.

## `HomestayPaymentScreen` (`lib/features/homestay/homestay_payment_screen.dart`)

A near-clone of `PaymentScreen` (services), differing only in the model it summarizes and the write it performs. Reuses the exact `_PayPhase` machine (`idle/opening/verifying/saving/retrySave`), `_busy`, the `payForBooking` call, and the identical snackbar copy + button-label logic (cancelled/failed/unverified/retry).

- Takes a `HomestayBooking? stay` via `extra`; null → "No booking" guard.
- Summary card: home name, host, `checkIn → checkOut`, `nights`, `subtotal`, `₹150 service fee`, `total`; plus `🔒 Secured by Razorpay — UPI, cards & netbanking`.
- Bottom bar: Total + gradient button; `payForBooking(amountRupees: stay.total, description: '${stay.homeName} · ${stay.nights} nights')`.
- On verified payment → `_phase = saving` → `ref.read(homestayBookingRepositoryProvider).markPaid(stay.id, paid.paymentId)` → on success `context.go(Routes.bookings)` (back to My-bookings, where the row now shows Upcoming). The `_paid` cache + "Retry saving" (retries only the `markPaid` write, never re-charges) is preserved exactly as Services.
- All async handlers guard `mounted`; unverified surfaces the `paymentId`.

Router: `GoRoute(path: Routes.homestayPayment, builder: (_, state) => HomestayPaymentScreen(stay: state.extra as HomestayBooking?))`; add `Routes.homestayPayment = '/homestay-payment'`; add it to `_protected`.

## My-bookings row (`_MyBookingRow` in `my_bookings_screen.dart`)

The stays loop passes a `canPay` flag and a paid indicator. The action column priority becomes: `★ Rated` → `Rate` (canRate) → **`Pay to confirm`** (canPay, gradient like Rate) → `Cancel` (canCancelStay). For a `paid`/upcoming stay (not canCancel, not canRate) show a passive muted note **"Contact host to cancel"** instead of a Cancel action. "Pay to confirm" → `context.push(Routes.homestayPayment, extra: stay)`. (Services rows are unaffected — service bookings have no `canPay`.)

## Notifications (`buildNotifications`)

Extend the `receivedStays` loop with a `paid` branch (alongside the existing `requested`/`cancelled`):

```dart
    } else if (s.status == 'paid') {
      final ts = _eventTs(s.updatedAt, s.createdAt);
      items.add(NotificationItem(
          type: PgNotificationType.homestay,
          icon: '💰', accent: const Color(0xFF34B27B),
          title: "${s.petName}'s stay is confirmed & paid",
          body: '${s.homeName} · ${HomestayBooking.fmtDay(s.checkIn)} · ${s.nights} nights',
          timestamp: ts, route: Routes.bookings, extra: 1, read: !unread(ts)));
    }
```

## Error handling

- `markPaid` write fails after a verified payment → the reused "Retry saving" state (button retries only the write; the verified `paymentId` is cached so no second charge), with the payment id surfaced — identical to Services.
- Payment cancelled/failed → stay stays `accepted` (awaitingPayment); nothing written; honest snackbar.
- Unverified (gateway succeeded, verify failed) → not marked paid; snackbar surfaces the `paymentId`; never claims "not charged".
- Malformed/missing stay via `extra` → "No booking" guard, no crash.

## Testing

- **booking_lifecycle:** `awaitingPayment` for `accepted` before check-in; `expired` for `accepted`/`requested` past check-in; `paid` → `upcoming`/`completed` at the checkout boundary; `canPay` true only for `accepted` before check-in; `canCancelStay` unchanged and **false for `paid`** (add a regression test asserting a `paid` stay is not cancellable); `canRate` completed-only (reached via paid).
- **Repository (fake + emulator):** `markPaid` writes exactly `status:'paid'`+`updatedAt`+`paymentId`; the emulator rules matrix above.
- **HomestayPaymentScreen (FakePaymentService via pumpPgApp):** success → `markPaid` called with the fake's `paymentId`, stay becomes `paid`, navigates to `/bookings`; cancelled/failed → not paid + correct snackbar; unverified → not paid + snackbar carries paymentId; write-fails-after-pay → "Retry saving" writes without a second charge (single `chargedAmounts`); button disabled in-flight.
- **My-bookings:** an `awaitingPayment` stay shows "Pay to confirm" + "Cancel"; tapping Pay opens `HomestayPaymentScreen`; a `paid`/upcoming stay shows no Cancel (passive "Contact host to cancel"); a completed paid stay shows Rate.
- **Notifications:** a received `paid` stay produces the "confirmed & paid" host item (timestamp `updatedAt`, deep-link Received tab).
- `flutter analyze` clean; existing tests green (the `stayPhase` semantic change may touch Slice-10 tests that asserted `accepted`-past-checkout → completed; update those to the new `paid` path — an intended, documented change).

## Prerequisites

None beyond Slice 11's (the same Razorpay test account + deployed Functions the owner still needs to set up before an on-device pass; code + emulator tests need neither).

## Deliverable / definition of done

A guest whose stay request was accepted sees "Pay to confirm ₹{total}" in My-bookings, taps it, completes a real Razorpay test checkout, and the stay flips to a `paid`/Upcoming booking (with a `paymentId`) that can be rated after checkout; the host's feed shows "confirmed & paid"; an accepted stay left unpaid past check-in reads "Expired"; paid stays show no in-app Cancel (Slice B). Rules block every invalid pay transition (emulator-verified). `flutter analyze` clean, `flutter test` green, debug APK builds.
