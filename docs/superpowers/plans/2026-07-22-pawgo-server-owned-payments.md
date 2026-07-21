# Pawgo Slice 15: Server-owned payments — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the two payment Cloud Functions the sole authority on what a booking costs and whether it is paid — for both pillars — so a client can neither set a price nor declare a booking paid, and a payment made for one booking can never confirm another.

**Architecture:** One unified contract: *you always pay for a booking that already exists*. Services therefore pre-creates a `pending` (unpaid) booking, mirroring Homestay's `accepted`. `createBookingOrder({kind, bookingId})` recomputes the price from the **listing** and stamps the Razorpay order with `notes:{bookingId,kind,uid}`; `verifyBookingPayment` verifies the signature, asserts those notes, and writes the paid state itself with admin. Rules lose the client's paid-write. The client's post-payment write — and its whole "Retry saving" failure class — is deleted.

**Tech Stack:** Firebase Functions v2 (TypeScript) + `firebase-admin` + `razorpay` (all present); Flutter/Dart ^3.12.2, `flutter_riverpod` 3.x, `go_router`, `cloud_firestore`.

**Spec:** `docs/superpowers/specs/2026-07-22-pawgo-server-owned-payments-design.md`.

## Global Constraints

- Keep `android/gradle.properties` → `kotlin.incremental=false`.
- No new packages, no new secrets.
- **The client never sends an amount.** `createBookingOrder` and `verifyBookingPayment` take `{kind, bookingId, …}` only; `kind` is the string `'service'` or `'homestay'`.
- **Price authority is the listing**: service `rate = pros/{proId}.rate`, `fee = Math.round(rate * 0.1)`, `total = rate + fee`. Homestay `subtotal = homestays/{hostId}.ratePerNight * nights`, `fee = 150`, `total = subtotal + fee`. `nights` comes from the booking's stored `checkIn`/`checkOut` (date-only strings; **IST midnight** — the existing cross-boundary contract, do not change the format).
- **Order binding**: `createBookingOrder` stamps `notes: {bookingId, kind, uid}`; `verifyBookingPayment` fetches the order and asserts all three match, else `permission-denied('order-booking-mismatch')`.
- **Only `verifyBookingPayment` writes paid state**, transactionally, re-asserting the payable state inside the transaction: service → `status:'confirmed'`, homestay → `status:'paid'`, plus `paymentId`, `updatedAt`, and the server-computed amounts.
- Payable states: service `pending`, homestay `accepted`. Error codes: `unauthenticated` / `invalid-argument` / `not-found` / `permission-denied('not-your-booking'|'signature-mismatch'|'order-booking-mismatch')` / `failed-precondition('not-payable'|'no-listing'|'bad-amount'|'amount-mismatch')` / `internal('order-failed'|'order-fetch-failed')`.
- Rules: `bookings` create must be `status:'pending'`; `bookings` update allows only `pending|confirmed → cancelled` by the parent; the homestay `accepted → paid` client arm is **deleted**.
- SDK isolation unchanged: `razorpay_flutter`/`cloud_functions` only in `lib/data/services/razorpay_payment_service.dart`.
- `updatedAt`/`createdAt` are client-millis ints (`Date.now()` server-side) — the existing convention.
- Riverpod 3.x `.value`; async handlers guard `context.mounted`; widget tests use `pumpPgApp` + fakes.
- Every task ends green: `flutter analyze` clean + `flutter test` green (+ `npm --prefix functions run build` for TS tasks), then commit. Do NOT push. Do NOT deploy.

---

### Task 1: Lifecycle — service `pending` phase + `canPayService`

**Files:**
- Modify: `lib/data/models/booking_lifecycle.dart`
- Modify: `test/data/booking_lifecycle_test.dart`

**Interfaces:**
- Produces: `servicePhase` handling `pending` → `awaitingPayment`/`expired`; `bool canPayService(Booking b, DateTime now)`; `canCancelService` extended to `pending`.

- [ ] **Step 1: Write the failing tests** — append this group to `test/data/booking_lifecycle_test.dart` (the file already has `_svc({status, date})` and `_now = DateTime(2026, 7, 19, 14, 30)`):

```dart
  group('service pending (unpaid)', () {
    test('pending before the date is awaitingPayment', () =>
        expect(servicePhase(_svc(status: 'pending', date: '2026-07-21'), _now),
            BookingPhase.awaitingPayment));
    test('pending on the date is awaitingPayment', () =>
        expect(servicePhase(_svc(status: 'pending', date: '2026-07-19'), _now),
            BookingPhase.awaitingPayment));
    test('pending past the date is expired (never paid)', () =>
        expect(servicePhase(_svc(status: 'pending', date: '2026-07-18'), _now),
            BookingPhase.expired));
    test('confirmed is unchanged (upcoming / completed)', () {
      expect(servicePhase(_svc(date: '2026-07-21'), _now), BookingPhase.upcoming);
      expect(servicePhase(_svc(date: '2026-07-18'), _now), BookingPhase.completed);
    });
    test('canPayService only for pending, not past the date', () {
      expect(canPayService(_svc(status: 'pending', date: '2026-07-21'), _now), isTrue);
      expect(canPayService(_svc(status: 'pending', date: '2026-07-19'), _now), isTrue);
      expect(canPayService(_svc(status: 'pending', date: '2026-07-18'), _now), isFalse);
      expect(canPayService(_svc(date: '2026-07-21'), _now), isFalse);          // confirmed
      expect(canPayService(_svc(status: 'pending'), _now), isFalse);           // legacy, no date
    });
    test('canCancelService covers pending and confirmed before the date', () {
      expect(canCancelService(_svc(status: 'pending', date: '2026-07-21'), _now), isTrue);
      expect(canCancelService(_svc(date: '2026-07-21'), _now), isTrue);
      expect(canCancelService(_svc(status: 'pending', date: '2026-07-18'), _now), isFalse);
    });
  });
```

