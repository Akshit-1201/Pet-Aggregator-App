# Pawgo Slice 11: Payments (Services · Razorpay test mode) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Real Razorpay test-mode checkout on the services booking flow — order created and signature verified by the project's first two Cloud Functions; the booking is written only after verification, stamped with its `paymentId`.

**Architecture:** Two callable Functions (`createBookingOrder`, `verifyBookingPayment`) own the Razorpay key secret. The app talks to them through a `PaymentService` seam whose sole implementation file imports `razorpay_flutter` + `cloud_functions`; screens and tests see only the interface. `PaymentScreen` drops the fake card UI for an honest summary + real checkout states. Repository seam, `bookings` rules, and the Slice-10 lifecycle are untouched.

**Tech Stack:** Flutter/Dart ^3.12.2, `razorpay_flutter` ^1.4.5 + `cloud_functions` ^6.3.3 (both already in pubspec — first imports now), Firebase Functions v2 (TypeScript, Node 20, `razorpay` npm SDK), `crypto` (new dev-dependency, integration test only).

**Spec:** `docs/superpowers/specs/2026-07-20-pawgo-payments-services-razorpay-design.md`.

## Global Constraints

- Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **SDK isolation:** `razorpay_flutter` and `cloud_functions` may be imported ONLY in `lib/data/services/razorpay_payment_service.dart`.
- **Region `asia-south1` everywhere**: both Functions declare it; every `FirebaseFunctions.instanceFor(region: 'asia-south1')`.
- Amounts: client sends whole **rupees** (int); the server converts to paise (`× 100`); currency `INR`; `createBookingOrder` accepts only integers `1..100000`; Razorpay `receipt` must be ≤ 40 chars.
- **Secrets never enter the repo**: `RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET` live in Secret Manager (prod) and `functions/.secret.local` (emulator, git-ignored, dummy values). The app never hardcodes a key id — it arrives per-order from the server.
- Exact copy strings: cancel snackbar `Payment cancelled — you haven't been charged.`; failure snackbar `Payment failed — you haven't been charged. Try again.`; unverified snackbar `Payment couldn't be verified — note payment id {paymentId} and contact support.`; write-failed snackbar `Payment received (id {paymentId}) but saving the booking failed — try again or contact support.`; secured note `🔒 Secured by Razorpay — UPI, cards & netbanking`; button labels `Pay ₹X` / `Opening…` / `Verifying…` / `Saving…` / `Retry saving`.
- Error taxonomy: `cancelled` and `failed` mean **nothing was charged**; `unverified` means the gateway succeeded but verification didn't (money may have moved — never claim otherwise) and carries the `paymentId`.
- Riverpod 3.x idioms; async handlers guard `context.mounted` after `await`; widget tests use `pumpPgApp` + fakes.
- Every task ends green: `flutter analyze` clean + `flutter test` passes, then commit. Do NOT deploy functions (Task 7 hands that to the owner).

---

### Task 1: Functions workspace — `createBookingOrder` + `verifyBookingPayment`

**Files:**
- Create: `functions/package.json`, `functions/tsconfig.json`, `functions/src/index.ts`, `functions/.gitignore`, `functions/.secret.local`
- Modify: `firebase.json` (functions source + emulator port)

**Interfaces:**
- Consumes: nothing (first Functions in the project).
- Produces: callable `createBookingOrder({amountRupees:int}) → {orderId:string, amountPaise:int, keyId:string}` and callable `verifyBookingPayment({orderId,paymentId,signature}) → {verified:true}`, both region `asia-south1`, both rejecting unauthenticated calls; errors: `unauthenticated` / `invalid-argument` / `internal('order-failed')` / `permission-denied('signature-mismatch')`.

- [ ] **Step 1: Create the workspace files**

```json
// functions/package.json
{
  "name": "functions",
  "private": true,
  "engines": { "node": "20" },
  "main": "lib/index.js",
  "scripts": { "build": "tsc" },
  "dependencies": {
    "firebase-admin": "^13.0.0",
    "firebase-functions": "^6.1.0",
    "razorpay": "^2.9.4"
  },
  "devDependencies": { "typescript": "^5.7.0" }
}
```

```json
// functions/tsconfig.json
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "es2022",
    "outDir": "lib",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "sourceMap": true
  },
  "include": ["src"]
}
```

```
# functions/.gitignore
node_modules/
lib/
.secret.local
```

```
# functions/.secret.local  (emulator-only dummy values; git-ignored — recreate on a fresh clone)
RAZORPAY_KEY_ID=rzp_test_dummy
RAZORPAY_KEY_SECRET=test_secret
```

