# Pawgo Slice 14: Homestay cancellation & refunds — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A guest can cancel a paid homestay stay before check-in and get a policy-based Razorpay refund, computed and issued entirely server-side by a new `refundBookingPayment` Cloud Function (never trusting the client), with a clear cancel-with-refund UI.

**Architecture:** A pure `refundRupees` policy function (display-only on the client; mirrored authoritatively in TS). The Function transactionally claims `paid → cancelled` (idempotent against double-taps), computes the refund, calls Razorpay's refund API, and writes with `firebase-admin`. The client reaches it through the existing `PaymentService` seam (`refundStay`). Two additive model fields; **no `firestore.rules` change** (the server owns the write).

**Tech Stack:** Flutter/Dart ^3.12.2, `flutter_riverpod` 3.x, `go_router`; Firebase Functions v2 (TypeScript), `firebase-admin` + `razorpay` (both already in `functions/`). Reuses `cloud_functions` only through `razorpay_payment_service.dart`.

**Spec:** `docs/superpowers/specs/2026-07-21-pawgo-homestay-cancellation-refunds-design.md`.

## Global Constraints

- Keep `android/gradle.properties` → `kotlin.incremental=false`.
- No new packages, no new secrets, **no `firestore.rules` change** (the refund is server-written via admin; existing rules already forbid a client `paid → cancelled` write and block `refundAmount`/`refundId`).
- **Policy:** refund = `subtotal` (rupees) if cancelling **≥24h before check-in**, else `0`. The ₹150 service fee is never refunded. `checkIn` is a date (midnight); interpret it as **IST (+05:30)** on the server to match the client's device-local parse (Mumbai-market app). The client value is **display-only**; the server recomputes authoritatively.
- Refund Function does exactly: transactionally claim `paid → cancelled` (assert guest + `status=='paid'` + before check-in) writing `{status,updatedAt,refundAmount}`; then (if refund>0) call `razorpay.payments.refund(paymentId, {amount: refundAmount*100, speed:'normal'})` and `update({refundId})`. A ₹0 cancel makes no Razorpay call.
- SDK isolation unchanged: `razorpay_flutter`/`cloud_functions` only in `lib/data/services/razorpay_payment_service.dart`.
- Exact copy (verbatim): dialog title `Cancel this stay?`; body (refund>0) `You'll be refunded ₹{X} of ₹{total}. Refunds take 5–7 business days. The ₹150 service fee isn't refundable.`; body (refund==0) `Cancellations within 24 hours of check-in aren't refundable — you'll be refunded ₹0.`; confirm (>0) `Cancel & refund`, (==0) `Cancel anyway`; keep `Keep`; success (>0) `Stay cancelled. ₹{X} will be refunded in 5–7 days.`, (==0) `Stay cancelled.`; failure pre-claim (`cancel-failed`) `Couldn't cancel the stay — try again.`, post-claim (`refund-failed`) `Stay cancelled, but the refund didn't go through — contact support.`; refunded-row suffix ` · ₹{amount} refunded`.
- Riverpod 3.x `.value`; async handlers guard `context.mounted` after `await`; widget tests use `pumpPgApp` + fakes.
- Every task ends green: `flutter analyze` clean + `flutter test` passes, then commit. Do NOT push. Do NOT deploy (Task 5 hands deploy to the owner).

---

### Task 1: `refund_policy.dart` (pure) + `HomestayBooking.refundAmount`/`refundId`

**Files:**
- Create: `lib/data/models/refund_policy.dart`
- Modify: `lib/data/models/homestay_booking.dart`
- Test: `test/data/refund_policy_test.dart` (create)

**Interfaces:**
- Produces: `int refundRupees(HomestayBooking b, DateTime now)`; `HomestayBooking.refundAmount` (int, default 0), `HomestayBooking.refundId` (String, default '').

- [ ] **Step 1: Write the failing test**