- [ ] **Step 2: Run it — expect FAIL** (`canPayService` undefined; `pending` falls through to upcoming/completed)

Run: `flutter test test/data/booking_lifecycle_test.dart`

- [ ] **Step 3: Implement** (`lib/data/models/booking_lifecycle.dart`)

Replace `servicePhase` with:
```dart
BookingPhase servicePhase(Booking b, DateTime now) {
  if (b.status == 'cancelled') return BookingPhase.cancelled;
  final d = DateTime.tryParse(b.date);
  if (d == null) return BookingPhase.completed; // legacy: no machine date, grandfathered
  if (b.status == 'pending') {
    // Unpaid: awaiting the guest's payment until the date passes, then expired.
    return _day(d).isBefore(_day(now)) ? BookingPhase.expired : BookingPhase.awaitingPayment;
  }
  return _day(d).isBefore(_day(now)) ? BookingPhase.completed : BookingPhase.upcoming;
}
```
Replace `canCancelService` with (adds `pending`):
```dart
bool canCancelService(Booking b, DateTime now) {
  final d = DateTime.tryParse(b.date);
  return (b.status == 'confirmed' || b.status == 'pending') &&
      d != null &&
      _day(now).isBefore(_day(d));
}
```
Add after it:
```dart
bool canPayService(Booking b, DateTime now) {
  final d = DateTime.tryParse(b.date);
  return b.status == 'pending' && d != null && !_day(d).isBefore(_day(now));
}
```
(`stayPhase`, `canPay`, `canCancelStay`, `canCancelPaidStay`, `canDecide`, `canRate` unchanged.)

- [ ] **Step 4: Run the lifecycle test — expect PASS**

Run: `flutter test test/data/booking_lifecycle_test.dart`

- [ ] **Step 5: `flutter analyze` clean + full suite green, then commit**

Run: `flutter analyze && flutter test`
```bash
git add lib/data/models/booking_lifecycle.dart test/data/booking_lifecycle_test.dart
git commit -m "feat: service pending phase (awaitingPayment/expired) + canPayService"
```

---

### Task 2: Cloud Functions — unified `{kind, bookingId}` contract

**Files:**
- Modify: `functions/src/index.ts` (rewrite both callables)

**Interfaces:**
- Produces: `createBookingOrder({kind, bookingId}) → {orderId, amountPaise, keyId}`; `verifyBookingPayment({kind, bookingId, orderId, paymentId, signature}) → {confirmed: true, paymentId}`. Error codes per Global Constraints. (`refundBookingPayment` is untouched.)

- [ ] **Step 1: Add the shared helper + rewrite `createBookingOrder`**