```ts
// functions/src/index.ts
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as crypto from "crypto";
import Razorpay from "razorpay";

const razorpayKeyId = defineSecret("RAZORPAY_KEY_ID");
const razorpayKeySecret = defineSecret("RAZORPAY_KEY_SECRET");

export const createBookingOrder = onCall(
  {region: "asia-south1", secrets: [razorpayKeyId, razorpayKeySecret]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const amountRupees = request.data?.amountRupees;
    if (!Number.isInteger(amountRupees) || amountRupees < 1 || amountRupees > 100000) {
      throw new HttpsError("invalid-argument", "bad-amount");
    }
    const rzp = new Razorpay({
      key_id: razorpayKeyId.value(),
      key_secret: razorpayKeySecret.value(),
    });
    try {
      const order = await rzp.orders.create({
        amount: amountRupees * 100, // paise
        currency: "INR",
        receipt: `bk_${request.auth.uid}_${Date.now()}`.slice(0, 40),
      });
      return {orderId: order.id, amountPaise: order.amount, keyId: razorpayKeyId.value()};
    } catch (e) {
      throw new HttpsError("internal", "order-failed");
    }
  });

export const verifyBookingPayment = onCall(
  {region: "asia-south1", secrets: [razorpayKeySecret]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in-required");
    const {orderId, paymentId, signature} = request.data ?? {};
    if (typeof orderId !== "string" || orderId === "" ||
        typeof paymentId !== "string" || paymentId === "" ||
        typeof signature !== "string" || signature === "") {
      throw new HttpsError("invalid-argument", "bad-args");
    }
    const expected = crypto.createHmac("sha256", razorpayKeySecret.value())
      .update(`${orderId}|${paymentId}`)
      .digest("hex");
    const a = Buffer.from(expected);
    const b = Buffer.from(signature);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      throw new HttpsError("permission-denied", "signature-mismatch");
    }
    return {verified: true};
  });
```

- [ ] **Step 2: Wire `firebase.json`** — add a top-level `functions` block and a functions emulator port (keep everything already there):

```json
  "functions": { "source": "functions", "predeploy": ["npm --prefix functions run build"] },
```
and inside `"emulators"`:
```json
    "functions": { "port": 5001 },
```