```dart
// test/data/refund_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/refund_policy.dart';

HomestayBooking _stay({required DateTime checkIn, int subtotal = 2700}) => HomestayBooking(
    id: 'hb1', guestId: 'g', hostId: 'h', homeName: 'H', hostName: 'M', petId: 'x',
    petName: 'Bruno', ratePerNight: 900, checkIn: checkIn,
    checkOut: checkIn.add(const Duration(days: 3)), nights: 3, subtotal: subtotal,
    fee: 150, total: subtotal + 150, status: 'paid');

void main() {
  final now = DateTime(2026, 7, 19, 12, 0);

  test('>= 24h before check-in refunds the full subtotal', () {
    expect(refundRupees(_stay(checkIn: now.add(const Duration(hours: 24))), now), 2700);
    expect(refundRupees(_stay(checkIn: now.add(const Duration(days: 5))), now), 2700);
    expect(refundRupees(_stay(checkIn: now.add(const Duration(hours: 24)), subtotal: 5000), now), 5000);
  });

  test('< 24h before check-in refunds 0', () {
    expect(refundRupees(_stay(checkIn: now.add(const Duration(hours: 23, minutes: 59))), now), 0);
    expect(refundRupees(_stay(checkIn: now.add(const Duration(hours: 1))), now), 0);
  });

  test('at or after check-in refunds 0', () {
    expect(refundRupees(_stay(checkIn: now), now), 0);
    expect(refundRupees(_stay(checkIn: now.subtract(const Duration(hours: 2))), now), 0);
  });

  test('HomestayBooking.refundAmount/refundId round-trip and default', () {
    final b = _stay(checkIn: now);
    expect(HomestayBooking.fromMap('hb1', b.toMap()).refundAmount, 0);
    expect(HomestayBooking.fromMap('hb1', b.toMap()).refundId, '');
    final r = HomestayBooking.fromMap('hb1', {...b.toMap(), 'refundAmount': 900, 'refundId': 'rfnd_1'});
    expect(r.refundAmount, 900);
    expect(r.refundId, 'rfnd_1');
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (`refund_policy.dart`/fields don't exist)

Run: `flutter test test/data/refund_policy_test.dart`

- [ ] **Step 3: Create `refund_policy.dart`**

```dart
// lib/data/models/refund_policy.dart
import 'homestay_booking.dart';

/// Refund (rupees, on the subtotal — the ₹150 service fee is never refundable)
/// for cancelling [b] at [now]. Display-only on the client; refundBookingPayment
/// recomputes this authoritatively server-side. Policy: 100% of subtotal if
/// cancelling >= 24h before check-in, else 0.
int refundRupees(HomestayBooking b, DateTime now) {
  if (!now.isBefore(b.checkIn)) return 0; // at or after check-in
  return b.checkIn.difference(now).inHours >= 24 ? b.subtotal : 0;
}
```

- [ ] **Step 4: Add the additive fields** (`lib/data/models/homestay_booking.dart`)

- Field declaration: add `refundAmount`/`refundId` — change the int line and string line:
  ```dart
  final String id, guestId, hostId, homeName, hostName, petId, petName, note, status, paymentId, refundId;
  final DateTime checkIn, checkOut;
  final int ratePerNight, nights, subtotal, fee, total, createdAt, updatedAt, refundAmount;
  ```
- Constructor: add `this.refundAmount = 0, this.refundId = '',` after `this.paymentId = '',`.
- `toMap()`: add `'refundAmount': refundAmount,` and `'refundId': refundId,` after `'paymentId': paymentId,`.
- `fromMap`: add `refundAmount: (m['refundAmount'] ?? 0) as int,` and `refundId: (m['refundId'] ?? '') as String,` after the `paymentId:` line.

- [ ] **Step 5: Run the test + existing homestay model tests — expect PASS**

Run: `flutter test test/data/refund_policy_test.dart test/data/homestay_booking_test.dart test/data/homestay_pay_test.dart`

- [ ] **Step 6: `flutter analyze` clean + full suite green, then commit**

Run: `flutter analyze && flutter test`
```bash
git add lib/data/models/refund_policy.dart lib/data/models/homestay_booking.dart test/data/refund_policy_test.dart
git commit -m "feat: refund policy (24h/100% flexible) + HomestayBooking refundAmount/refundId"
```

---

### Task 2: `PaymentService.refundStay` seam + fake + impl

**Files:**
- Modify: `lib/data/services/payment_service.dart`
- Modify: `lib/data/services/razorpay_payment_service.dart`
- Modify: `test/support/fakes.dart` (`FakePaymentService`)
- Test: `test/data/refund_service_test.dart` (create)

**Interfaces:**
- Produces: `class RefundResult { final int refundAmount; final String refundId; const RefundResult({required this.refundAmount, required this.refundId}); }`; `PaymentService.refundStay({required String bookingId}) → Future<RefundResult>` (throws `PaymentException(failed, 'refund-failed')` when the gateway failed after the claim, `PaymentException(failed, 'cancel-failed')` otherwise); `FakePaymentService` gains `RefundResult? refundResult`, `PaymentException? refundError`, `List<String> refundedBookingIds`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/refund_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';

void main() {
  test('FakePaymentService.refundStay returns the configured result + records the id', () async {
    final fake = FakePaymentService(
        refundResult: const RefundResult(refundAmount: 2700, refundId: 'rfnd_1'));
    final r = await fake.refundStay(bookingId: 'hb1');
    expect(r.refundAmount, 2700);
    expect(r.refundId, 'rfnd_1');
    expect(fake.refundedBookingIds, ['hb1']);
  });

  test('default fake refund is a 0-refund cancel', () async {
    final r = await FakePaymentService().refundStay(bookingId: 'hb1');
    expect(r.refundAmount, 0);
    expect(r.refundId, '');
  });

  test('a configured refund error is thrown and still records the attempt', () async {
    final fake = FakePaymentService(
        refundError: const PaymentException(PaymentErrorType.failed, 'refund-failed'));
    await expectLater(fake.refundStay(bookingId: 'hb1'),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', 'refund-failed')));
    expect(fake.refundedBookingIds, ['hb1']);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (`refundStay`/`RefundResult` don't exist)

Run: `flutter test test/data/refund_service_test.dart`

- [ ] **Step 3: Extend the seam** (`lib/data/services/payment_service.dart`)

Add above `abstract interface class PaymentService`:
```dart
class RefundResult {
  final int refundAmount; // rupees actually refunded (0 for the <24h path)
  final String refundId;  // '' when refundAmount == 0
  const RefundResult({required this.refundAmount, required this.refundId});
}
```
Add to the `PaymentService` interface (after `payForBooking`):
```dart
  Future<RefundResult> refundStay({required String bookingId});