Add above the callables (after the secret definitions):
```ts
type Kind = "service" | "homestay";

/** Reads the booking, asserts ownership + payable state, and recomputes the
 *  authoritative price from the LISTING (never from client-written fields). */
async function loadPayable(kind: Kind, bookingId: string, uid: string) {
  const db = admin.firestore();
  const col = kind === "service" ? "bookings" : "homestayBookings";
  const ref = db.collection(col).doc(bookingId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "no-booking");
  const b = snap.data() as FirebaseFirestore.DocumentData;

  const ownerField = kind === "service" ? "parentId" : "guestId";
  if (b[ownerField] !== uid) throw new HttpsError("permission-denied", "not-your-booking");
  const payableStatus = kind === "service" ? "pending" : "accepted";
  if (b.status !== payableStatus) throw new HttpsError("failed-precondition", "not-payable");

  let amounts: {total: number; parts: Record<string, number>};
  if (kind === "service") {
    const pro = await db.collection("pros").doc(String(b.proId)).get();
    if (!pro.exists) throw new HttpsError("failed-precondition", "no-listing");
    const rate = Number(pro.data()?.rate);
    if (!Number.isFinite(rate) || rate <= 0) throw new HttpsError("failed-precondition", "bad-amount");
    const fee = Math.round(rate * 0.1);
    amounts = {total: rate + fee, parts: {rate, fee, total: rate + fee}};
  } else {
    const home = await db.collection("homestays").doc(String(b.hostId)).get();
    if (!home.exists) throw new HttpsError("failed-precondition", "no-listing");
    const ratePerNight = Number(home.data()?.ratePerNight);
    // checkIn/checkOut are date-only YYYY-MM-DD at IST midnight (existing contract).
    const ci = new Date(`${String(b.checkIn).slice(0, 10)}T00:00:00+05:30`);
    const co = new Date(`${String(b.checkOut).slice(0, 10)}T00:00:00+05:30`);
    if (!Number.isFinite(ci.getTime()) || !Number.isFinite(co.getTime())) {
      throw new HttpsError("failed-precondition", "bad-amount");
    }
    const nights = Math.round((co.getTime() - ci.getTime()) / 86400000);
    if (!Number.isFinite(ratePerNight) || ratePerNight <= 0 || nights <= 0) {
      throw new HttpsError("failed-precondition", "bad-amount");
    }
    const subtotal = ratePerNight * nights;
    const fee = 150;
    amounts = {total: subtotal + fee, parts: {subtotal, fee, nights, total: subtotal + fee}};
  }
  if (amounts.total <= 0) throw new HttpsError("failed-precondition", "bad-amount");
  // Never surprise-charge: the stored total must match what the server computes.
  if (Number(b.total) !== amounts.total) {
    throw new HttpsError("failed-precondition", "amount-mismatch");
  }
  return {ref, booking: b, amounts};
}

function readArgs(data: unknown) {
  const d = (data ?? {}) as Record<string, unknown>;
  const kind = d.kind;
  const bookingId = d.bookingId;
  if ((kind !== "service" && kind !== "homestay") ||
      typeof bookingId !== "string" || bookingId === "") {
    throw new HttpsError("invalid-argument", "bad-args");
  }
  return {kind: kind as Kind, bookingId};
}
```
Replace `createBookingOrder`'s body with:
```ts
export const createBookingOrder = onCall(
  {region: "asia-south1", secrets: [razorpayKeyId, razorpayKeySecret]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const {kind, bookingId} = readArgs(request.data);
    const uid = request.auth.uid;
    const {amounts} = await loadPayable(kind, bookingId, uid);
    const rzp = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });
    try {
      const order = await rzp.orders.create({
        amount: amounts.total * 100, // paise — server-computed, never client-supplied
        currency: "INR",
        receipt: `bk_${uid}_${Date.now()}`.slice(0, 40),
        notes: {bookingId, kind, uid}, // binds this order to this booking
      });
      return {orderId: order.id, amountPaise: order.amount, keyId: razorpayKeyId.value()};
    } catch (e) {
      logger.error("createBookingOrder failed", e);
      throw new HttpsError("internal", "order-failed");
    }
  });
```

- [ ] **Step 2: Rewrite `verifyBookingPayment` to bind + write**

```ts
export const verifyBookingPayment = onCall(
  {region: "asia-south1", secrets: [razorpayKeyId, razorpayKeySecret]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const {kind, bookingId} = readArgs(request.data);
    const d = request.data as Record<string, unknown>;
    const {orderId, paymentId, signature} = d;
    if (typeof orderId !== "string" || orderId === "" ||
        typeof paymentId !== "string" || paymentId === "" ||
        typeof signature !== "string" || signature === "") {
      throw new HttpsError("invalid-argument", "bad-args");
    }
    const uid = request.auth.uid;

    // 1. The signature proves Razorpay issued this payment for this order.
    const expected = crypto.createHmac("sha256", razorpayKeySecret.value())
      .update(`${orderId}|${paymentId}`)
      .digest("hex");
    const a = Buffer.from(expected);
    const b = Buffer.from(signature);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      throw new HttpsError("permission-denied", "signature-mismatch");
    }

    // 2. The order's notes prove it was created for THIS booking and caller —
    //    without this a payment for booking A could confirm booking B.
    let order;
    try {
      const rzp = new Razorpay({
        key_id: razorpayKeyId.value(),
        key_secret: razorpayKeySecret.value(),
      });
      order = await rzp.orders.fetch(orderId);
    } catch (e) {
      logger.error("verifyBookingPayment order fetch failed", e);
      throw new HttpsError("internal", "order-fetch-failed");
    }
    const notes = (order?.notes ?? {}) as Record<string, unknown>;
    if (notes.bookingId !== bookingId || notes.kind !== kind || notes.uid !== uid) {
      throw new HttpsError("permission-denied", "order-booking-mismatch");
    }

    // 3. Re-validate (state may have changed since the order) and write.
    const {ref, amounts} = await loadPayable(kind, bookingId, uid);
    const payableStatus = kind === "service" ? "pending" : "accepted";
    const paidStatus = kind === "service" ? "confirmed" : "paid";
    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError("not-found", "no-booking");
      if (snap.data()?.status !== payableStatus) {
        throw new HttpsError("failed-precondition", "not-payable");
      }
      tx.update(ref, {
        ...amounts.parts, // server-authoritative amounts
        status: paidStatus,
        paymentId,
        updatedAt: Date.now(),
      });
    });
    return {confirmed: true, paymentId};
  });
```

- [ ] **Step 3: Build — this is the gate**

Run: `npm --prefix functions run build`
Expected: `tsc` exits 0.

- [ ] **Step 4: Flutter side untouched so far**

Run: `flutter analyze`
Expected: clean (no Dart changed in this task).

- [ ] **Step 5: Commit**

```bash
git add functions/src/index.ts
git commit -m "feat: payment Functions own price + paid-write, bound by order notes"
```

---

### Task 3: Firestore rules — remove the client's paid-write