- [ ] **Step 3: Install + build (this is the task's test)**

Run: `npm --prefix functions install` then `npm --prefix functions run build`
Expected: install succeeds; `tsc` exits 0 and `functions/lib/index.js` exists. (The emulator behaviour test comes in Task 6.)

- [ ] **Step 4: Verify the Flutter side is untouched**

Run: `flutter analyze && flutter test test/app_smoke_test.dart`
Expected: clean / pass (nothing in `lib/` changed).

- [ ] **Step 5: Commit**

```bash
git add functions/package.json functions/tsconfig.json functions/src/index.ts functions/.gitignore firebase.json
git commit -m "feat: first Cloud Functions - createBookingOrder + verifyBookingPayment (asia-south1)"
```
(`functions/.secret.local`, `node_modules/`, `lib/` stay untracked via the new .gitignore.)

---

### Task 2: `Booking.paymentId` (additive model field)

**Files:**
- Modify: `lib/data/models/booking.dart`
- Test: `test/data/booking_payment_id_test.dart` (create)

**Interfaces:**
- Produces: `Booking.paymentId` (`String`, default `''`), constructor param `this.paymentId = ''`, in `toMap`/`fromMap`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/booking_payment_id_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

void main() {
  test('Booking.paymentId round-trips and defaults to empty', () {
    final b = Booking(id: 'bk1', parentId: 'g', proId: 'p', proName: 'Aarav', petId: 'x',
        petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue', timeSlot: '5:00 PM', paymentId: 'pay_abc123');
    expect(Booking.fromMap('bk1', b.toMap()).paymentId, 'pay_abc123');
    expect(Booking.fromMap('bk1', const {}).paymentId, ''); // legacy + homestay side
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (`paymentId` doesn't exist)

Run: `flutter test test/data/booking_payment_id_test.dart`

- [ ] **Step 3: Implement** — in `lib/data/models/booking.dart`: add `paymentId` to the String fields declaration (`final String dateLabel, timeSlot, status, date, paymentId;`), constructor (`this.paymentId = '',` after `this.date = '',`), `toMap()` (`'paymentId': paymentId,` after `'date': date,`), and `fromMap` (`paymentId: (m['paymentId'] ?? '') as String,` after the `date:` line).

- [ ] **Step 4: Run the test + the other booking model tests — expect PASS**

Run: `flutter test test/data/booking_payment_id_test.dart test/data/booking_test.dart test/data/booking_status_fields_test.dart`

- [ ] **Step 5: `flutter analyze` clean, then commit**

```bash
git add lib/data/models/booking.dart test/data/booking_payment_id_test.dart
git commit -m "feat: Booking carries an additive paymentId"
```

---

### Task 3: `PaymentService` seam + fake + provider

**Files:**
- Create: `lib/data/services/payment_service.dart`
- Modify: `lib/data/repositories/providers.dart` (one provider)
- Modify: `test/support/fakes.dart` (append `FakePaymentService`)
- Test: `test/data/payment_service_test.dart` (create)

**Interfaces:**
- Produces (used verbatim by Tasks 4–6):

```dart
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
  Future<PaymentResult> payForBooking({
    required int amountRupees,
    required String description,
    void Function()? onVerifying, // fires when the gateway succeeded and verification starts
  });
}
```
- Also produces: `paymentServiceProvider` (`Provider<PaymentService>`); `FakePaymentService` with `List<int> chargedAmounts`, optional success `result`, optional `error` to throw, optional `Completer<PaymentResult>? gate` (when set, `payForBooking` awaits it — lets tests hold a payment in flight), and `factory FakePaymentService.success()` returning `PaymentResult(paymentId: 'pay_fake123', orderId: 'order_fake123')`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/payment_service_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';

void main() {
  test('FakePaymentService.success returns the canned result, records amount, fires onVerifying', () async {
    final fake = FakePaymentService.success();
    var verifying = false;
    final r = await fake.payForBooking(
        amountRupees: 275, description: 'Dog Walker', onVerifying: () => verifying = true);
    expect(r.paymentId, 'pay_fake123');
    expect(r.orderId, 'order_fake123');
    expect(fake.chargedAmounts, [275]);
    expect(verifying, isTrue);
  });

  test('a configured error is thrown and still records the attempt', () async {
    final fake = FakePaymentService(
        error: const PaymentException(PaymentErrorType.cancelled, 'cancelled'));
    await expectLater(
        fake.payForBooking(amountRupees: 100, description: 'x'),
        throwsA(isA<PaymentException>()
            .having((e) => e.type, 'type', PaymentErrorType.cancelled)));
    expect(fake.chargedAmounts, [100]);
  });

  test('gate holds the payment in flight until completed', () async {
    final gate = Completer<PaymentResult>();
    final fake = FakePaymentService(gate: gate);
    final future = fake.payForBooking(amountRupees: 50, description: 'x');
    var done = false;
    unawaited(future.then((_) => done = true));
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    gate.complete(const PaymentResult(paymentId: 'pay_g', orderId: 'order_g'));
    expect((await future).paymentId, 'pay_g');
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (files don't exist)

Run: `flutter test test/data/payment_service_test.dart`

- [ ] **Step 3: Implement the seam** — `lib/data/services/payment_service.dart` with exactly the code from the Interfaces block above (no SDK imports in this file).

- [ ] **Step 4: Append the fake to `test/support/fakes.dart`**

```dart
class FakePaymentService implements PaymentService {
  final PaymentResult? result;
  final PaymentException? error;
  final Completer<PaymentResult>? gate;
  final List<int> chargedAmounts = [];
  FakePaymentService({this.result, this.error, this.gate});

  factory FakePaymentService.success() => FakePaymentService(
      result: const PaymentResult(paymentId: 'pay_fake123', orderId: 'order_fake123'));

  @override
  Future<PaymentResult> payForBooking({
    required int amountRupees,
    required String description,
    void Function()? onVerifying,
  }) async {
    chargedAmounts.add(amountRupees);
    if (gate != null) return gate!.future;
    if (error != null) throw error!;
    onVerifying?.call();
    return result ??
        (throw const PaymentException(PaymentErrorType.failed, 'not-configured'));
  }
}
```
(Add `import 'dart:async';` and `import 'package:pet_aggregator_app/data/services/payment_service.dart';` to `fakes.dart` if not present.)

- [ ] **Step 5: Add the provider** — in `lib/data/repositories/providers.dart`, next to `imagePickerServiceProvider`:

```dart
final paymentServiceProvider =
    Provider<PaymentService>((ref) => RazorpayPaymentService());
```
with imports `import '../services/payment_service.dart';` and `import '../services/razorpay_payment_service.dart';`. **Note:** `RazorpayPaymentService` arrives in Task 4 — to keep this task green on its own, add the provider in Task 4 instead if you're running tasks strictly in order; otherwise stub nothing. (Recommended: leave the provider to Task 4 and end this task with the interface + fake + tests only.)

- [ ] **Step 6: Run the test + full suite — expect PASS**

Run: `flutter test test/data/payment_service_test.dart && flutter test`

- [ ] **Step 7: `flutter analyze` clean, then commit**

```bash
git add lib/data/services/payment_service.dart test/support/fakes.dart test/data/payment_service_test.dart
git commit -m "feat: PaymentService seam + typed payment errors + fake"
```

---

### Task 4: `RazorpayPaymentService` (the only SDK importer) + provider

**Files:**
- Create: `lib/data/services/razorpay_payment_service.dart`
- Modify: `lib/data/repositories/providers.dart`

**Interfaces:**
- Consumes: `PaymentService`/`PaymentResult`/`PaymentException` (Task 3); callables from Task 1.
- Produces: `RazorpayPaymentService([FirebaseFunctions? functions])`; `paymentServiceProvider` in providers.dart.

- [ ] **Step 1: Implement**

```dart
// lib/data/services/razorpay_payment_service.dart
//
// The ONLY file allowed to import razorpay_flutter and cloud_functions.
// Flow: createBookingOrder (callable) -> Razorpay Checkout -> on success
// verifyBookingPayment (callable) -> PaymentResult. Cancel/failed mean
// "not charged"; unverified means the gateway succeeded but verification
// didn't - it carries the paymentId and must never be conflated with failed.
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'payment_service.dart';

class RazorpayPaymentService implements PaymentService {
  final FirebaseFunctions _functions;
  RazorpayPaymentService([FirebaseFunctions? functions])
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  Completer<PaymentResult>? _inFlight;
  void Function()? _onVerifying;

  @override
  Future<PaymentResult> payForBooking({
    required int amountRupees,
    required String description,
    void Function()? onVerifying,
  }) async {
    if (_inFlight != null) {
      throw const PaymentException(PaymentErrorType.failed, 'busy');
    }
    final Map<String, dynamic> order;
    try {
      final res = await _functions
          .httpsCallable('createBookingOrder')
          .call<Map<Object?, Object?>>({'amountRupees': amountRupees});
      order = Map<String, dynamic>.from(res.data);
    } catch (_) {
      throw const PaymentException(PaymentErrorType.failed, 'order-failed');
    }

    final completer = Completer<PaymentResult>();
    _inFlight = completer;
    _onVerifying = onVerifying;
    final razorpay = Razorpay();
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS,
        (PaymentSuccessResponse r) => _verify(razorpay, r));
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      _finishError(
          razorpay,
          r.code == Razorpay.PAYMENT_CANCELLED
              ? const PaymentException(PaymentErrorType.cancelled, 'cancelled')
              : PaymentException(PaymentErrorType.failed, r.message ?? 'failed'));
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      _finishError(razorpay,
          const PaymentException(PaymentErrorType.failed, 'external-wallet-unsupported'));
    });
    razorpay.open({
      'key': order['keyId'],
      'order_id': order['orderId'],
      'amount': order['amountPaise'],
      'currency': 'INR',
      'name': 'Pawgo',
      'description': description,
      'theme': {'color': '#F59E2E'},
    });
    return completer.future;
  }

  Future<void> _verify(Razorpay razorpay, PaymentSuccessResponse r) async {
    _onVerifying?.call();
    final paymentId = r.paymentId ?? '';
    try {
      await _functions.httpsCallable('verifyBookingPayment').call<Map<Object?, Object?>>({
        'orderId': r.orderId,
        'paymentId': r.paymentId,
        'signature': r.signature,
      });
      _finish(razorpay,
          result: PaymentResult(paymentId: paymentId, orderId: r.orderId ?? ''));
    } catch (_) {
      _finishError(
          razorpay,
          PaymentException(PaymentErrorType.unverified, 'verification-failed',
              paymentId: paymentId));
    }
  }

  void _finish(Razorpay razorpay, {required PaymentResult result}) {
    razorpay.clear();
    final c = _inFlight;
    _inFlight = null;
    _onVerifying = null;
    if (c != null && !c.isCompleted) c.complete(result);
  }

  void _finishError(Razorpay razorpay, PaymentException e) {
    razorpay.clear();
    final c = _inFlight;
    _inFlight = null;
    _onVerifying = null;
    if (c != null && !c.isCompleted) c.completeError(e);
  }
}
```

- [ ] **Step 2: Add the provider** — in `lib/data/repositories/providers.dart`, after `imagePickerServiceProvider`:

```dart
final paymentServiceProvider =
    Provider<PaymentService>((ref) => RazorpayPaymentService());
```
Imports: `import '../services/payment_service.dart';` and `import '../services/razorpay_payment_service.dart';`.

- [ ] **Step 3: Enforce the isolation rule** (grep gate)

Run (Grep or PowerShell): search `lib/` for `razorpay_flutter|cloud_functions` — the ONLY hit must be `lib/data/services/razorpay_payment_service.dart`.

- [ ] **Step 4: `flutter analyze` clean + full suite still green** (this class has no widget/unit test — the plugin needs a real Activity; behaviour is covered by the Task 6 emulator test for the callables and the Task 7 on-device pass)

Run: `flutter analyze && flutter test`

- [ ] **Step 5: Commit**

```bash
git add lib/data/services/razorpay_payment_service.dart lib/data/repositories/providers.dart
git commit -m "feat: RazorpayPaymentService - order, checkout, server verify (sole SDK importer)"
```

---

### Task 5: `PaymentScreen` rework — honest summary + real checkout states

**Files:**
- Modify: `lib/features/services/payment_screen.dart` (full rewrite below)
- Modify: `test/features/payment_screen_test.dart`
- Modify: `test/features/booking_date_wire_test.dart`
- Test: `test/features/payment_flow_test.dart` (create)

**Interfaces:**
- Consumes: `paymentServiceProvider`, `PaymentService.payForBooking(amountRupees:, description:, onVerifying:)`, `PaymentException`/`PaymentErrorType`, `FakePaymentService` (Tasks 3–4); `Booking.paymentId` (Task 2).
- Produces: the final PaymentScreen; no API other tasks consume.

- [ ] **Step 1: Update the two existing tests** (they tap Pay and will hit the real service otherwise)

In `test/features/payment_screen_test.dart`: add `paymentServiceProvider.overrideWithValue(FakePaymentService.success()),` to the overrides list, and extend the final assertions:

```dart
    final mine = await bookings.watchMyBookings('uid_me@x.com').first;
    expect(mine.single.petName, 'Bruno');
    expect(mine.single.paymentId, 'pay_fake123');
    expect(find.text('Booking confirmed! 🎉'), findsOneWidget);
```

In `test/features/booking_date_wire_test.dart`: add `paymentServiceProvider.overrideWithValue(FakePaymentService.success()),` to its overrides list (no other change).

- [ ] **Step 2: Write the failing flow tests**

```dart
// test/features/payment_flow_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _draft = Booking(parentId: 'uid_me@x.com', proId: 'pro1', proName: 'Aarav Sharma',
    petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25,
    total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', date: '2027-01-10');

class _FailingOnceBookingRepository extends InMemoryBookingRepository {
  int _failuresLeft = 1;
  @override
  Future<void> createBooking(Booking booking) {
    if (_failuresLeft > 0) {
      _failuresLeft--;
      throw Exception('write-failed');
    }
    return super.createBooking(booking);
  }
}

Future<(InMemoryBookingRepository, FakePaymentService)> _pump(WidgetTester tester,
    {FakePaymentService? payments, InMemoryBookingRepository? bookings}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final b = bookings ?? InMemoryBookingRepository();
  final p = payments ?? FakePaymentService.success();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    bookingRepositoryProvider.overrideWithValue(b),
    paymentServiceProvider.overrideWithValue(p),
  ], initialLocation: Routes.payment, extra: _draft);
  await tester.pumpAndSettle();
  return (b, p);
}

void main() {
  testWidgets('the fake theater is gone; the honest summary is shown', (tester) async {
    await _pump(tester);
    expect(find.text('PAWGO PAY'), findsNothing);
    expect(find.textContaining('4421'), findsNothing);
    expect(find.textContaining('Pawgo Wallet'), findsNothing);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('🔒 Secured by Razorpay — UPI, cards & netbanking'), findsOneWidget);
  });

  testWidgets('success: charged the exact total, booking written with paymentId, navigates',
      (tester) async {
    final (bookings, payments) = await _pump(tester);
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(payments.chargedAmounts, [275]);
    final stored = (await bookings.watchMyBookings('uid_me@x.com').first).single;
    expect(stored.paymentId, 'pay_fake123');
    expect(stored.date, '2027-01-10'); // draft fields survive
    expect(find.text('Booking confirmed! 🎉'), findsOneWidget);
  });

  testWidgets('cancelled: no booking, honest snackbar, button idle again', (tester) async {
    final (bookings, _) = await _pump(tester,
        payments: FakePaymentService(
            error: const PaymentException(PaymentErrorType.cancelled, 'cancelled')));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(find.text("Payment cancelled — you haven't been charged."), findsOneWidget);
    expect(find.text('Pay ₹275'), findsOneWidget);
    expect(await bookings.watchMyBookings('uid_me@x.com').first, isEmpty);
  });

  testWidgets('failed: no booking, failure snackbar', (tester) async {
    final (bookings, _) = await _pump(tester,
        payments: FakePaymentService(
            error: const PaymentException(PaymentErrorType.failed, 'declined')));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(find.text("Payment failed — you haven't been charged. Try again."), findsOneWidget);
    expect(await bookings.watchMyBookings('uid_me@x.com').first, isEmpty);
  });

  testWidgets('unverified: no booking, snackbar carries the payment id', (tester) async {
    final (bookings, _) = await _pump(tester,
        payments: FakePaymentService(
            error: const PaymentException(PaymentErrorType.unverified, 'verification-failed',
                paymentId: 'pay_x9')));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pay_x9'), findsOneWidget);
    expect(await bookings.watchMyBookings('uid_me@x.com').first, isEmpty);
  });

  testWidgets('write-fails-after-verified-payment: Retry saving writes without a second charge',
      (tester) async {
    final bookings = _FailingOnceBookingRepository();
    final (_, payments) = await _pump(tester, bookings: bookings);
    await tester.tap(find.text('Pay ₹275'));
    await tester.pumpAndSettle();
    expect(find.textContaining('saving the booking failed'), findsOneWidget);
    expect(find.text('Retry saving'), findsOneWidget);

    await tester.tap(find.text('Retry saving'));
    await tester.pumpAndSettle();
    expect(payments.chargedAmounts, [275]); // exactly ONE charge across both taps
    final stored = (await bookings.watchMyBookings('uid_me@x.com').first).single;
    expect(stored.paymentId, 'pay_fake123');
    expect(find.text('Booking confirmed! 🎉'), findsOneWidget);
  });

  testWidgets('button is disabled while a payment is in flight', (tester) async {
    final gate = Completer<PaymentResult>();
    final (bookings, payments) = await _pump(tester, payments: FakePaymentService(gate: gate));
    await tester.tap(find.text('Pay ₹275'));
    await tester.pump();
    expect(find.text('Opening…'), findsOneWidget);
    await tester.tap(find.text('Opening…')); // second tap must be a no-op
    await tester.pump();
    gate.complete(const PaymentResult(paymentId: 'pay_g', orderId: 'order_g'));
    await tester.pumpAndSettle();
    expect(payments.chargedAmounts, [275]); // single attempt
    expect((await bookings.watchMyBookings('uid_me@x.com').first).single.paymentId, 'pay_g');
  });
}
```

- [ ] **Step 3: Run the new + updated tests — expect FAIL** (old fake-card screen)

Run: `flutter test test/features/payment_flow_test.dart test/features/payment_screen_test.dart`

- [ ] **Step 4: Rewrite `lib/features/services/payment_screen.dart`** (full replacement)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/providers.dart';
import '../../data/services/payment_service.dart';

enum _PayPhase { idle, opening, verifying, saving, retrySave }

class PaymentScreen extends ConsumerStatefulWidget {
  final Booking? draft;
  const PaymentScreen({super.key, this.draft});
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  _PayPhase _phase = _PayPhase.idle;
  PaymentResult? _paid; // kept across a failed booking write so retry never re-charges

  bool get _busy =>
      _phase == _PayPhase.opening || _phase == _PayPhase.verifying || _phase == _PayPhase.saving;

  String _label(int total) => switch (_phase) {
        _PayPhase.idle => 'Pay ₹$total',
        _PayPhase.opening => 'Opening…',
        _PayPhase.verifying => 'Verifying…',
        _PayPhase.saving => 'Saving…',
        _PayPhase.retrySave => 'Retry saving',
      };

  Future<void> _pay(Booking draft) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_paid == null) {
      setState(() => _phase = _PayPhase.opening);
      try {
        _paid = await ref.read(paymentServiceProvider).payForBooking(
              amountRupees: draft.total,
              description: '${draft.serviceType.label} · ${draft.dateLabel}',
              onVerifying: () {
                if (mounted) setState(() => _phase = _PayPhase.verifying);
              },
            );
      } on PaymentException catch (e) {
        if (!mounted) return;
        setState(() => _phase = _PayPhase.idle);
        messenger.showSnackBar(SnackBar(
            content: Text(switch (e.type) {
          PaymentErrorType.cancelled => "Payment cancelled — you haven't been charged.",
          PaymentErrorType.failed => "Payment failed — you haven't been charged. Try again.",
          PaymentErrorType.unverified =>
            "Payment couldn't be verified — note payment id ${e.paymentId} and contact support.",
        })));
        return;
      }
      if (!mounted) return;
    }
    setState(() => _phase = _PayPhase.saving);
    final paid = _paid!;
    final booking = Booking(
        parentId: draft.parentId, proId: draft.proId, proName: draft.proName,
        petId: draft.petId, petName: draft.petName, serviceType: draft.serviceType,
        rate: draft.rate, fee: draft.fee, total: draft.total,
        dateLabel: draft.dateLabel, timeSlot: draft.timeSlot, date: draft.date,
        paymentId: paid.paymentId);
    try {
      await ref.read(bookingRepositoryProvider).createBooking(booking);
      if (mounted) context.go(Routes.bookingConfirmed, extra: booking);
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _PayPhase.retrySave);
      messenger.showSnackBar(SnackBar(
          content: Text('Payment received (id ${paid.paymentId}) but saving the booking '
              'failed — try again or contact support.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final draft = widget.draft;
    if (draft == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No booking')));
    }
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Payment', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: c.surface,
                      border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _row(c, 'Professional', draft.proName),
                    _row(c, 'Service', draft.serviceType.label),
                    _row(c, 'When', '${draft.dateLabel} · ${draft.timeSlot}'),
                    _row(c, 'Pet', draft.petName),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Container(height: 1, color: c.border)),
                    _row(c, 'Rate', '₹${draft.rate}'),
                    _row(c, 'Service fee', '₹${draft.fee}'),
                    _row(c, 'Total', '₹${draft.total}', bold: true),
                  ]),
                ),
                const SizedBox(height: 14),
                Text('🔒 Secured by Razorpay — UPI, cards & netbanking',
                    style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
                color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(22, 13, 22, 18),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total', style: PgText.inter(12, FontWeight.w400, color: c.faint)),
                Text('₹${draft.total}', style: PgText.poppins(20, FontWeight.w800, color: c.text)),
              ]),
              const SizedBox(width: 14),
              Expanded(
                  child: GestureDetector(
                      onTap: _busy ? null : () => _pay(draft),
                      child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [c.brand, c.brand2]),
                              borderRadius: BorderRadius.circular(16)),
                          child: Text(_label(draft.total),
                              style: PgText.poppins(15.5, FontWeight.w700,
                                  color: Colors.white))))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(PgColors c, String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: PgText.inter(13, FontWeight.w400, color: c.muted)),
          Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bold
                      ? PgText.poppins(14.5, FontWeight.w800, color: c.text)
                      : PgText.inter(13, FontWeight.w600, color: c.text))),
        ]),
      );
}
```

- [ ] **Step 5: Run the payment tests + full suite — expect PASS**

Run: `flutter test test/features/payment_flow_test.dart test/features/payment_screen_test.dart test/features/booking_date_wire_test.dart && flutter test`

- [ ] **Step 6: `flutter analyze` clean, then commit**

```bash
git add lib/features/services/payment_screen.dart test/features/payment_flow_test.dart test/features/payment_screen_test.dart test/features/booking_date_wire_test.dart
git commit -m "feat: honest Payment screen - real checkout states, no fake card theater"
```

---

### Task 6: Functions emulator integration test (HMAC verify)

**Files:**
- Create: `integration_test/functions_test.dart`
- Modify: `pubspec.yaml` (dev_dependencies: `crypto: ^3.0.6`)

**Interfaces:**
- Consumes: the Task 1 callables running in the Functions emulator with `functions/.secret.local` (`RAZORPAY_KEY_SECRET=test_secret`).

- [ ] **Step 1: Add the dev dependency** — in `pubspec.yaml` under `dev_dependencies:` add `crypto: ^3.0.6`, then run `flutter pub get`.

- [ ] **Step 2: Write the test**

```dart
// integration_test/functions_test.dart
//
// Verifies the payment callables against the Functions emulator. Run with:
//   npm --prefix functions run build
//   firebase emulators:start --only auth,functions --project pet-aggregator-app
//   flutter test integration_test/functions_test.dart -d emulator-5554
// Requires functions/.secret.local containing RAZORPAY_KEY_SECRET=test_secret
// (git-ignored; recreate on a fresh clone).
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pet_aggregator_app/firebase_options.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('10.0.2.2', 9099);
    FirebaseFunctions.instanceFor(region: 'asia-south1')
        .useFunctionsEmulator('10.0.2.2', 5001);
  });

  testWidgets('verifyBookingPayment: auth gate, valid HMAC accepted, tampering rejected',
      (tester) async {
    final fns = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // Unauthenticated calls are rejected by both callables.
    await expectLater(
        fns.httpsCallable('verifyBookingPayment')
            .call({'orderId': 'o', 'paymentId': 'p', 'signature': 's'}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'unauthenticated')));
    await expectLater(
        fns.httpsCallable('createBookingOrder').call({'amountRupees': 275}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'unauthenticated')));

    await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: 'fn_$stamp@x.com', password: 'secret1');

    // A valid signature (dummy secret matches functions/.secret.local).
    const secret = 'test_secret';
    const orderId = 'order_test1';
    const paymentId = 'pay_test1';
    final valid = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode('$orderId|$paymentId'))
        .toString();
    final ok = await fns.httpsCallable('verifyBookingPayment').call<Map<Object?, Object?>>(
        {'orderId': orderId, 'paymentId': paymentId, 'signature': valid});
    expect(ok.data['verified'], true);

    // A tampered signature is rejected.
    final tampered = valid.replaceRange(0, 1, valid[0] == 'a' ? 'b' : 'a');
    await expectLater(
        fns.httpsCallable('verifyBookingPayment')
            .call({'orderId': orderId, 'paymentId': paymentId, 'signature': tampered}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'permission-denied')));

    // createBookingOrder input validation (no Razorpay network needed to reject).
    await expectLater(
        fns.httpsCallable('createBookingOrder').call({'amountRupees': 0}),
        throwsA(isA<FirebaseFunctionsException>()
            .having((e) => e.code, 'code', 'invalid-argument')));

    await FirebaseAuth.instance.signOut();
  });
}
```

- [ ] **Step 3: Run it against the emulators** (build functions first; needs an Android emulator, same as the existing Firestore suite)

```bash
npm --prefix functions run build
firebase emulators:start --only auth,functions --project pet-aggregator-app   # terminal 1
flutter test integration_test/functions_test.dart -d emulator-5554            # terminal 2
```
Expected: all assertions pass. Stop the Firebase emulators afterwards. (If no Android emulator is available in this environment, complete Steps 1–2, run `flutter analyze`, and defer the run to Task 7 — same convention as Slice 10's rules matrix.)

- [ ] **Step 4: `flutter analyze` clean + unit suite untouched**

Run: `flutter analyze && flutter test`

- [ ] **Step 5: Commit**

```bash
git add integration_test/functions_test.dart pubspec.yaml pubspec.lock
git commit -m "test: verifyBookingPayment HMAC matrix against the Functions emulator"
```

---

### Task 7: Final verification + owner setup + on-device Razorpay pass

**Files:** none (fixes only if verification finds problems).

- [ ] **Step 1: Full local verification**

```bash
flutter analyze              # No issues found!
flutter test                 # all pass
flutter build apk --debug    # succeeds — razorpay_flutter native code compiles
npm --prefix functions run build   # tsc exits 0
```
(If the Kotlin "different roots" error appears from the new plugin, confirm `kotlin.incremental=false` in `android/gradle.properties` and `flutter clean`.)

- [ ] **Step 2: Emulator integration suites** (if Task 6's run was deferred, it is mandatory here)

```bash
npm --prefix functions run build
firebase emulators:start --only auth,firestore,functions --project pet-aggregator-app
flutter test integration_test/functions_test.dart -d emulator-5554
flutter test integration_test/firebase_repos_test.dart -d emulator-5554   # regression: still green
```
Kill the emulator processes afterwards; verify ports 9099/8080/5001 freed.

- [ ] **Step 3: Owner setup (USER-RUN — the assistant must not do these)**

1. Create a free Razorpay account at razorpay.com (test mode — no KYC).
2. Dashboard → Settings → API Keys → Generate **Test Key** → copy Key ID + Key Secret.
3. In the repo: `! firebase functions:secrets:set RAZORPAY_KEY_ID` (paste the Key ID when prompted), then `! firebase functions:secrets:set RAZORPAY_KEY_SECRET` (paste the Secret).
4. `! firebase deploy --only functions --project pet-aggregator-app` — expected: `✔ Deploy complete!` with both functions in `asia-south1`.

- [ ] **Step 4: On-device pass (`flutter run -d emulator-5554`, after Step 3)**

1. Book a walker → Payment shows the honest summary (no fake VISA card) → `Pay ₹275` opens the real Razorpay test checkout.
2. Pay with test UPI `success@razorpay` → `Verifying…` → Booking-confirmed; the Firestore booking has a `pay_…` `paymentId`; the payment shows in the Razorpay test dashboard; Bookings hub shows the booking as Upcoming.
3. Back out of checkout → `Payment cancelled — you haven't been charged.`, no booking written.
4. Pay with the failure test instrument (`failure@razorpay`) → failure snackbar, no booking.