```

- [ ] **Step 4: Implement in `RazorpayPaymentService`**

Add (uses the existing `_functions` field):
```dart
  @override
  Future<RefundResult> refundStay({required String bookingId}) async {
    try {
      final res = await _functions
          .httpsCallable('refundBookingPayment')
          .call<Map<Object?, Object?>>({'bookingId': bookingId});
      final data = Map<String, dynamic>.from(res.data);
      return RefundResult(
          refundAmount: (data['refundAmount'] ?? 0) as int,
          refundId: (data['refundId'] ?? '') as String);
    } on FirebaseFunctionsException catch (e) {
      // 'refund-failed' means the booking was already cancelled but the Razorpay
      // refund didn't go through (post-claim) — never conflate with a pre-claim
      // failure, which leaves the booking unchanged.
      throw PaymentException(PaymentErrorType.failed,
          e.message == 'refund-failed' ? 'refund-failed' : 'cancel-failed');
    } catch (_) {
      throw const PaymentException(PaymentErrorType.failed, 'cancel-failed');
    }
  }
```

- [ ] **Step 5: Extend `FakePaymentService`** (`test/support/fakes.dart`)

Add fields + method:
```dart
  final RefundResult? refundResult;
  final PaymentException? refundError;
  final List<String> refundedBookingIds = [];
```
Add these to the constructor params: `this.refundResult, this.refundError,` (after `this.gate`). Then add the method:
```dart
  @override
  Future<RefundResult> refundStay({required String bookingId}) async {
    refundedBookingIds.add(bookingId);
    if (refundError != null) throw refundError!;
    return refundResult ?? const RefundResult(refundAmount: 0, refundId: '');
  }