**Files:**
- Modify: `firestore.rules`
- Modify: `integration_test/firebase_repos_test.dart` (migrate the Slice-13 matrix rows)

**Interfaces:**
- Consumes: nothing. Produces: rules where a client can only create `pending` service bookings and can never write `confirmed`/`paid`.

- [ ] **Step 1: Update `match /bookings/{id}`** — replace its `create` and `update`:

```
      allow create: if request.auth != null
                  && request.resource.data.parentId == request.auth.uid
                  && request.resource.data.status == 'pending';
      allow update: if request.auth != null
                    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt'])
                    && resource.data.parentId == request.auth.uid
                    && resource.data.status in ['pending', 'confirmed']
                    && request.resource.data.status == 'cancelled';
```
(`read` and `allow delete: if false;` unchanged.)

- [ ] **Step 2: Delete the homestay `accepted → paid` client arm** — in `match /homestayBookings/{id}`, the `allow update` becomes only the accept/decline + cancel branch (drop the whole second disjunct that allowed `status == 'paid'` with `paymentId`):

```
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
```
(`create`, `read`, `delete` unchanged.)

- [ ] **Step 3: Migrate the matrix test** (`integration_test/firebase_repos_test.dart`, the `'booking lifecycle transitions obey the rules matrix (real Firestore emulators)'` test)

The homestay section currently drives `accepted → paid` via `stays.markPaid(...)` and asserts it succeeds. That arm is now **denied** — flip it. Replace the block that runs from the `// Guest pays the accepted stay` comment through the `expect(paid.updatedAt, greaterThan(0));` line with:
```dart
    // The guest can no longer write paid — that transition is server-only now
    // (verifyBookingPayment writes it with admin after binding the order).
    await auth.signOut();
    await auth.signIn(email: 'lg_$stamp@x.com', password: 'secret1');
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update(
            {'status': 'paid', 'updatedAt': 5, 'paymentId': 'pay_client'}),
        throwsA(isA<FirebaseException>()));
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update({'status': 'paid', 'updatedAt': 5}),
        throwsA(isA<FirebaseException>()));
```
Then the following `// A paid stay can no longer be cancelled` assertion no longer applies (the stay is still `accepted`, and an accepted stay IS cancellable) — **delete that block**. Keep the separate-stay guest-cancel coverage that follows. In the service-booking section, any booking created directly with `status: 'confirmed'` must become `'pending'`, and add:
```dart
    // A client can no longer mint a confirmed (paid) service booking.
    await expectLater(
        db.collection('bookings').add({'parentId': guest.uid, 'proId': host.uid, 'status': 'confirmed'}),
        throwsA(isA<FirebaseException>()));
```

