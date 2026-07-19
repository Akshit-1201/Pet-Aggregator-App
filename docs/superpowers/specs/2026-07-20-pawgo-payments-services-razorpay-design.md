# Pawgo Slice 11: Payments (Services · Razorpay test mode) — Design

> **Status:** approved design (2026-07-20). First of the Payments phase (the plan's "Phase 10"), split like Services/Homestay were: **services checkout now, homestay pay-after-accept is the follow-up slice.** Runs the full production-shaped Razorpay integration in **test mode** — real checkout UI, test UPI/cards, signature verification — with **no real money** and no KYC. Introduces the project's **first Cloud Functions**.

## Goal

Replace the fake payment theater (VISA •••• 4421, "Card on file", fake UPI rows) with a real Razorpay Checkout on the services booking flow. "Pay" opens the actual gateway; a booking is written **only after the payment's signature is verified server-side**, stamped with its `paymentId`. Cancel and failure leave no booking and say so honestly.

## Design decisions (settled during brainstorming)

- **Test mode now.** The integration is production-shaped end-to-end (Orders API, Checkout, HMAC verification); going live later is a Razorpay KYC + swapping the two stored secrets — no code change. Every dev/emulator payment uses Razorpay's test instruments.
- **Services only.** Homestays keep their free request flow; the "pay to confirm after host accepts" step is its own next slice on these rails.
- **Functions verify + client writes.** Two small callable Cloud Functions own the key secret: `createBookingOrder` (makes the Razorpay Order) and `verifyBookingPayment` (checks the HMAC). After a verified payment the app writes the booking exactly as today — the repository seam, `bookings` create rules, and Slice-10 lifecycle all stay untouched.
- **Honest limitation, documented:** the client still supplies the amount and still writes the booking, so a tampered client could underpay or skip payment. Same client-trust posture as the rest of the codebase; server-owned pricing + server-written bookings stay on the tracked rules-hardening follow-up, for which these Functions are the foundation.
- **SDK isolation:** `razorpay_flutter` and `cloud_functions` are imported ONLY in the `RazorpayPaymentService` implementation file. Screens see a `PaymentService` interface; tests use a fake. (Both packages have been pre-declared in `pubspec.yaml` since Slice 1 — first actual import now.)
- **The fake payment UI is removed, not restyled.** No pretend card-on-file, no fake wallet balance — the prototype's payment screen is visual theater and the owner's directive is a real app. The bottom Total + gradient Pay bar keeps the prototype styling.
- **Deferred:** homestay payment; live keys/KYC; refunds (cancelling a paid booking moves no money back — copy stays silent about refunds); Razorpay webhooks (client callback + verify is enough at this scale); server-owned pricing/writes; saved cards/wallets; App Check enforcement on the callables.

## Scope

**In scope**
- `functions/` — first Cloud Functions workspace (TypeScript, Functions v2, Node 20, region `asia-south1`): `createBookingOrder`, `verifyBookingPayment`, secrets via `defineSecret`.
- `lib/data/services/payment_service.dart` — `PaymentService` interface + `PaymentResult` + typed `PaymentException`.
- `lib/data/services/razorpay_payment_service.dart` — the real implementation (sole importer of `razorpay_flutter` + `cloud_functions`).
- `Booking.paymentId` (additive model field) written on create.
- `PaymentScreen` rework: honest order summary, real checkout states, cancel/failure handling.
- `firebase.json` functions emulator entry; a Functions-emulator integration test for signature verification.
- Owner setup: Razorpay test keys → Functions secrets → `firebase deploy --only functions`.

**Out of scope (later)**
- Homestay pay-after-accept (next slice): Pay button on accepted stays, `paid` state, its notifications.
- Live mode (KYC, live secrets, Proguard rules for release builds — belongs to launch prep).
- Refund flows, payment history UI, webhooks, payouts to pros/hosts.
- Server-owned pricing & booking writes (tracked rules-hardening follow-up).

## Cloud Functions (`functions/`)

First Functions in the project. `firebase init functions` layout: TypeScript, Node 20, ESLint off (repo convention is `flutter analyze`; keep the Functions toolchain minimal). Both callables are **Functions v2 `onCall`**, region **`asia-south1`** (same as Firestore), with `secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET]` declared via `defineSecret`.

### `createBookingOrder`

- Rejects unauthenticated calls (`HttpsError('unauthenticated')`).
- Input `{ amountRupees: number }` — must be an integer in `1..100000`, else `HttpsError('invalid-argument')`.
- Calls the Razorpay Orders API (official `razorpay` npm SDK) with `amount: amountRupees * 100` (paise), `currency: 'INR'`, `receipt: 'bk_' + uid + '_' + Date.now()`.
- Returns `{ orderId, amountPaise, keyId }` — the app never hardcodes the key id; it always arrives per-order from the server, so a key rotation is server-only.
- Razorpay/API failure → `HttpsError('internal', 'order-failed')`.

### `verifyBookingPayment`

- Rejects unauthenticated calls.
- Input `{ orderId, paymentId, signature }` (all non-empty strings, else `invalid-argument`).
- Computes `HMAC-SHA256(orderId + '|' + paymentId, RAZORPAY_KEY_SECRET)` (Node `crypto`, timing-safe compare) and compares to `signature`.
- Match → `{ verified: true }`. Mismatch → `HttpsError('permission-denied', 'signature-mismatch')`.
- **Pure crypto, no network** — fully testable against the Functions emulator with a locally computed signature.

### Secrets & emulator

- Production: `firebase functions:secrets:set RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` (owner runs; values from Razorpay Dashboard → Settings → API Keys, test mode).
- Emulator: `functions/.secret.local` (git-ignored) holds dummy values (e.g. `RAZORPAY_KEY_SECRET=test_secret`); the integration test computes its HMAC with the same dummy, so verification is tested without any Razorpay account.
- `firebase.json` gains `"functions": { "source": "functions" }` and an emulators entry `"functions": { "port": 5001 }`.

## Client seam (`lib/data/services/`)

```dart
// payment_service.dart — interface only, no SDK imports
class PaymentResult {
  final String paymentId, orderId;
  const PaymentResult({required this.paymentId, required this.orderId});
}

enum PaymentErrorType { cancelled, failed, unverified }

class PaymentException implements Exception {
  final PaymentErrorType type;
  final String message;
  final String paymentId; // set only for unverified (money may have moved)
  const PaymentException(this.type, this.message, {this.paymentId = ''});
}

abstract interface class PaymentService {
  /// Opens checkout for [amountRupees]; returns only after server-side
  /// signature verification. Throws PaymentException(cancelled) when the
  /// user backs out, PaymentException(failed) on gateway/verification failure.
  Future<PaymentResult> payForBooking({
    required int amountRupees,
    required String description,
  });
}
```

`RazorpayPaymentService` (the ONLY file importing `razorpay_flutter` + `cloud_functions`):

1. `FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('createBookingOrder')` → `{orderId, amountPaise, keyId}`.
2. Opens Checkout: `Razorpay().open({ 'key': keyId, 'order_id': orderId, 'amount': amountPaise, 'currency': 'INR', 'name': 'Pawgo', 'description': description, 'theme': {'color': '#F59E2E'} })`.
3. Bridges the plugin's event API (`EVENT_PAYMENT_SUCCESS` / `EVENT_PAYMENT_ERROR` / external-wallet) to a single `Completer`: success → calls `verifyBookingPayment` with the response's `orderId/paymentId/signature`, then completes with `PaymentResult`; error code `Razorpay.PAYMENT_CANCELLED` → `PaymentException(cancelled)`; any other gateway error or a `createBookingOrder` failure → `PaymentException(failed)` (nothing was charged); a gateway SUCCESS whose verification then rejects or errors → `PaymentException(unverified, paymentId: …)` — money may have moved, so this is never conflated with `failed`.
4. Always `clear()`s the Razorpay instance listeners afterwards; a `payForBooking` call while one is in flight throws `PaymentException(failed, 'busy')`.

Provider: `paymentServiceProvider` in `providers.dart` (`Provider<PaymentService>((ref) => RazorpayPaymentService())`). Tests override with `FakePaymentService` (configurable: succeed with a canned `PaymentResult`, throw cancelled, throw failed; records the amounts it was asked to charge).

## Model: `Booking.paymentId`

Additive `String paymentId` (default `''`), in `toMap`/`fromMap` (plain `(m['paymentId'] ?? '') as String`). All existing bookings and the whole homestay pillar keep `''`. Written by the payment flow on create; displayed nowhere this slice. **No `firestore.rules` change** — the `bookings` create guard checks `parentId` + `status == 'confirmed'` only, and extra fields are allowed on create.

## `PaymentScreen` rework

- **Removed:** the gradient VISA card, "Card on file", the fake UPI row, the fake "Pawgo Wallet ₹1,540" row.
- **Body:** an order summary card in the standard row style — pro name, `ServiceType.label`, `dateLabel · timeSlot`, pet name, then `Rate ₹x / Service fee ₹y / Total ₹z` lines — plus a muted note row: `🔒 Secured by Razorpay — UPI, cards & netbanking`.
- **Bottom bar unchanged** (prototype styling): Total + gradient button.
- **States:** `Pay ₹X` → tap → `Opening…` (order being created / checkout on screen) → `Verifying…` (signature check) → booking written (with `paymentId`) → `context.go(Routes.bookingConfirmed, extra: booking)` exactly as today. Button disabled while in flight.
- **Cancel:** snackbar `Payment cancelled — you haven't been charged.`, button returns to idle, nothing written.
- **Failure (gateway declined / order creation failed):** snackbar `Payment failed — you haven't been charged. Try again.`, idle, nothing written.
- **Verification mismatch (`unverified`):** snackbar `Payment couldn't be verified — note payment id {paymentId} and contact support.`, idle, nothing written. Never claims "you haven't been charged".
- **Booking write fails after a verified payment** (worst case): snackbar `Payment received (id {paymentId}) but saving the booking failed — try again or contact support.` and the button becomes `Retry saving` which retries ONLY the write (no second charge). All async handlers guard `mounted`.

## Error handling summary

| Failure point | User sees | Booking written? | Charged? |
|---|---|---|---|
| `createBookingOrder` fails (offline, Functions down) | failed snackbar | no | no |
| User backs out of Checkout | cancelled snackbar | no | no |
| Gateway declines / test payment fails | failed snackbar | no | no |
| Signature verification rejects | unverified snackbar (shows paymentId) | no | yes (test money) — visible in Razorpay dashboard; refund is manual/deferred |
| Booking write fails after verify | retry-saving state with paymentId shown | retryable | yes (test money) |

## Testing

- **Widget (FakePaymentService via `pumpPgApp`):** success → booking written once with the fake's `paymentId`, navigates to Booking-confirmed; cancelled → no booking, cancel snackbar, button idle; failed → no booking, failure snackbar; unverified → no booking, verification snackbar containing the `paymentId`; button disabled while a payment is in flight; the fake records that it was asked for exactly `draft.total` rupees. Existing payment/booking tests updated to override `paymentServiceProvider`.
- **Functions emulator (integration_test):** with the functions emulator running (`.secret.local` dummy secret), `verifyBookingPayment` returns `{verified:true}` for a locally computed valid HMAC and throws for a tampered signature; both callables reject unauthenticated calls. (`createBookingOrder`'s Razorpay call needs the real network — covered by the on-device pass.)
- **On-device (manual, after owner setup + deploy):** a real test-mode checkout on the Android emulator — success via test UPI (`success@razorpay`) produces a verified booking with a `paymentId` visible in Firestore + the payment in the Razorpay test dashboard; back-button cancel and a failing test instrument leave no booking.
- `flutter analyze` clean; all existing tests green (model field is additive; the payment flow change is behind the seam).

## Prerequisites (owner-side, before the on-device pass — code + emulator tests don't need them)

1. Create a free Razorpay account (razorpay.com) — test mode, no KYC.
2. Dashboard → Settings → API Keys → generate **test** Key ID + Key Secret.
3. `firebase functions:secrets:set RAZORPAY_KEY_ID` and `...:set RAZORPAY_KEY_SECRET` (interactive; run with `!`).
4. `firebase deploy --only functions --project pet-aggregator-app` (run with `!` if the classifier blocks it).

## Deliverable / definition of done

Booking a walker on the emulator opens the real Razorpay test checkout; paying with `success@razorpay` lands on Booking-confirmed with a `paymentId`-stamped booking that the Bookings hub shows as Upcoming; backing out or failing the payment writes nothing and says so; `verifyBookingPayment` provably rejects tampered signatures (emulator test); `flutter analyze` clean, `flutter test` green, debug APK builds, functions deployed to `asia-south1`.