```

- [ ] **Step 6: Run the test + full suite — expect PASS** (the seam grew a method; every `PaymentService` implementer — `RazorpayPaymentService` + `FakePaymentService` — now implements it, so the suite must still compile/pass)

Run: `flutter test test/data/refund_service_test.dart && flutter test`

- [ ] **Step 7: Enforce SDK isolation + analyze, then commit**

Grep `lib/` for `cloud_functions` → only `lib/data/services/razorpay_payment_service.dart`.
Run: `flutter analyze`
```bash
git add lib/data/services/payment_service.dart lib/data/services/razorpay_payment_service.dart test/support/fakes.dart test/data/refund_service_test.dart
git commit -m "feat: PaymentService.refundStay seam (RefundResult) + fake + Razorpay impl"
```

---

### Task 3: `refundBookingPayment` Cloud Function + emulator test

**Files:**
- Modify: `functions/src/index.ts`
- Modify: `integration_test/functions_test.dart`

**Interfaces:**
- Consumes: model fields (`guestId`, `status`, `checkIn`, `subtotal`, `paymentId`) — all existing on the `homestayBookings` doc.
- Produces: callable `refundBookingPayment({bookingId}) → {refundAmount, refundId}`, region `asia-south1`; errors `unauthenticated`/`invalid-argument`/`not-found`/`permission-denied`/`failed-precondition('not-paid'|'after-checkin'|'no-payment-id')`/`internal('refund-failed')`.

- [ ] **Step 1: Add `firebase-admin` init + the function** (`functions/src/index.ts`)

At the top, after the existing imports, add:
```ts
import * as admin from "firebase-admin";
admin.initializeApp();
```
Append the function (after `verifyBookingPayment`):
```ts
export const refundBookingPayment = onCall(
  {region: "asia-south1", secrets: [razorpayKeyId, razorpayKeySecret]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const bookingId = request.data?.bookingId;
    if (typeof bookingId !== "string" || bookingId === "") {
      throw new HttpsError("invalid-argument", "bad-args");
    }
    const uid = request.auth.uid;
    const ref = admin.firestore().collection("homestayBookings").doc(bookingId);

    // Transactionally claim paid -> cancelled: computes the authoritative refund
    // and locks the booking so a double-submit cannot double-refund. Pure (no
    // network); Razorpay is called only after this commits.
    const claim = await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError("not-found", "no-booking");
      const b = snap.data() as FirebaseFirestore.DocumentData;
      if (b.guestId !== uid) throw new HttpsError("permission-denied", "not-your-booking");
      if (b.status !== "paid") throw new HttpsError("failed-precondition", "not-paid");
      // checkIn is a date (YYYY-MM-DD); interpret at IST midnight (Mumbai market).
      const checkIn = new Date(`${b.checkIn}T00:00:00+05:30`);
      const now = new Date();
      if (now.getTime() >= checkIn.getTime()) {
        throw new HttpsError("failed-precondition", "after-checkin");
      }
      const hours = (checkIn.getTime() - now.getTime()) / 3600000;
      const refundAmount = hours >= 24 ? (b.subtotal as number) : 0;
      tx.update(ref, {status: "cancelled", updatedAt: Date.now(), refundAmount});
      return {refundAmount, paymentId: (b.paymentId as string) || ""};
    });

    let refundId = "";
    if (claim.refundAmount > 0) {
      if (!claim.paymentId) throw new HttpsError("failed-precondition", "no-payment-id");
      try {
        const rzp = new Razorpay({
          key_id: razorpayKeyId.value(),
          key_secret: razorpayKeySecret.value(),
        });
        const r = await rzp.payments.refund(claim.paymentId,
          {amount: claim.refundAmount * 100, speed: "normal"});
        refundId = r.id;
        await ref.update({refundId});
      } catch (e) {
        // The booking is already cancelled with refundAmount set; refundId stays
        // '' (a tracked reconciliation case). Signal distinctly so the client
        // shows an honest "cancelled but refund failed" message.
        logger.error("refundBookingPayment refund failed", e);
        throw new HttpsError("internal", "refund-failed");
      }
    }
    return {refundAmount: claim.refundAmount, refundId};
  });
