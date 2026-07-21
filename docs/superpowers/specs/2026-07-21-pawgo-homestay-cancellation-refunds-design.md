# Pawgo Slice 14: Homestay cancellation & refunds — Design

> **Status:** approved design (2026-07-21). Slice B of the homestay-payments pair (Slice A = pay-to-confirm, merged). A guest can cancel a **paid** stay and receive a policy-based refund. Refunds are **money out**, so this is the project's first **server-computed, server-owned** money operation — a deliberately stricter posture than the pay-in flows. Runs in Razorpay **test mode** (test-mode refunds are simulated); live money needs live keys + KYC later.

## Goal

After Slice A, a paid homestay stay has no in-app cancellation — the row shows a "Contact host to cancel" placeholder. This slice replaces that (before check-in) with a real **Cancel & refund** flow: the guest sees the refund they'll get under a clear policy, confirms, and a Cloud Function issues the Razorpay refund and cancels the booking. The refund amount is **computed and issued entirely server-side** — the client never dictates how much money leaves.

## Cancellation policy (settled during brainstorming)

**One platform-default policy** (not per-host yet). Refund is a function of how far the cancellation is from check-in, computed on the stay **subtotal**; the **₹150 service fee is never refundable**:

| Cancel timing | Refund (of subtotal) |
|---|---|
| **≥ 24 hours before check-in** | 100% |
| **< 24 hours before check-in, or after check-in** | 0% |

(The "Flexible" Airbnb shape.) A guest can cancel a paid stay any time **before check-in** — inside 24h they can still cancel, but for ₹0, with explicit copy. **After check-in** (mid-stay) there is no in-app cancel; "Contact host to cancel" remains.

## Design decisions (settled during brainstorming)

- **Server-computed, server-owned refund.** A new Cloud Function `refundBookingPayment` reads the stored booking, computes the refund itself (never trusts the client), issues the Razorpay refund, and writes the cancellation with `firebase-admin`. The client only calls the function and reads the result.
- **No `firestore.rules` change.** Because the server writes the paid-cancellation with admin (bypassing rules), and the existing rules already (a) forbid a client `paid → cancelled` write and (b) block a client from touching `refundAmount`/`refundId` via their `hasOnly` guards, there is nothing to change. This is the whole point of the server-owned posture the Slice-A final review asked for.
- **Idempotent by transactional claim.** The function transactionally flips `paid → cancelled` (asserting the pre-state) *before* calling Razorpay, so a double-tap's second call sees a non-`paid` doc and aborts — no double refund.
- **The pure policy function is display-only on the client.** `refundRupees(stay, now)` shows the estimate in the confirm dialog; the server recomputes authoritatively. The client value is never trusted for the actual refund.
- **Unpaid cancellation is unchanged.** `requested`/`accepted` (no money) still cancel client-side via the existing `cancelStay`. Only a **paid** cancel goes through the refund function.
- **Reuse the `PaymentService` seam** (it already owns `cloud_functions`) for the client→function call — no new SDK imports leak out of `razorpay_payment_service.dart`.
- **Deferred:** per-host selectable policies; partial/deposit refunds; host-initiated cancellation; refund status polling/webhooks; a dedicated refund-notification type (the existing "was cancelled" host notification already fires); live Razorpay/KYC.

## Scope

**In scope**
- `lib/data/models/refund_policy.dart` — pure `refundRupees(HomestayBooking, DateTime now)`.
- `HomestayBooking.refundAmount` (int, default 0) + `refundId` (String, default '') — additive.
- `functions/src/index.ts` — new `refundBookingPayment` callable (+ `firebase-admin` init, `razorpay.payments.refund`).
- `PaymentService` seam: `RefundResult` + `refundStay({bookingId})`; `RazorpayPaymentService` impl; `FakePaymentService`.
- `booking_lifecycle.dart`: `canCancelPaidStay(stay, now)`.
- My-bookings paid row: **Cancel & refund** before check-in (refund-aware dialog), "Contact host" mid-stay, "₹X refunded" on a refunded row.
- Tests: policy unit, function emulator (auth/precondition/₹0 path/idempotency), widget (dialog + flow), on-device (>0 Razorpay refund).

**Out of scope**
- No `firestore.rules` change; no new packages (`firebase-admin`/`razorpay` already in `functions/`).
- No change to pay-in (`createBookingOrder`/`verifyBookingPayment`), the request/accept flow, or the Services pillar.
- Per-host policies, refund webhooks/polling, host-side cancellation, live keys.

## Refund policy (`lib/data/models/refund_policy.dart`)