- [ ] **Step 4: `flutter analyze` clean + full unit suite green** (the integration file isn't in the unit suite; analyze proves it compiles)

Run: `flutter analyze && flutter test`
**Emulator note:** the rules matrix run needs the auth+firestore emulators and an Android device; the instrumentation build has hung in this environment before. If it won't run after a genuine effort, commit and report DONE_WITH_CONCERNS deferring the emulator run to Task 7 — same convention as prior slices.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules integration_test/firebase_repos_test.dart
git commit -m "feat: rules - client creates only pending bookings, never writes paid"
```

---

### Task 4: Client seam — `payForBooking({bookingId, kind})`, drop `markPaid`

**Files:**
- Modify: `lib/data/services/payment_service.dart`
- Modify: `lib/data/services/razorpay_payment_service.dart`
- Modify: `lib/data/repositories/homestay_booking_repository.dart`
- Modify: `lib/data/repositories/firebase/firestore_homestay_booking_repository.dart`
- Modify: `lib/data/repositories/firebase/firestore_booking_repository.dart`
- Modify: `test/support/fakes.dart`
- Modify: `test/data/homestay_pay_test.dart`
- Test: `test/data/payment_kind_test.dart` (create)

**Interfaces:**
- Produces: `enum PaymentKind { service, homestay }`; `PaymentService.payForBooking({required String bookingId, required PaymentKind kind, required String description, void Function()? onVerifying})` (no `amountRupees`); `FakePaymentService` records `paidBookingIds` (`List<String>`) and `paidKinds` (`List<PaymentKind>`). `HomestayBookingRepository.markPaid` **removed**. `BookingRepository.createBooking` writes `status:'pending'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/payment_kind_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';

void main() {
  test('payForBooking takes a bookingId + kind and records both', () async {
    final fake = FakePaymentService.success();
    final r = await fake.payForBooking(
        bookingId: 'bk1', kind: PaymentKind.service, description: 'Dog Walker');
    expect(r.paymentId, 'pay_fake123');
    expect(fake.paidBookingIds, ['bk1']);
    expect(fake.paidKinds, [PaymentKind.service]);
  });

  test('homestay kind is recorded too', () async {
    final fake = FakePaymentService.success();
    await fake.payForBooking(
        bookingId: 'hb1', kind: PaymentKind.homestay, description: 'Meera\'s Home');
    expect(fake.paidBookingIds, ['hb1']);
    expect(fake.paidKinds, [PaymentKind.homestay]);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (signature/fields don't exist)

Run: `flutter test test/data/payment_kind_test.dart`

- [ ] **Step 3: Change the seam** (`lib/data/services/payment_service.dart`)

Add above `PaymentService`:
```dart
enum PaymentKind { service, homestay }
```
Replace the `payForBooking` declaration with:
```dart
  /// Pays for an EXISTING booking. The server prices it and writes the paid
  /// state — the client never supplies an amount.
  Future<PaymentResult> payForBooking({
    required String bookingId,
    required PaymentKind kind,
    required String description,
    void Function()? onVerifying,
  });
```
(`PaymentResult`, `RefundResult`, `PaymentException`, `PaymentErrorType`, `refundStay` unchanged.)

- [ ] **Step 4: Update `RazorpayPaymentService`**

Change the signature to match, and pass the new args to both callables:
```dart
  @override
  Future<PaymentResult> payForBooking({
    required String bookingId,
    required PaymentKind kind,
    required String description,
    void Function()? onVerifying,
  }) async {
```
Replace the `createBookingOrder` call payload with:
```dart
          .call<Map<Object?, Object?>>({'kind': kind.name, 'bookingId': bookingId});
```
Store the ids for the verify step — add fields next to `_onVerifying`:
```dart
  String? _bookingId;
  PaymentKind? _kind;
```
Set them where `_onVerifying` is set (`_bookingId = bookingId; _kind = kind;`) and clear them in `_finish`/`_finishError` alongside `_onVerifying = null;`. Then in `_verify`, send them:
```dart
      await _functions.httpsCallable('verifyBookingPayment').call<Map<Object?, Object?>>({
        'kind': _kind?.name,
        'bookingId': _bookingId,
        'orderId': r.orderId,
        'paymentId': r.paymentId,
        'signature': r.signature,
      });
```
(The rest of the checkout/event bridging, `busy` guard and error mapping are unchanged.)

- [ ] **Step 5: Update the fake** (`test/support/fakes.dart`, `FakePaymentService`)

Add fields `final List<String> paidBookingIds = []; final List<PaymentKind> paidKinds = [];` and replace `payForBooking` with:
```dart
  @override
  Future<PaymentResult> payForBooking({
    required String bookingId,
    required PaymentKind kind,
    required String description,
    void Function()? onVerifying,
  }) async {
    paidBookingIds.add(bookingId);
    paidKinds.add(kind);
    if (gate != null) return gate!.future;
    if (error != null) throw error!;
    onVerifying?.call();
    return result ??
        (throw const PaymentException(PaymentErrorType.failed, 'not-configured'));
  }
```
Delete the `chargedAmounts` field and its uses (there is no client amount any more); delete `InMemoryHomestayBookingRepository.markPaid`.

- [ ] **Step 6: Remove `markPaid` + make `createBooking` write pending**

- `lib/data/repositories/homestay_booking_repository.dart`: delete the `markPaid` line from the interface.
- `lib/data/repositories/firebase/firestore_homestay_booking_repository.dart`: delete the `markPaid` override.
- **`createBooking` forces `pending` AND returns the created booking** (Task 5's BookingScreen needs the new id — doing both here keeps the method edited once).
  - `lib/data/repositories/booking_repository.dart`: change the signature to `Future<Booking> createBooking(Booking booking);`
  - `lib/data/repositories/firebase/firestore_booking_repository.dart`:
```dart
  @override
  Future<Booking> createBooking(Booking booking) async {
    final map = booking.toMap();
    if ((map['createdAt'] ?? 0) == 0) map['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    map['status'] = 'pending'; // paid state is server-written (verifyBookingPayment)
    final doc = await _col.add(map);
    return Booking.fromMap(doc.id, map);
  }
```
  - `test/support/fakes.dart` → `InMemoryBookingRepository.createBooking`: force `'status': 'pending'` in the same map it already builds, assign an id when `booking.id` is empty (`'bk${_bookings.length + 1}'`), store it, and return the stored `Booking`.
  - Dart lets callers ignore a returned value, so existing call sites keep compiling.
- `test/data/homestay_pay_test.dart`: delete the `'markPaid sets status=paid + updatedAt + paymentId'` test; keep the `paymentId` round-trip test.

- [ ] **Step 7: Run the new test + full suite — expect the payment SCREEN tests to fail**

Run: `flutter test test/data/payment_kind_test.dart` → PASS.
Run: `flutter test` → `payment_screen_test.dart`, `payment_flow_test.dart`, `homestay_payment_test.dart` and `booking_date_wire_test.dart` will fail to compile/pass (they call the old signature and assert the removed retry-save behaviour). **That is expected — Task 5 rewrites those screens and their tests.** Do NOT patch them here; note the failing files in your report.

- [ ] **Step 8: `flutter analyze`** — will report errors in the screens that still call the old signature; those are fixed in Task 5. Commit anyway so the seam change is one reviewable unit:

```bash
git add lib/data/services lib/data/repositories test/support/fakes.dart test/data/payment_kind_test.dart test/data/homestay_pay_test.dart
git commit -m "feat: payForBooking takes bookingId+kind (no client amount); drop markPaid"
```

**Sequencing note for the controller:** Task 4 intentionally leaves the tree red (screens still use the old seam). Task 5 restores green. If you prefer every task green, run Tasks 4 and 5 as a single unit.

---

### Task 5: Payment screens — pay by id, delete the retry-save class

**Files:**
- Modify: `lib/features/services/booking_screen.dart`
- Modify: `lib/features/services/payment_screen.dart`
- Modify: `lib/features/homestay/homestay_payment_screen.dart`
- Modify: `test/features/payment_screen_test.dart`, `test/features/payment_flow_test.dart`, `test/features/homestay_payment_test.dart`, `test/features/booking_date_wire_test.dart`

**Interfaces:**
- Consumes: `payForBooking({bookingId, kind, description, onVerifying})`, `PaymentKind`, `FakePaymentService.paidBookingIds/paidKinds` (Task 4); `canPayService` (Task 1).
- Produces: screens with phases `idle → opening → verifying` only; `BookingScreen` creates the pending booking.

- [ ] **Step 1: `BookingScreen` creates the pending booking then navigates**

In `lib/features/services/booking_screen.dart`, make `_continue` async and write the booking first. Replace the whole `_continue` with:
```dart
  bool _starting = false;

  Future<void> _continue(Pro pro, List<PetProfile> pets) async {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null || _starting) return;
    final pet = pets.firstWhere((p) => p.id == _petId, orElse: () => pets.first);
    final fee = Booking.feeFor(pro.rate);
    final day = _days[_dateIndex];
    final draft = Booking(
        parentId: me.uid, proId: pro.uid, proName: pro.name, petId: pet.id, petName: pet.name,
        serviceType: pro.serviceType, rate: pro.rate, fee: fee, total: pro.rate + fee,
        dateLabel: _label(day), timeSlot: _times[_timeIndex],
        date: Booking.isoDate(day), status: 'pending');
    setState(() => _starting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final created = await ref.read(bookingRepositoryProvider).createBooking(draft);
      if (!mounted) return;
      setState(() => _starting = false);
      context.push(Routes.payment, extra: created);
    } catch (_) {
      if (!mounted) return;
      setState(() => _starting = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Couldn\'t start this booking — try again.')));
    }
  }
```
Update the bottom button to `onPressed: (pets.isEmpty || _starting) ? () {} : () => _continue(pro, pets)` and its label to `_starting ? 'Starting…' : 'Continue to payment'` (keep the existing petless "Add a pet" branch exactly as it is).

(`createBooking` already returns the created `Booking` and forces `status: 'pending'` — done in Task 4, so `created.id` is available here.)

- [ ] **Step 2: Simplify `PaymentScreen` (services)**

- `enum _PayPhase { idle, opening, verifying }`.
- Delete the `_paid` field, the `saving`/`retrySave` labels, and the entire post-payment `createBooking` block.
- `_busy` becomes `_phase != _PayPhase.idle`.
- `_pay` becomes:
```dart
  Future<void> _pay(Booking booking) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _phase = _PayPhase.opening);
    try {
      await ref.read(paymentServiceProvider).payForBooking(
            bookingId: booking.id,
            kind: PaymentKind.service,
            description: '${booking.serviceType.label} · ${booking.dateLabel}',
            onVerifying: () {
              if (mounted) setState(() => _phase = _PayPhase.verifying);
            },
          );
    } on PaymentException catch (e) {
      if (!mounted) return;
      setState(() => _phase = _PayPhase.idle);
      messenger.showSnackBar(_snack(switch (e.type) {
        PaymentErrorType.cancelled => "Payment cancelled — you haven't been charged.",
        PaymentErrorType.failed => "Payment failed — you haven't been charged. Try again.",
        PaymentErrorType.unverified =>
          "Payment couldn't be verified — note payment id ${e.paymentId} and contact support.",
      }));
      return;
    }
    if (mounted) context.go(Routes.bookingConfirmed, extra: booking);
  }
```
Keep the summary card, the `_snack` helper, the bottom bar and `_label` (minus the deleted phases) exactly as they are. The screen's field stays `final Booking? draft;` (now a *created* booking, not a draft) — rename the field to `booking` for honesty, updating the router builder `PaymentScreen(booking: state.extra as Booking?)`.

- [ ] **Step 3: Simplify `HomestayPaymentScreen` identically**

Same three changes: `enum _PayPhase { idle, opening, verifying }`, delete `_paid` + the `markPaid` block, and:
```dart
  Future<void> _pay(HomestayBooking stay) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _phase = _PayPhase.opening);
    try {
      await ref.read(paymentServiceProvider).payForBooking(
            bookingId: stay.id,
            kind: PaymentKind.homestay,
            description: '${stay.homeName} · ${stay.nights} nights',
            onVerifying: () {
              if (mounted) setState(() => _phase = _PayPhase.verifying);
            },
          );
    } on PaymentException catch (e) {
      if (!mounted) return;
      setState(() => _phase = _PayPhase.idle);
      messenger.showSnackBar(_snack(switch (e.type) {
        PaymentErrorType.cancelled => "Payment cancelled — you haven't been charged.",
        PaymentErrorType.failed => "Payment failed — you haven't been charged. Try again.",
        PaymentErrorType.unverified =>
          "Payment couldn't be verified — note payment id ${e.paymentId} and contact support.",
      }));
      return;
    }
    if (mounted) context.go(Routes.bookings);
  }
```

- [ ] **Step 4: Update the four affected test files**

- `test/features/payment_flow_test.dart`: delete the `write-fails-after-verified-payment` test and `_FailingOnceBookingRepository` (that class no longer exists). Replace the success assertion `expect(payments.chargedAmounts, [275])` with `expect(payments.paidBookingIds, [<the created booking id>])` and `expect(payments.paidKinds, [PaymentKind.service])`. The in-flight `gate` test keeps working — assert `paidBookingIds.length == 1` instead of `chargedAmounts`. Cancelled/failed/unverified tests keep their snackbar assertions but drop any "no booking written" assertion that assumed the client writes (the booking now pre-exists) — assert instead that the row/nav did not advance (`find.text('Booking confirmed! 🎉'), findsNothing`).
- `test/features/payment_screen_test.dart`: the draft must now be a *created* pending booking — seed it through `InMemoryBookingRepository.createBooking` and pass the returned booking as `extra`; assert navigation to Booking-confirmed on success.
- `test/features/homestay_payment_test.dart`: delete the `write-fails-after-pay` test and `_FailOnceHomestayRepo`; replace `chargedAmounts` assertions with `paidBookingIds`/`paidKinds`; the stay stays `accepted` in the fake (the server would flip it) so drop status assertions that expected the client to flip it, keeping the snackbar/nav ones.
- `test/features/booking_date_wire_test.dart`: it taps through Booking → Payment; update it to assert the **created pending booking** carries the ISO `date` (read it from the repo after tapping "Continue to payment"), and keep the `paymentServiceProvider` override.

- [ ] **Step 5: Run the payment tests + full suite — expect PASS**

Run: `flutter test test/features/payment_flow_test.dart test/features/payment_screen_test.dart test/features/homestay_payment_test.dart test/features/booking_date_wire_test.dart && flutter test`

- [ ] **Step 6: Confirm the retry-save class is gone**

Grep `lib/` for `retrySave` and `Retry saving` → **no matches**.

- [ ] **Step 7: `flutter analyze` clean, then commit**

```bash
git add lib/features test/features
git commit -m "feat: pay by bookingId+kind; server writes paid, retry-save class deleted"
```

---

### Task 6: Functions emulator tests — including the exploit test

**Files:**
- Modify: `integration_test/functions_test.dart`

**Interfaces:**
- Consumes: the Task-2 callables; `FirestoreBookingRepository`/`FirestoreHomestayBookingRepository` for seeding.

- [ ] **Step 1: Add the contract + exploit tests**

Append to `integration_test/functions_test.dart` (the emulator wiring is already in `setUpAll`; ensure it includes `FirebaseFirestore.instance.useFirestoreEmulator('10.0.2.2', 8080);`):
```dart
  testWidgets('createBookingOrder: auth, args, ownership and payable-state gates',
      (tester) async {
    final fns = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final auth = FirebaseAuthRepository();
    final bookings = FirestoreBookingRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    await expectLater(
        fns.httpsCallable('createBookingOrder').call({'kind': 'service', 'bookingId': 'x'}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'unauthenticated')));

    final me = await auth.signUp(email: 'sop_$stamp@x.com', password: 'secret1');

    // Bad args + unknown booking.
    await expectLater(fns.httpsCallable('createBookingOrder').call({'kind': 'nope', 'bookingId': 'x'}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'invalid-argument')));
    await expectLater(
        fns.httpsCallable('createBookingOrder').call({'kind': 'service', 'bookingId': 'ghost_$stamp'}),
        throwsA(isA<FirebaseFunctionsException>().having((e) => e.code, 'code', 'not-found')));

    // A pending booking whose pro listing does not exist -> no-listing.
    final created = await bookings.createBooking(Booking(
        parentId: me.uid, proId: 'ghostpro_$stamp', proName: 'X', petId: 'p', petName: 'Bruno',
        serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue', timeSlot: '5:00 PM', date: '2027-01-10', status: 'pending'));
    await expectLater(
        fns.httpsCallable('createBookingOrder').call({'kind': 'service', 'bookingId': created.id}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'failed-precondition')
            .having((e) => e.message, 'message', 'no-listing')));

    await auth.signOut();
  });

  testWidgets('verifyBookingPayment: a payment for booking A cannot confirm booking B',
      (tester) async {
    final fns = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final auth = FirebaseAuthRepository();
    final bookings = FirestoreBookingRepository();
    final pros = FirestoreProRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // A pro listing the server can price from.
    final pro = await auth.signUp(email: 'sopro_$stamp@x.com', password: 'secret1');
    await pros.upsertPro(Pro(uid: pro.uid, name: 'Aarav', area: 'Khar', bio: 'Walker',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 3));
    await auth.signOut();

    final me = await auth.signUp(email: 'sopay_$stamp@x.com', password: 'secret1');
    Future<Booking> mk() => bookings.createBooking(Booking(
        parentId: me.uid, proId: pro.uid, proName: 'Aarav', petId: 'p', petName: 'Bruno',
        serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue', timeSlot: '5:00 PM', date: '2027-01-10', status: 'pending'));
    final a = await mk();
    final b = await mk();

    // An order is created for booking A (this reaches real Razorpay, so only run
    // this test with test-mode secrets configured in the emulator).
    final orderRes = await fns.httpsCallable('createBookingOrder')
        .call<Map<Object?, Object?>>({'kind': 'service', 'bookingId': a.id});
    final orderId = Map<String, dynamic>.from(orderRes.data)['orderId'] as String;

    // Attempting to verify that order against booking B is rejected by the
    // order<->booking binding, even before any signature could be valid.
    await expectLater(
        fns.httpsCallable('verifyBookingPayment').call({
          'kind': 'service', 'bookingId': b.id, 'orderId': orderId,
          'paymentId': 'pay_fake_$stamp', 'signature': 'deadbeef',
        }),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'permission-denied')));

    await auth.signOut();
  });
```
Add the imports these need (`Booking`, `Pro`, `ServiceType`, `FirestoreBookingRepository`, `FirestoreProRepository`) if absent.

**Note:** the exploit test's `createBookingOrder` call hits the real Razorpay Orders API, so it needs the owner's test-mode secrets available to the emulator (`functions/.secret.local`). If they aren't configured, the test will fail at order creation — mark it skipped rather than deleting it, and note it in the report.

- [ ] **Step 2: Build + run against the emulators**

```bash
npm --prefix functions run build
firebase emulators:start --only auth,firestore,functions --project pet-aggregator-app
flutter test integration_test/functions_test.dart -d emulator-5554
```
Kill the emulators after; confirm ports 9099/8080/5001 freed. **If the instrumentation build hangs (it has before), defer to Task 7 and report DONE_WITH_CONCERNS.**

- [ ] **Step 3: `flutter analyze` clean + unit suite green, then commit**

```bash
git add integration_test/functions_test.dart
git commit -m "test: payment contract + order-binding exploit test"
```

---

### Task 7: Final verification + deploy + on-device pass

**Files:** none (fixes only if verification finds problems).

- [ ] **Step 1: Full local verification**

```bash
flutter analyze              # No issues found!
flutter test                 # all pass
npm --prefix functions run build   # tsc exit 0
flutter build apk --debug    # succeeds
```

- [ ] **Step 2: Emulator suites** (mandatory here if Task 3 or 6 deferred)

```bash
firebase emulators:start --only auth,firestore,functions --project pet-aggregator-app
flutter test integration_test/firebase_repos_test.dart -d emulator-5554   # rules matrix (client can't write paid)
flutter test integration_test/functions_test.dart -d emulator-5554        # contract + exploit test
```
Kill emulators; confirm ports freed.

- [ ] **Step 3: Deploy (owner-run)** — requires the Razorpay secrets from Slice 11:

```bash
firebase deploy --only functions --project pet-aggregator-app
firebase deploy --only firestore:rules --project pet-aggregator-app
```
**Deploy the Functions BEFORE the rules** (the rules remove the client's paid-write; deploying them first would break payments for any client running the old build until the Functions land).

- [ ] **Step 4: On-device pass** (`flutter run -d emulator-5554`, two accounts)

1. **Services:** book a walker → "Continue to payment" creates a **Awaiting payment** booking → pay with `success@razorpay` → Booking-confirmed; Firestore shows `status:'confirmed'` with a `pay_…` and server amounts.
2. Abandon a checkout → the booking stays **Awaiting payment** in My bookings and can be paid later; past its date it reads **Expired**.
3. **Homestay:** request → host accepts → pay → the stay flips to **Upcoming**; then cancel it ≥24h out → refund (this also exercises Slice 14 end-to-end), **including a second cancel attempt on the already-cancelled stay** (the anti-double-refund claim has no automated coverage).
4. **The gate:** confirm the app can no longer write paid state directly — the only path is through the Functions.

- [ ] **Step 5: Commit any verification fixes** (none expected).

---

## Self-review notes (checked against the spec)

- Spec coverage: lifecycle (T1), both Functions incl. price recompute + order-notes binding + transactional paid-write (T2), rules + matrix migration (T3), seam + `markPaid` removal + `createBooking` pending (T4), screens simplified + the four test migrations (T5), emulator contract + exploit test (T6), verify/deploy/on-device (T7). The spec's test-migration table maps to T3 (matrix), T4 (`homestay_pay_test`, fakes) and T5 (payment screen tests).
- Type consistency: `PaymentKind{service,homestay}`, `payForBooking({bookingId, kind, description, onVerifying})`, `paidBookingIds`/`paidKinds`, `canPayService(b, now)`, `loadPayable(kind, bookingId, uid)`, `readArgs(data)`, callable payloads `{kind, bookingId, …}`, error messages `not-payable`/`no-listing`/`amount-mismatch`/`order-booking-mismatch` — identical across tasks and tests.
- **Deliberate red window:** Task 4 leaves the screens uncompilable (old seam) and Task 5 restores green. Flagged in Task 4's sequencing note; run 4+5 together if every task must be green.
- `createBooking` changes return type to `Future<Booking>` and forces `status:'pending'` — both done once, in T4 Step 6 (the Firestore impl already has the `DocumentReference` to build the id from); T5 just consumes `created.id`.
- The exploit test needs real Razorpay test secrets in the emulator (order creation hits the live test API); flagged with a skip-not-delete instruction.