```

- [ ] **Step 2: Build the functions** (this is the TS gate)

Run: `npm --prefix functions run build`
Expected: `tsc` exits 0, `functions/lib/index.js` updated.

- [ ] **Step 3: Extend the emulator test** (`integration_test/functions_test.dart`)

Add a new `testWidgets` (the emulator setup — `useFunctionsEmulator`/`useFirestoreEmulator`/`useAuthEmulator` — is already in `setUpAll`; if the file only wires auth+functions, add `FirebaseFirestore.instance.useFirestoreEmulator('10.0.2.2', 8080);` to `setUpAll`):
```dart
  testWidgets('refundBookingPayment: auth + precondition gates, then 0-refund cancel + idempotency',
      (tester) async {
    final fns = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final auth = FirebaseAuthRepository();
    final stays = FirestoreHomestayBookingRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // Unauthenticated -> rejected.
    await expectLater(fns.httpsCallable('refundBookingPayment').call({'bookingId': 'x'}),
        throwsA(isA<FirebaseFunctionsException>().having((e) => e.code, 'code', 'unauthenticated')));

    final guest = await auth.signUp(email: 'rf_$stamp@x.com', password: 'secret1');

    // Missing/unknown booking.
    await expectLater(fns.httpsCallable('refundBookingPayment').call({'bookingId': ''}),
        throwsA(isA<FirebaseFunctionsException>().having((e) => e.code, 'code', 'invalid-argument')));
    await expectLater(fns.httpsCallable('refundBookingPayment').call({'bookingId': 'nope_$stamp'}),
        throwsA(isA<FirebaseFunctionsException>().having((e) => e.code, 'code', 'not-found')));

    // A requested (unpaid) booking owned by the guest -> not-paid.
    await stays.createHomestayBooking(HomestayBooking(guestId: guest.uid, hostId: 'host_$stamp',
        homeName: 'H', hostName: 'M', petId: 'p', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime.now().add(const Duration(hours: 12)),
        checkOut: DateTime.now().add(const Duration(hours: 84)), nights: 3,
        subtotal: 2700, fee: 150, total: 2850));
    final reqId = (await stays.watchMyHomestayBookings(guest.uid).firstWhere((l) => l.isNotEmpty)).single.id;
    await expectLater(fns.httpsCallable('refundBookingPayment').call({'bookingId': reqId}),
        throwsA(isA<FirebaseFunctionsException>().having((e) => e.code, 'code', 'failed-precondition')));

    // Drive it to paid (checkIn ~12h away -> the 0-refund path): host accepts, guest pays.
    await auth.signOut();
    final host = await auth.signUp(email: 'rfh_$stamp@x.com', password: 'secret1');
    // Re-point the booking's host to this account so acceptRequest passes rules:
    // create a fresh booking whose hostId is this host, then run accept+pay.
    await auth.signOut();
    await auth.signIn(email: 'rf_$stamp@x.com', password: 'secret1');
    await stays.createHomestayBooking(HomestayBooking(guestId: guest.uid, hostId: host.uid,
        homeName: 'H2', hostName: 'M', petId: 'p', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime.now().add(const Duration(hours: 12)),
        checkOut: DateTime.now().add(const Duration(hours: 84)), nights: 3,
        subtotal: 2700, fee: 150, total: 2850));
    final payId = (await stays.watchMyHomestayBookings(guest.uid)
        .firstWhere((l) => l.any((s) => s.hostId == host.uid))).firstWhere((s) => s.hostId == host.uid).id;
    await auth.signOut();
    await auth.signIn(email: 'rfh_$stamp@x.com', password: 'secret1');
    await stays.acceptRequest(payId);
    await auth.signOut();
    await auth.signIn(email: 'rf_$stamp@x.com', password: 'secret1');
    await stays.markPaid(payId, 'pay_rf_$stamp');

    // Guest cancels < 24h out -> 0 refund, no Razorpay call, booking cancelled.
    final res = await fns.httpsCallable('refundBookingPayment').call<Map<Object?, Object?>>({'bookingId': payId});
    expect(res.data['refundAmount'], 0);
    expect(res.data['refundId'], '');
    final cancelled = await stays.watchMyHomestayBookings(guest.uid)
        .firstWhere((l) => l.any((s) => s.id == payId && s.status == 'cancelled'));
    expect(cancelled.firstWhere((s) => s.id == payId).refundAmount, 0);

    // Idempotent: a second call finds a non-paid booking.
    await expectLater(fns.httpsCallable('refundBookingPayment').call({'bookingId': payId}),
        throwsA(isA<FirebaseFunctionsException>().having((e) => e.code, 'code', 'failed-precondition')));

    await auth.signOut();
  });