- [ ] **Step 5: Commit any verification fixes** (none expected; do not commit secrets or `.secret.local`).

---

## Self-review notes (checked against the spec)

- Spec coverage: Functions (Task 1), model (Task 2), seam+fake (Task 3), sole-importer impl + provider (Task 4), screen rework + all five error/UX paths incl. retry-save and busy-guard (Task 5), emulator HMAC matrix + auth gates (Task 6), owner setup/deploy/on-device DoD (Task 7). Homestay flow untouched anywhere — matches scope.
- The spec's `PaymentService` interface gains one optional param (`onVerifying`) — it is how the spec's mandated `Opening…`→`Verifying…` button states are realized through the seam; documented here deliberately.
- Type consistency: `PaymentResult(paymentId:, orderId:)`, `PaymentErrorType.{cancelled,failed,unverified}`, `PaymentException(type, message, {paymentId})`, `payForBooking({amountRupees, description, onVerifying})`, `paymentServiceProvider`, callable names `createBookingOrder`/`verifyBookingPayment`, region `asia-south1`, dummy secret `test_secret` — identical spellings across Tasks 1–6.
- `Razorpay.PAYMENT_CANCELLED` is compared symbolically (never a hardcoded int), so plugin constant values can't bite.
- The provider intentionally lands in Task 4 (not 3) so every task compiles green on its own.