```dart
import 'homestay_booking.dart';

/// Refund (in rupees, on the subtotal — the ₹150 service fee is never
/// refundable) for cancelling [b] at [now]. Display-only on the client; the
/// server recomputes this authoritatively in refundBookingPayment.
/// Policy: 100% of subtotal if >= 24h before check-in, else 0.
int refundRupees(HomestayBooking b, DateTime now) {
  if (!now.isBefore(b.checkIn)) return 0; // at/after check-in
  return b.checkIn.difference(now).inHours >= 24 ? b.subtotal : 0;
}
```

**Note on `checkIn`:** stored as an ISO date (midnight). So "≥24h before check-in" effectively means "cancel at least a full day before the check-in date." Time-based (hours), unlike the date-only phase logic — deliberate, because the policy cutoff is a real 24h window. The TS server mirrors this exactly.

## Model: `HomestayBooking` additive fields

`refundAmount` (int rupees, default 0) + `refundId` (String, default ''), in `toMap`/`fromMap` (`(m['refundAmount'] ?? 0) as int`, `(m['refundId'] ?? '') as String`). All existing/unpaid-cancelled stays keep 0/''. Written only by the function. A `cancelled` stay with `refundAmount > 0` is a refunded cancellation.

## Cloud Function `refundBookingPayment` (`functions/src/index.ts`)

First function that writes Firestore — add `import * as admin from "firebase-admin"; admin.initializeApp();` at the top (once). `onCall`, region `asia-south1`, `secrets: [razorpayKeyId, razorpayKeySecret]`.

Flow:
1. Reject unauth (`HttpsError('unauthenticated')`). Input `{ bookingId }` must be a non-empty string else `invalid-argument`.
2. **Transactionally claim** (`db.runTransaction`): read `homestayBookings/{bookingId}`; if missing → `not-found`; if `guestId != auth.uid` → `permission-denied`; if `status != 'paid'` → `failed-precondition('not-paid')`; parse `checkIn`; if `now >= checkIn` → `failed-precondition('after-checkin')`. Compute `refundRupees` server-side (`subtotal` if `>=24h` before check-in else `0`). Inside the transaction, set `{status:'cancelled', updatedAt, refundAmount:<computed>}` (claims the booking; `refundId` filled after). The transaction is pure (no network) — Razorpay is called after it commits.
3. **After** the transaction commits: if `refundAmount > 0`, require `paymentId` (else `failed-precondition('no-payment-id')`), call `new Razorpay({...}).payments.refund(paymentId, { amount: refundAmount * 100, speed: 'normal' })`, then `ref.update({ refundId: refund.id })`. On a Razorpay error, log it (`logger.error`) and throw `internal('refund-failed')` — the booking is already `cancelled` with `refundAmount` set but `refundId` empty (a tracked support/retry case; surfaced to the client as a failure).
4. Return `{ refundAmount, refundId }` (`refundId` '' for the ₹0 path).

**Why claim-before-refund:** it makes double-submits safe (second call finds non-`paid`) and means the authoritative amount is fixed at claim time. The small window where the doc is `cancelled` but `refundId` is still '' is acceptable and self-describing.

## Client seam (`lib/data/services/payment_service.dart`)

```dart
class RefundResult {
  final int refundAmount; // rupees actually refunded (0 for the <24h path)
  final String refundId;  // '' when refundAmount == 0
  const RefundResult({required this.refundAmount, required this.refundId});
}

// PaymentService +=
Future<RefundResult> refundStay({required String bookingId});
```

`RazorpayPaymentService.refundStay` calls `FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('refundBookingPayment').call({'bookingId': bookingId})` and maps the result. Failures reuse `PaymentException(failed, …)` (refunds have no "unverified" notion), but the message distinguishes the **post-claim** case: a `FirebaseFunctionsException` with code `internal` and message `refund-failed` (Razorpay failed *after* the booking was already cancelled) → `PaymentException(failed, 'refund-failed')`; any other failure (precondition, offline — booking unchanged) → `PaymentException(failed, 'cancel-failed')`. The screen keys its snackbar on `e.message` (see Error handling). `FakePaymentService` gains an optional `RefundResult refundResult` (default `RefundResult(refundAmount: 0, refundId: '')`) and an optional refund `error`, and records `refundedBookingIds`.

## Lifecycle (`booking_lifecycle.dart`)

Add:
```dart
bool canCancelPaidStay(HomestayBooking b, DateTime now) =>
    b.status == 'paid' && now.isBefore(b.checkIn);
```
`canCancelStay` (unpaid), `canPay`, `stayPhase`, `canRate` unchanged. A `paid` stay's phase stays `upcoming`/`completed`; the cancel affordance is gated by `canCancelPaidStay` (before check-in), and the mid-stay "Contact host" note by `paid && !canCancelPaidStay && phase == upcoming`.

## My-bookings paid row (`my_bookings_screen.dart`)