```

- [ ] **Step 4: Run against the emulators** (functions + firestore + auth)

```bash
npm --prefix functions run build
firebase emulators:start --only auth,firestore,functions --project pet-aggregator-app
flutter test integration_test/functions_test.dart -d emulator-5554
```
Expected: all pass, including the new refund test. Stop the emulators after. **If no Android emulator / the instrumentation build won't run** after a genuine effort (this has hung on Gradle before), complete Steps 1–3, confirm `tsc` builds + `flutter analyze` clean + full unit `flutter test` green, commit, and report DONE_WITH_CONCERNS deferring the emulator run to Task 5 — same convention as prior slices.

- [ ] **Step 5: `flutter analyze` clean, then commit** (deploy is Task 5)

```bash
git add functions/src/index.ts integration_test/functions_test.dart
git commit -m "feat: refundBookingPayment Cloud Function (server-computed, transactional claim)"
```

---

### Task 4: `canCancelPaidStay` + My-bookings Cancel & refund UI

**Files:**
- Modify: `lib/data/models/booking_lifecycle.dart`
- Modify: `lib/features/bookings/my_bookings_screen.dart`
- Test: `test/data/booking_lifecycle_test.dart` (add a `canCancelPaidStay` group)
- Test: `test/features/homestay_refund_row_test.dart` (create)

**Interfaces:**
- Consumes: `refundRupees` (Task 1); `RefundResult`/`refundStay`/`PaymentException` + `FakePaymentService(refundResult/refundError)` (Task 2).
- Produces: `bool canCancelPaidStay(HomestayBooking b, DateTime now)`; the paid-cancel row affordance.

- [ ] **Step 1: Add the lifecycle test** (`test/data/booking_lifecycle_test.dart`, new group)

```dart
  group('canCancelPaidStay', () {
    final now = DateTime(2026, 7, 19, 12, 0);
    HomestayBooking paid(DateTime checkIn) => HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h',
        homeName: 'H', hostName: 'M', petId: 'x', petName: 'Bruno', ratePerNight: 900,
        checkIn: checkIn, checkOut: checkIn.add(const Duration(days: 3)), nights: 3,
        subtotal: 2700, fee: 150, total: 2850, status: 'paid');
    test('paid + before check-in is cancellable (any distance before check-in)', () {
      expect(canCancelPaidStay(paid(now.add(const Duration(days: 5))), now), isTrue);
      expect(canCancelPaidStay(paid(now.add(const Duration(hours: 2))), now), isTrue); // still cancellable (0 refund)
    });
    test('paid at/after check-in is not cancellable in-app', () {
      expect(canCancelPaidStay(paid(now), now), isFalse);
      expect(canCancelPaidStay(paid(now.subtract(const Duration(days: 1))), now), isFalse);
    });
    test('non-paid stays are not covered by canCancelPaidStay', () {
      final accepted = HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h', homeName: 'H',
          hostName: 'M', petId: 'x', petName: 'B', ratePerNight: 900,
          checkIn: now.add(const Duration(days: 5)), checkOut: now.add(const Duration(days: 8)),
          nights: 3, subtotal: 2700, fee: 150, total: 2850, status: 'accepted');
      expect(canCancelPaidStay(accepted, now), isFalse);
    });
  });
```

- [ ] **Step 2: Run it — expect FAIL** (`canCancelPaidStay` doesn't exist)

Run: `flutter test test/data/booking_lifecycle_test.dart`

- [ ] **Step 3: Add `canCancelPaidStay`** (`lib/data/models/booking_lifecycle.dart`, after `canPay`)

```dart
bool canCancelPaidStay(HomestayBooking b, DateTime now) =>
    b.status == 'paid' && now.isBefore(b.checkIn);
```

- [ ] **Step 4: Run the lifecycle test — expect PASS**

Run: `flutter test test/data/booking_lifecycle_test.dart`

- [ ] **Step 5: Write the failing row/flow test**

```dart
// test/features/homestay_refund_row_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

HomestayBooking _stay(String uid, {required String status, required int checkInHours,
        int refundAmount = 0}) =>
    HomestayBooking(id: 'hb1', guestId: uid, hostId: 'host1', homeName: "Meera's Home",
        hostName: 'Meera', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime.now().add(Duration(hours: checkInHours)),
        checkOut: DateTime.now().add(Duration(hours: checkInHours + 72)),
        nights: 3, subtotal: 2700, fee: 150, total: 2850, status: status,
        paymentId: 'pay_x', refundAmount: refundAmount);

// Note: FakePaymentService.refundStay only records the call + returns the result
// (it models the CLIENT calling the function); the actual paid->cancelled write is
// server-side, so these widget tests assert the client behavior (refundStay called,
// snackbar, dialog copy), not a repo status flip — that's covered by the Function
// emulator test + the on-device pass.
Future<(InMemoryHomestayBookingRepository, FakePaymentService)> _pump(WidgetTester tester,
    HomestayBooking stay, {FakePaymentService? payments}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final repo = InMemoryHomestayBookingRepository();
  await repo.createHomestayBooking(stay);
  final p = payments ?? FakePaymentService();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    homestayBookingRepositoryProvider.overrideWithValue(repo),
    bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    paymentServiceProvider.overrideWithValue(p),
  ], initialLocation: Routes.bookings);
  await tester.pumpAndSettle();
  return (repo, p);
}