The stays loop passes `canCancelPaid: canCancelPaidStay(s, now)`, `refundEstimate: refundRupees(s, now)`, and keeps `showContactHost` for the mid-stay case (now `stayPhase == upcoming && !canCancelPaidStay(s, now)`). A cancelled stay with `s.refundAmount > 0` appends `· ₹{s.refundAmount} refunded` to its detail line.

`_MyBookingRow` gains `canCancelPaid`, `onCancelPaid`, `refundEstimate`. Action-column order: `★ Rated → Rate → Pay to confirm → Cancel (unpaid) → Cancel (paid → refund dialog) → Contact host note`. The paid Cancel opens a dedicated handler (`_confirmCancelPaid`) that builds the refund-aware dialog (copy per refund>0 / ==0 above), calls `refundStay`, and shows the success/failure snackbar; `mounted`-guarded.

Exact copy: dialog title `Cancel this stay?`; body (refund>0) `You'll be refunded ₹{X} of ₹{total}. Refunds take 5–7 business days. The ₹150 service fee isn't refundable.`; body (refund==0) `Cancellations within 24 hours of check-in aren't refundable — you'll be refunded ₹0.`; confirm label (>0) `Cancel & refund`, (==0) `Cancel anyway`; keep label `Keep`; success snackbar (>0) `Stay cancelled. ₹{X} will be refunded in 5–7 days.`, (==0) `Stay cancelled.`; failure — pre-claim (`cancel-failed`) `Couldn't cancel the stay — try again.`, post-claim refund failure (`refund-failed`) `Stay cancelled, but the refund didn't go through — contact support.`; refunded-row suffix `· ₹{amount} refunded`.

## Error handling

- Double-tap → the transactional claim makes the second call a `failed-precondition` (already non-paid) → surfaced as the failure snackbar; no double refund.
- Razorpay refund fails **after** the claim → booking is `cancelled` (the stream flips the row to Cancelled) with `refundAmount` set, `refundId` ''; the function throws `internal('refund-failed')`, and the client shows the honest post-claim message `Stay cancelled, but the refund didn't go through — contact support.` (a tracked reconciliation case) — NOT "couldn't cancel", which would contradict the now-cancelled row.
- Pre-claim failure (precondition, offline — the claim never committed, booking unchanged) → `cancel-failed` message `Couldn't cancel the stay — try again.`
- A ₹0 cancel issues no Razorpay call; it just marks cancelled with `refundAmount: 0`.

## Testing

- **refund_policy (unit):** `subtotal` at exactly 24h and beyond; `0` at 23h59m, at check-in, and after; fee never included; different subtotals.
- **Cloud Function (functions+firestore emulator):** rejects unauth / non-guest / non-`paid` / after-check-in; the **₹0 path** (a stay <24h out) marks the booking `cancelled` with `refundAmount: 0` and makes **no** Razorpay call; a second call to an already-cancelled booking aborts (`failed-precondition`). The **>0 Razorpay refund** path is on-device (needs the real Razorpay test network, like `createBookingOrder`). If the emulator can't run in-session, defer to the owner pass (per prior slices).
- **Widget (FakePaymentService via pumpPgApp):** a paid/before-check-in row shows "Cancel"; tapping shows the dialog with the correct ₹X estimate; the <24h fixture shows the ₹0 non-refundable copy; confirm calls `refundStay(bookingId:)` and (via the fake flipping the stay) the row shows Cancelled; a cancelled fixture with `refundAmount: 900` shows "· ₹900 refunded"; a mid-stay paid fixture shows "Contact host to cancel"; dismissing the dialog writes nothing.
- **On-device (owner pass, after deploy):** pay a stay, then cancel it ≥24h before check-in → Razorpay test dashboard shows the refund, the booking reads `cancelled · ₹{subtotal} refunded`; cancel another <24h out → ₹0, no refund on the dashboard.
- `flutter analyze` clean; existing tests green (additive fields; new lifecycle permission doesn't alter existing phases).

## Prerequisites

The owner's Slice-11 Razorpay Functions setup (test account + secrets + `firebase deploy --only functions`) — the same pending prerequisite; `refundBookingPayment` deploys alongside. No new secrets. `firebase-admin` already declared.

## Deliverable / definition of done

A guest with a paid, not-yet-started stay taps **Cancel**, sees exactly what they'll be refunded under the policy, confirms, and the stay flips to **Cancelled · ₹X refunded** — with the refund issued by the server (visible in the Razorpay test dashboard) and the amount computed server-side, never by the client. Cancelling inside 24h refunds ₹0 with clear copy; mid-stay stays "Contact host". Double-taps can't double-refund. `flutter analyze` clean, `flutter test` green, functions `tsc` builds, debug APK builds; no `firestore.rules` change.