void main() {
  testWidgets('paid + >=24h shows Cancel; dialog shows the full-refund estimate', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'paid', checkInHours: 120)); // 5 days out
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('₹2700 of ₹2850'), findsOneWidget);
    expect(find.text('Cancel & refund'), findsOneWidget);
  });

  testWidgets('paid + <24h dialog shows the non-refundable copy', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'paid', checkInHours: 6)); // 6h out
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining("within 24 hours of check-in aren't refundable"), findsOneWidget);
    expect(find.text('Cancel anyway'), findsOneWidget);
  });

  testWidgets('confirming Cancel & refund calls refundStay for the booking', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final payments = FakePaymentService(
        refundResult: const RefundResult(refundAmount: 2700, refundId: 'rfnd_1'));
    final (_, p) = await _pump(tester, _stay(uid, status: 'paid', checkInHours: 120), payments: payments);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel & refund'));
    await tester.pumpAndSettle();
    expect(p.refundedBookingIds, ['hb1']);
    expect(find.textContaining('₹2700 will be refunded'), findsOneWidget);
  });

  testWidgets('mid-stay paid (after check-in) shows Contact host, no Cancel', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'paid', checkInHours: -12)); // checked in 12h ago
    expect(find.text('Contact host to cancel'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('a cancelled stay with a refund shows the refunded amount', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'cancelled', checkInHours: 120, refundAmount: 900));
    expect(find.textContaining('₹900 refunded'), findsOneWidget);
  });
}
```

- [ ] **Step 6: Run it — expect FAIL** (no paid-cancel affordance / refunded suffix)

Run: `flutter test test/features/homestay_refund_row_test.dart`

- [ ] **Step 7: Wire the stays loop + `_MyBookingRow`** (`lib/features/bookings/my_bookings_screen.dart`)

Add imports if missing: `import '../../data/models/refund_policy.dart';` and `import '../../data/services/payment_service.dart';`.

In the `for (final s in stays)` loop's `_MyBookingRow`, change `detail`, `showContactHost`, and add the paid-cancel params:
```dart
            _MyBookingRow(
              emoji: '🏡',
              name: s.homeName,
              detail: '${s.hostName} · ${HomestayBooking.fmtDay(s.checkIn)} · ${s.nights} nights'
                  '${s.refundAmount > 0 ? ' · ₹${s.refundAmount} refunded' : ''}',
              phase: stayPhase(s, now),
              rated: rated.contains(s.id),
              canCancel: canCancelStay(s, now),
              canPay: canPay(s, now),
              canCancelPaid: canCancelPaidStay(s, now),
              showContactHost: stayPhase(s, now) == BookingPhase.upcoming && !canCancelPaidStay(s, now),
              onPay: () => context.push(Routes.homestayPayment, extra: s),
              onCancelPaid: () => _confirmCancelPaid(context, ref, s, now),
              onCancel: () => confirmAndRun(context,
                  title: 'Cancel this booking?',
                  message: "This can't be undone.",
                  confirmLabel: 'Cancel booking',
                  action: () => ref.read(homestayBookingRepositoryProvider).cancelStay(s.id)),
              onRate: () => context.push(Routes.rate,
                  extra: ReviewTarget(
                      type: ReviewTargetType.homestay, id: s.hostId, name: s.homeName,
                      subtitle: '${s.hostName} · ${s.nights} nights', bookingId: s.id)),
            ),
```
Add the top-level handler (put it near `confirmAndRun` usage, e.g. a top-level function in the file, so it's reusable):
```dart
Future<void> _confirmCancelPaid(
    BuildContext context, WidgetRef ref, HomestayBooking s, DateTime now) async {
  final c = context.pg;
  final refund = refundRupees(s, now);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: c.surface,
      title: Text('Cancel this stay?', style: PgText.poppins(16, FontWeight.w700, color: c.text)),
      content: Text(
          refund > 0
              ? "You'll be refunded ₹$refund of ₹${s.total}. Refunds take 5–7 business days. "
                  "The ₹150 service fee isn't refundable."
              : "Cancellations within 24 hours of check-in aren't refundable — you'll be refunded ₹0.",
          style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text('Keep', style: PgText.inter(13.5, FontWeight.w600, color: c.muted))),
        TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(refund > 0 ? 'Cancel & refund' : 'Cancel anyway',
                style: PgText.inter(13.5, FontWeight.w700, color: c.brand))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await ref.read(paymentServiceProvider).refundStay(bookingId: s.id);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text(result.refundAmount > 0
            ? 'Stay cancelled. ₹${result.refundAmount} will be refunded in 5–7 days.'
            : 'Stay cancelled.')));
  } on PaymentException catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text(e.message == 'refund-failed'
            ? "Stay cancelled, but the refund didn't go through — contact support."
            : "Couldn't cancel the stay — try again.")));
  }
}
```
(The two failure strings use double quotes because they contain apostrophes — keep them exactly as shown.) Extend `_MyBookingRow`: add `final bool canCancelPaid; final VoidCallback? onCancelPaid;` (defaults `false`/`null`) to the fields + constructor, and in the action column add — after the `if (canCancel)` block, before `if (showContactHost)`:
```dart
          if (canCancelPaid) ...[
            const SizedBox(height: 6),
            GestureDetector(
                onTap: onCancelPaid,
                child: Text('Cancel', style: PgText.inter(12.5, FontWeight.w600, color: c.muted))),
          ],
```
For the **services** loop's `_MyBookingRow`, add `canCancelPaid: false, onCancelPaid: null,` (services have no paid-stay refund).

- [ ] **Step 8: Run the row test + bookings tests + full suite — expect PASS**

Run: `flutter test test/features/homestay_refund_row_test.dart test/features/homestay_pay_row_test.dart test/features/my_bookings_screen_test.dart test/features/bookings_hub_test.dart && flutter test`

- [ ] **Step 9: `flutter analyze` clean, then commit**

```bash
git add lib/data/models/booking_lifecycle.dart lib/features/bookings/my_bookings_screen.dart test/data/booking_lifecycle_test.dart test/features/homestay_refund_row_test.dart
git commit -m "feat: Cancel & refund a paid stay before check-in (policy-aware dialog)"
```

---

### Task 5: Final verification + functions deploy + on-device refund pass

**Files:** none (fixes only if verification finds problems).

- [ ] **Step 1: Full local verification**

```bash
flutter analyze              # No issues found!
flutter test                 # all pass
flutter build apk --debug    # succeeds
npm --prefix functions run build   # tsc exits 0
```

- [ ] **Step 2: Emulator functions test** (mandatory here if Task 3's run was deferred)

```bash
npm --prefix functions run build
firebase emulators:start --only auth,firestore,functions --project pet-aggregator-app
flutter test integration_test/functions_test.dart -d emulator-5554
```
Kill the emulators after; confirm ports 9099/8080/5001 freed.

- [ ] **Step 3: Deploy the function** (owner-run if the classifier blocks the assistant; needs the Slice-11 Razorpay secrets already set)

```bash
firebase deploy --only functions --project pet-aggregator-app
```
Expected: `✔ Deploy complete!` including `refundBookingPayment` in `asia-south1`.

- [ ] **Step 4: On-device refund pass** (`flutter run -d emulator-5554`, after Step 3 + a paid stay exists)

1. Pay a stay whose check-in is **>24h away**, then tap **Cancel** on it → dialog shows `₹2700 of ₹2850` → **Cancel & refund** → snackbar "₹2700 will be refunded…"; the row reads **Cancelled · ₹2700 refunded**; the **Razorpay test dashboard shows the refund**; Firestore doc `status:'cancelled'`, `refundAmount:2700`, `refundId` set.
2. Pay another stay **<24h** away → Cancel → "Cancel anyway" → snackbar "Stay cancelled." (no refund on the dashboard); `refundAmount:0`.
3. A mid-stay paid stay shows "Contact host to cancel" (no Cancel).

- [ ] **Step 5: Commit any verification fixes** (none expected).

---

## Self-review notes (checked against the spec)

- Spec coverage: policy fn + model fields (T1), seam+fake+impl (T2), the server-computed refund Function + emulator test (T3), lifecycle permission + Cancel-with-refund UI incl. both refund/no-refund copy, refund-failed vs cancel-failed messaging, and the refunded-row suffix (T4), verify/deploy/on-device (T5). No `firestore.rules` change — as the spec mandates (server-owned write).
- Type consistency: `refundRupees(HomestayBooking, DateTime)`, `HomestayBooking.refundAmount`/`refundId`, `RefundResult{refundAmount, refundId}`, `PaymentService.refundStay({bookingId})`, `canCancelPaidStay(stay, now)`, `refundBookingPayment({bookingId})`, `_MyBookingRow(… canCancelPaid, onCancelPaid)` — identical across tasks and tests.
- The refund-failed vs cancel-failed distinction (post-claim vs pre-claim) is threaded: Function throws `internal('refund-failed')`, `RazorpayPaymentService` maps it, the screen keys the snackbar on `e.message`.
- Timezone: server interprets `checkIn` at IST midnight to match the client's device-local parse (single-market app) — documented in both the policy fn comment and the Function.
- Idempotency: the transactional claim (paid→cancelled inside `runTransaction`) makes a double-submit's second call a `failed-precondition`; covered by the emulator test.
