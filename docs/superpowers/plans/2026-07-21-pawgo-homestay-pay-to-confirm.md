# Pawgo Slice 13: Homestay pay-to-confirm — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a host accepts a stay, the guest pays (real Razorpay test-mode checkout) to confirm it — a new `paid` status reached via a `markPaid` transition, surfaced as "Pay to confirm" in My-bookings and a `paid` host notification, reusing the entire Slice-11 payment machinery.

**Architecture:** New stored status `paid` on `homestayBookings`, written only by `markPaid(id, paymentId)` after a server-verified payment. `booking_lifecycle.dart` gains an `awaitingPayment` phase and a `canPay` permission; `stayPhase` routes `accepted`→awaiting/expired and `paid`→upcoming/completed. A new `HomestayPaymentScreen` clones the services `PaymentScreen`, reusing the `PaymentService` seam and its phase machine/copy, differing only in the summary and in calling `markPaid` instead of `createBooking`. One rules branch, one derived notification. No new packages or Cloud Functions.

**Tech Stack:** Flutter/Dart ^3.12.2, `flutter_riverpod` 3.x, `go_router`, `cloud_firestore`. Reuses `razorpay_flutter`/`cloud_functions` only through the existing `PaymentService` seam (no new SDK imports).

**Spec:** `docs/superpowers/specs/2026-07-21-pawgo-homestay-pay-to-confirm-design.md`.

## Global Constraints

- Keep `android/gradle.properties` → `kotlin.incremental=false`.
- No new packages, no new Cloud Functions. `razorpay_flutter`/`cloud_functions` stay imported ONLY in `lib/data/services/razorpay_payment_service.dart` (unchanged) — the new screen uses the `PaymentService` seam.
- Only new write: guest `accepted → paid` via `markPaid`, writing exactly `{status:'paid', updatedAt:<client millis>, paymentId}`. `updatedAt` is `DateTime.now().millisecondsSinceEpoch` (matches the repo convention).
- Stored statuses: `requested → accepted|declined` (host), `requested|accepted → cancelled` (guest), `accepted → paid` (guest). `awaitingPayment`/`completed`/`expired` are derived, never stored.
- **No self-cancel once paid this slice** — `canCancelStay` is unchanged (already excludes `paid`). Paid/upcoming rows show a passive "Contact host to cancel".
- Reuse Slice-11 copy verbatim in the new screen: button `Pay ₹X`/`Opening…`/`Verifying…`/`Saving…`/`Retry saving`; snackbars cancelled `Payment cancelled — you haven't been charged.`, failed `Payment failed — you haven't been charged. Try again.`, unverified `Payment couldn't be verified — note payment id {paymentId} and contact support.`, write-fail `Payment received (id {paymentId}) but saving the booking failed — try again or contact support.`; secured note `🔒 Secured by Razorpay — UPI, cards & netbanking`; the floating `_snack` with `margin fromLTRB(16,0,16,100)`.
- New copy: My-bookings pay action `Pay to confirm`; paid-row note `Contact host to cancel`; new phase label `Pay to confirm`; host paid notification `{petName}'s stay is confirmed & paid`.
- Riverpod 3.x `.value`; async handlers guard `context.mounted` after `await`; widget tests use `pumpPgApp` + fakes.
- Every task ends green: `flutter analyze` clean + `flutter test` passes, then commit. Do NOT push. Do NOT deploy (Task 7 hands rules deploy to the owner).

---

### Task 1: `HomestayBooking.paymentId` + `markPaid` repository method

**Files:**
- Modify: `lib/data/models/homestay_booking.dart`
- Modify: `lib/data/repositories/homestay_booking_repository.dart`
- Modify: `lib/data/repositories/firebase/firestore_homestay_booking_repository.dart`
- Modify: `test/support/fakes.dart` (`InMemoryHomestayBookingRepository`)
- Test: `test/data/homestay_pay_test.dart` (create)

**Interfaces:**
- Produces: `HomestayBooking.paymentId` (`String`, default `''`); `HomestayBookingRepository.markPaid(String id, String paymentId)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/homestay_pay_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import '../support/fakes.dart';

HomestayBooking _stay(String id, {String status = 'accepted'}) => HomestayBooking(
    id: id, guestId: 'g', hostId: 'h', homeName: 'H', hostName: 'M', petId: 'x',
    petName: 'Bruno', ratePerNight: 900, checkIn: DateTime(2027, 1, 10),
    checkOut: DateTime(2027, 1, 13), nights: 3, subtotal: 2700, fee: 150, total: 2850,
    status: status);

void main() {
  test('HomestayBooking.paymentId round-trips and defaults to empty', () {
    final b = HomestayBooking.fromMap('hb1', _stay('hb1').toMap());
    expect(b.paymentId, '');
    final withId = HomestayBooking.fromMap('hb1', {..._stay('hb1').toMap(), 'paymentId': 'pay_x'});
    expect(withId.paymentId, 'pay_x');
  });

  test('markPaid sets status=paid + updatedAt + paymentId', () async {
    final repo = InMemoryHomestayBookingRepository();
    await repo.createHomestayBooking(_stay('hb1'));
    await repo.markPaid('hb1', 'pay_abc');
    final s = (await repo.watchMyHomestayBookings('g').first).single;
    expect(s.status, 'paid');
    expect(s.paymentId, 'pay_abc');
    expect(s.updatedAt, greaterThan(0));
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (`paymentId`/`markPaid` don't exist)

Run: `flutter test test/data/homestay_pay_test.dart`

- [ ] **Step 3: Add `paymentId` to the model** (`lib/data/models/homestay_booking.dart`)

- Field declaration: change `final String id, guestId, hostId, homeName, hostName, petId, petName, note, status;` to add `paymentId`:
  ```dart
  final String id, guestId, hostId, homeName, hostName, petId, petName, note, status, paymentId;
  ```
- Constructor: add `this.paymentId = '',` after `this.note = '',`.
- `toMap()`: add `'paymentId': paymentId,` after `'note': note,`.
- `fromMap`: add `paymentId: (m['paymentId'] ?? '') as String,` after the `note:` line.

- [ ] **Step 4: Add `markPaid` to the interface** (`lib/data/repositories/homestay_booking_repository.dart`)

Add to the abstract interface (after `cancelStay`):
```dart
  Future<void> markPaid(String id, String paymentId);
```

- [ ] **Step 5: Implement in the Firestore repo** (`firestore_homestay_booking_repository.dart`)

Add after `cancelStay`:
```dart
  @override
  Future<void> markPaid(String id, String paymentId) => _col.doc(id).update({
        'status': 'paid',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'paymentId': paymentId,
      });
```

- [ ] **Step 6: Implement in the fake** (`test/support/fakes.dart`, `InMemoryHomestayBookingRepository`)

Add after `cancelStay`:
```dart
  @override
  Future<void> markPaid(String id, String paymentId) async {
    final i = _bookings.indexWhere((b) => b.id == id);
    if (i == -1) return;
    _bookings[i] = HomestayBooking.fromMap(id, {..._bookings[i].toMap(),
        'status': 'paid', 'updatedAt': DateTime.now().millisecondsSinceEpoch, 'paymentId': paymentId});
    _controller.add(List.of(_bookings));
  }
```

- [ ] **Step 7: Run the test + existing homestay model/repo tests — expect PASS**

Run: `flutter test test/data/homestay_pay_test.dart test/data/homestay_booking_test.dart test/data/homestay_booking_repository_test.dart test/data/booking_transitions_test.dart`

- [ ] **Step 8: `flutter analyze` clean + full suite green, then commit**

Run: `flutter analyze && flutter test`
```bash
git add lib/data/models/homestay_booking.dart lib/data/repositories/homestay_booking_repository.dart lib/data/repositories/firebase/firestore_homestay_booking_repository.dart test/support/fakes.dart test/data/homestay_pay_test.dart
git commit -m "feat: HomestayBooking.paymentId + markPaid transition (accepted -> paid)"
```

---

### Task 2: `booking_lifecycle.dart` — `awaitingPayment` phase, `stayPhase` rework, `canPay`

**Files:**
- Modify: `lib/data/models/booking_lifecycle.dart`
- Modify: `test/data/booking_lifecycle_test.dart` (rewrite 2 stay tests, add new ones)

**Interfaces:**
- Consumes: `HomestayBooking.status` (incl. `'paid'` from Task 1).
- Produces: `BookingPhase.awaitingPayment` (label `'Pay to confirm'`); reworked `stayPhase`; `bool canPay(HomestayBooking b, DateTime now)`. `canCancelStay`/`canRate`/`servicePhase` unchanged.

- [ ] **Step 1: Update the lifecycle tests** (`test/data/booking_lifecycle_test.dart`)

Replace the two tests at "accepted is upcoming…" / "accepted past checkout is completed" (the `stayPhase` group) with:
```dart
    test('accepted before check-in is awaitingPayment', () =>
        expect(stayPhase(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 21)), _now),
            BookingPhase.awaitingPayment));
    test('accepted past check-in (never paid) is expired', () =>
        expect(stayPhase(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 18)), _now),
            BookingPhase.expired));
    test('paid is upcoming up to and including checkout day', () =>
        expect(stayPhase(_stay(status: 'paid', checkIn: DateTime(2026, 7, 15), checkOut: DateTime(2026, 7, 19)), _now),
            BookingPhase.upcoming));
    test('paid past checkout is completed', () =>
        expect(stayPhase(_stay(status: 'paid', checkIn: DateTime(2026, 7, 10), checkOut: DateTime(2026, 7, 18)), _now),
            BookingPhase.completed));
```
Add a new `group('canPay + paid cancel', ...)` after the permissions group:
```dart
  group('canPay + paid no-cancel', () {
    test('canPay only for accepted before check-in', () {
      expect(canPay(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 20)), _now), isTrue);
      expect(canPay(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 19)), _now), isTrue); // check-in today ok
      expect(canPay(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 18)), _now), isFalse); // past
      expect(canPay(_stay(status: 'requested', checkIn: DateTime(2026, 7, 20)), _now), isFalse);
      expect(canPay(_stay(status: 'paid', checkIn: DateTime(2026, 7, 20)), _now), isFalse);
    });
    test('a paid stay is not cancellable', () {
      expect(canCancelStay(_stay(status: 'paid', checkIn: DateTime(2026, 7, 25)), _now), isFalse);
    });
  });
```
(The `_stay` helper already defaults `status: 'requested'` and takes `status`/`checkIn`/`checkOut` — no helper change needed. `_now` is `DateTime(2026, 7, 19, 14, 30)`.)

- [ ] **Step 2: Run it — expect FAIL** (`awaitingPayment`/`canPay` don't exist; paid cases wrong)

Run: `flutter test test/data/booking_lifecycle_test.dart`

- [ ] **Step 3: Implement in `booking_lifecycle.dart`**

Add `awaitingPayment` to the enum (between `pending` and `upcoming`):
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
```
Replace `stayPhase` with:
```dart
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
```
Add `canPay` (after `canCancelStay`, which stays unchanged):
```dart
bool canPay(HomestayBooking b, DateTime now) =>
    b.status == 'accepted' && !_day(b.checkIn).isBefore(_day(now));
```

- [ ] **Step 4: Run the lifecycle test — expect PASS**

Run: `flutter test test/data/booking_lifecycle_test.dart`

- [ ] **Step 5: Run the full suite — expect the two migrated screen tests to now FAIL**

Run: `flutter test`
Expected: `test/features/my_bookings_screen_test.dart` fails — its two `status: 'accepted'` stay fixtures with past dates were relying on `accepted`→`completed`→Rate; under the new semantics they're `expired`. **This is expected and fixed in Task 5** (migrate those fixtures to `status: 'paid'`). Do NOT fix them here — Task 2 owns only the pure lifecycle. Note the failing test names in your report so Task 5 addresses them. All OTHER tests must pass.

**Sequencing note for the controller:** because Task 2 knowingly leaves `my_bookings_screen_test.dart` red (fixed in Task 5), commit Task 2 with the lifecycle test green and that one screen test red, OR fold the two-line fixture migration into Task 2. **This plan folds it into Task 2 Step 6** so every task ends fully green.

- [ ] **Step 6: Migrate the two stale fixtures now** (`test/features/my_bookings_screen_test.dart`)

Change both occurrences of `..., status: 'accepted'));` (the homestay fixtures at ~line 30 and ~line 67) to `..., status: 'paid'));`. These stays have past dates and the tests assert Rate — under the new lifecycle a completed rateable stay must be `paid`, not `accepted`. Re-run: `flutter test test/features/my_bookings_screen_test.dart` → PASS.

- [ ] **Step 7: `flutter analyze` clean + full suite green, then commit**

Run: `flutter analyze && flutter test`
```bash
git add lib/data/models/booking_lifecycle.dart test/data/booking_lifecycle_test.dart test/features/my_bookings_screen_test.dart
git commit -m "feat: awaitingPayment phase + canPay; accepted stays await payment, paid confirms"
```

---

### Task 3: Firestore rules — the guest pay transition + emulator matrix

**Files:**
- Modify: `firestore.rules` (the `homestayBookings` `update` rule)
- Modify: `integration_test/firebase_repos_test.dart` (extend the homestay matrix test)

**Interfaces:**
- Consumes: `markPaid` (Task 1); `acceptRequest` (existing).
- Produces: rules allowing guest `accepted → paid` with `paymentId`. Deploy happens in Task 7.

- [ ] **Step 1: Replace the `homestayBookings` update rule** (`firestore.rules`)

Replace the current `allow update: …` block inside `match /homestayBookings/{id}` with:
```
      allow update: if request.auth != null && (
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
          || ( resource.data.guestId == request.auth.uid
            && resource.data.status == 'accepted'
            && request.resource.data.status == 'paid'
            && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt', 'paymentId'])
          )
        );
```
(`create` and `allow delete: if false;` unchanged.)

- [ ] **Step 2: Extend the homestay matrix test** (`integration_test/firebase_repos_test.dart`)

Find the test `'booking lifecycle transitions obey the rules matrix (real Firestore emulators)'`. After the block where the host accepts the stay (`stays.acceptRequest(stayId)` → the doc is now `accepted`, host signed in), add — still as host — a denial, then switch to guest and pay:
```dart
    // Host cannot mark the stay paid (only the guest pays).
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update(
            {'status': 'paid', 'updatedAt': 3, 'paymentId': 'pay_h'}),
        throwsA(isA<FirebaseException>()));

    // Guest pays the accepted stay: accepted -> paid with a paymentId.
    await auth.signOut();
    await auth.signIn(email: 'lg_$stamp@x.com', password: 'secret1');
    await stays.markPaid(stayId, 'pay_ok');
    final paid = (await stays.watchMyHomestayBookings(guest.uid).firstWhere(
            (l) => l.any((s) => s.id == stayId && s.status == 'paid')))
        .firstWhere((s) => s.id == stayId);
    expect(paid.paymentId, 'pay_ok');
    expect(paid.updatedAt, greaterThan(0));

    // A paid stay can no longer be cancelled by the guest (no matching branch).
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update({'status': 'cancelled', 'updatedAt': 4}),
        throwsA(isA<FirebaseException>()));
    // The pay branch cannot smuggle an extra field.
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update(
            {'status': 'paid', 'total': 1, 'updatedAt': 5, 'paymentId': 'p'}),
        throwsA(isA<FirebaseException>()));
```
**Important:** this replaces the *old* portion of the test that had the guest cancel the accepted stay (the stay is now consumed by the pay path instead). If the existing test later references this `stayId` as `cancelled`, remove those now-contradictory lines; the service-booking portion of the matrix test is unaffected. Read the surrounding test and adjust so the stay's terminal state in this test is `paid`, not `cancelled`. Add a SEPARATE fresh stay earlier if you need to still assert the guest-cancel-of-accepted arrow (create a second requested stay, host-accept it, guest-cancel it) — keep that coverage.

- [ ] **Step 3: Run against the emulators** (loads local `firestore.rules`)

```bash
npm --prefix functions run build   # (functions unchanged, but the emulator loads compiled fns; harmless)
firebase emulators:start --only auth,firestore --project pet-aggregator-app
flutter test integration_test/firebase_repos_test.dart -d emulator-5554
```
Expected: all pass, including the new pay rows. Stop the emulators after. **If no Android emulator is available in this environment**, complete Steps 1–2, run `flutter analyze` + full unit `flutter test` (the integration file isn't in the unit suite), commit, and report DONE_WITH_CONCERNS deferring the emulator run to Task 7 — same convention as prior slices.

- [ ] **Step 4: `flutter analyze` clean, then commit** (deploy is Task 7)

```bash
git add firestore.rules integration_test/firebase_repos_test.dart
git commit -m "feat: rules allow the guest accepted->paid transition (+ emulator matrix)"
```

---

### Task 4: `HomestayPaymentScreen` + route

**Files:**
- Create: `lib/features/homestay/homestay_payment_screen.dart`
- Modify: `lib/core/router/routes.dart` (add `homestayPayment`)
- Modify: `lib/core/router/app_router.dart` (route + `_protected`)
- Test: `test/features/homestay_payment_test.dart` (create)

**Interfaces:**
- Consumes: `paymentServiceProvider`, `PaymentService.payForBooking`, `PaymentException`/`PaymentErrorType`, `FakePaymentService` (Slice 11); `homestayBookingRepositoryProvider.markPaid` (Task 1).
- Produces: `HomestayPaymentScreen({HomestayBooking? stay})`; `Routes.homestayPayment = '/homestay-payment'`.

- [ ] **Step 1: Add the route constant** — in `lib/core/router/routes.dart`, after `hostAccepted`:
```dart
  static const homestayPayment = '/homestay-payment';
```

- [ ] **Step 2: Write the failing flow tests**

```dart
// test/features/homestay_payment_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/data/services/payment_service.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

HomestayBooking _accepted(String uid) => HomestayBooking(
    id: 'hb1', guestId: uid, hostId: 'host1', homeName: "Meera's Home", hostName: 'Meera Iyer',
    petId: 'p1', petName: 'Bruno', ratePerNight: 900, checkIn: DateTime.now().add(const Duration(days: 5)),
    checkOut: DateTime.now().add(const Duration(days: 8)), nights: 3, subtotal: 2700, fee: 150,
    total: 2850, status: 'accepted');

class _FailOnceHomestayRepo extends InMemoryHomestayBookingRepository {
  int _left = 1;
  @override
  Future<void> markPaid(String id, String paymentId) {
    if (_left > 0) { _left--; throw Exception('write-failed'); }
    return super.markPaid(id, paymentId);
  }
}

Future<(InMemoryHomestayBookingRepository, FakePaymentService)> _pump(WidgetTester tester,
    {FakePaymentService? payments, InMemoryHomestayBookingRepository? repo}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final uid = auth.currentUser!.uid;
  final r = repo ?? InMemoryHomestayBookingRepository();
  await r.createHomestayBooking(_accepted(uid));
  final p = payments ?? FakePaymentService.success();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    homestayBookingRepositoryProvider.overrideWithValue(r),
    paymentServiceProvider.overrideWithValue(p),
    proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
  ], initialLocation: Routes.homestayPayment, extra: _accepted(uid));
  await tester.pumpAndSettle();
  return (r, p);
}

void main() {
  testWidgets('shows the honest summary (home, host, nights, total)', (tester) async {
    await _pump(tester);
    expect(find.text("Meera's Home"), findsOneWidget);
    expect(find.text('🔒 Secured by Razorpay — UPI, cards & netbanking'), findsOneWidget);
    expect(find.text('Pay ₹2850'), findsOneWidget);
  });

  testWidgets('success: charged the total, marks paid with paymentId, navigates', (tester) async {
    final (repo, payments) = await _pump(tester);
    await tester.tap(find.text('Pay ₹2850'));
    await tester.pumpAndSettle();
    expect(payments.chargedAmounts, [2850]);
    final s = (await repo.watchMyHomestayBookings('uid_me@x.com').first).single;
    expect(s.status, 'paid');
    expect(s.paymentId, 'pay_fake123');
  });

  testWidgets('cancelled: not paid, honest snackbar, button idle', (tester) async {
    final (repo, _) = await _pump(tester,
        payments: FakePaymentService(error: const PaymentException(PaymentErrorType.cancelled, 'x')));
    await tester.tap(find.text('Pay ₹2850'));
    await tester.pumpAndSettle();
    expect(find.text("Payment cancelled — you haven't been charged."), findsOneWidget);
    expect((await repo.watchMyHomestayBookings('uid_me@x.com').first).single.status, 'accepted');
  });

  testWidgets('unverified: not paid, snackbar carries the payment id', (tester) async {
    final (repo, _) = await _pump(tester,
        payments: FakePaymentService(
            error: const PaymentException(PaymentErrorType.unverified, 'x', paymentId: 'pay_z9')));
    await tester.tap(find.text('Pay ₹2850'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pay_z9'), findsOneWidget);
    expect((await repo.watchMyHomestayBookings('uid_me@x.com').first).single.status, 'accepted');
  });

  testWidgets('write-fails-after-pay: Retry saving marks paid without a second charge', (tester) async {
    final repo = _FailOnceHomestayRepo();
    final (_, payments) = await _pump(tester, repo: repo);
    await tester.tap(find.text('Pay ₹2850'));
    await tester.pumpAndSettle();
    expect(find.text('Retry saving'), findsOneWidget);
    await tester.tap(find.text('Retry saving'));
    await tester.pumpAndSettle();
    expect(payments.chargedAmounts, [2850]); // one charge across both taps
    expect((await repo.watchMyHomestayBookings('uid_me@x.com').first).single.status, 'paid');
  });
}
```

- [ ] **Step 3: Run it — expect FAIL** (screen + route don't exist)

Run: `flutter test test/features/homestay_payment_test.dart`

- [ ] **Step 4: Create the screen** (`lib/features/homestay/homestay_payment_screen.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/repositories/providers.dart';
import '../../data/services/payment_service.dart';

enum _PayPhase { idle, opening, verifying, saving, retrySave }

class HomestayPaymentScreen extends ConsumerStatefulWidget {
  final HomestayBooking? stay;
  const HomestayPaymentScreen({super.key, this.stay});
  @override
  ConsumerState<HomestayPaymentScreen> createState() => _HomestayPaymentScreenState();
}

class _HomestayPaymentScreenState extends ConsumerState<HomestayPaymentScreen> {
  _PayPhase _phase = _PayPhase.idle;
  PaymentResult? _paid; // kept across a failed markPaid so retry never re-charges

  bool get _busy =>
      _phase == _PayPhase.opening || _phase == _PayPhase.verifying || _phase == _PayPhase.saving;

  String _label(int total) => switch (_phase) {
        _PayPhase.idle => 'Pay ₹$total',
        _PayPhase.opening => 'Opening…',
        _PayPhase.verifying => 'Verifying…',
        _PayPhase.saving => 'Saving…',
        _PayPhase.retrySave => 'Retry saving',
      };

  Future<void> _pay(HomestayBooking stay) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_paid == null) {
      setState(() => _phase = _PayPhase.opening);
      try {
        _paid = await ref.read(paymentServiceProvider).payForBooking(
              amountRupees: stay.total,
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
      if (!mounted) return;
    }
    setState(() => _phase = _PayPhase.saving);
    final paid = _paid!;
    try {
      await ref.read(homestayBookingRepositoryProvider).markPaid(stay.id, paid.paymentId);
      if (mounted) context.go(Routes.bookings);
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _PayPhase.retrySave);
      messenger.showSnackBar(_snack('Payment received (id ${paid.paymentId}) but saving the '
          'booking failed — try again or contact support.'));
    }
  }

  SnackBar _snack(String message) => SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final stay = widget.stay;
    if (stay == null) {
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
                    _row(c, 'Home', stay.homeName),
                    _row(c, 'Host', stay.hostName),
                    _row(c, 'Dates',
                        '${HomestayBooking.fmtDay(stay.checkIn)} → ${HomestayBooking.fmtDay(stay.checkOut)}'),
                    _row(c, 'Nights', '${stay.nights}'),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Container(height: 1, color: c.border)),
                    _row(c, 'Subtotal', '₹${stay.subtotal}'),
                    _row(c, 'Service fee', '₹${stay.fee}'),
                    _row(c, 'Total', '₹${stay.total}', bold: true),
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
                Text('₹${stay.total}', style: PgText.poppins(20, FontWeight.w800, color: c.text)),
              ]),
              const SizedBox(width: 14),
              Expanded(
                  child: GestureDetector(
                      onTap: _busy ? null : () => _pay(stay),
                      child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [c.brand, c.brand2]),
                              borderRadius: BorderRadius.circular(16)),
                          child: Text(_label(stay.total),
                              style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white))))),
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

- [ ] **Step 5: Wire the route** (`lib/core/router/app_router.dart`)

Add import: `import '../../features/homestay/homestay_payment_screen.dart';`
Add `Routes.homestayPayment` to the `_protected` set (next to `Routes.hostRequest, Routes.hostAccepted`).
Add the route (near the other homestay routes):
```dart
      GoRoute(path: Routes.homestayPayment, builder: (_, state) =>
          HomestayPaymentScreen(stay: state.extra as HomestayBooking?)),
```

- [ ] **Step 6: Run the flow tests + full suite — expect PASS**

Run: `flutter test test/features/homestay_payment_test.dart && flutter test`

- [ ] **Step 7: `flutter analyze` clean, then commit**

```bash
git add lib/features/homestay/homestay_payment_screen.dart lib/core/router/routes.dart lib/core/router/app_router.dart test/features/homestay_payment_test.dart
git commit -m "feat: HomestayPaymentScreen - pay an accepted stay to confirm (markPaid)"
```

---

### Task 5: My-bookings row — "Pay to confirm" + paid "Contact host to cancel"

**Files:**
- Modify: `lib/features/bookings/my_bookings_screen.dart` (`_MyBookingsTab` stays loop + `_MyBookingRow`)
- Test: `test/features/homestay_pay_row_test.dart` (create)

**Interfaces:**
- Consumes: `canPay`, `stayPhase`, `BookingPhase` (Task 2); `Routes.homestayPayment` (Task 4).
- Produces: the row's Pay/Contact-host affordances.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/homestay_pay_row_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

HomestayBooking _stay(String uid, {required String status, int checkInDays = 5}) => HomestayBooking(
    id: 'hb1', guestId: uid, hostId: 'host1', homeName: "Meera's Home", hostName: 'Meera',
    petId: 'p1', petName: 'Bruno', ratePerNight: 900,
    checkIn: DateTime.now().add(Duration(days: checkInDays)),
    checkOut: DateTime.now().add(Duration(days: checkInDays + 3)),
    nights: 3, subtotal: 2700, fee: 150, total: 2850, status: status);

Future<void> _pump(WidgetTester tester, HomestayBooking stay) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final repo = InMemoryHomestayBookingRepository();
  await repo.createHomestayBooking(stay);
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    homestayBookingRepositoryProvider.overrideWithValue(repo),
    bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
  ], initialLocation: Routes.bookings);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('accepted stay shows Pay to confirm + Cancel; Pay opens payment', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'accepted'));
    expect(find.text('Pay to confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Pay to confirm'), findsOneWidget);
    await tester.tap(find.text('Pay to confirm'));
    await tester.pumpAndSettle();
    expect(find.text('🔒 Secured by Razorpay — UPI, cards & netbanking'), findsOneWidget); // payment screen
  });

  testWidgets('paid/upcoming stay shows no Cancel, shows Contact host to cancel', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    await _pump(tester, _stay(uid, status: 'paid'));
    expect(find.text('Contact host to cancel'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Pay to confirm'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `flutter test test/features/homestay_pay_row_test.dart`

- [ ] **Step 3: Thread `canPay`/pay/contact-host into the stays loop** (`_MyBookingsTab.build`, the `for (final s in stays)` block)

In the stays loop, add the three new params. `stayPhase(s, now)` is a cheap pure function, so calling it twice (for `phase:` and `showContactHost:`) is simplest — no IIFE or local needed:
```dart
          for (final s in stays)
            _MyBookingRow(
              emoji: '🏡',
              name: s.homeName,
              detail: '${s.hostName} · ${HomestayBooking.fmtDay(s.checkIn)} · ${s.nights} nights',
              phase: stayPhase(s, now),
              rated: rated.contains(s.id),
              canCancel: canCancelStay(s, now),
              canPay: canPay(s, now),
              showContactHost: stayPhase(s, now) == BookingPhase.upcoming,
              onPay: () => context.push(Routes.homestayPayment, extra: s),
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
(Keep the existing `onCancel`/`onRate` bodies exactly as they were — only the three new params are added.)

For the **services** loop's `_MyBookingRow`, add `canPay: false, onPay: null, showContactHost: false,` (services never pay-to-confirm).

- [ ] **Step 4: Extend `_MyBookingRow`** (add the params + render)

Change the constructor/fields:
```dart
class _MyBookingRow extends StatelessWidget {
  final String emoji, name, detail;
  final BookingPhase phase;
  final bool rated, canCancel, canPay, showContactHost;
  final VoidCallback onRate, onCancel;
  final VoidCallback? onPay;
  const _MyBookingRow(
      {required this.emoji, required this.name, required this.detail, required this.phase,
      required this.rated, required this.canCancel, required this.onRate, required this.onCancel,
      this.canPay = false, this.onPay, this.showContactHost = false});
```
In the action `Column` (after the `rated`/`canRate` else-chain, before the `canCancel` block), insert the Pay affordance and the contact-host note:
```dart
          ] else if (canPay) ...[
            const SizedBox(height: 6),
            GestureDetector(
                onTap: onPay,
                child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [c.brand, c.brand2]),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('Pay to confirm',
                        style: PgText.poppins(12.5, FontWeight.w700, color: Colors.white)))),
          ],
          if (canCancel) ...[
            const SizedBox(height: 6),
            GestureDetector(
                onTap: onCancel,
                child: Text('Cancel',
                    style: PgText.inter(12.5, FontWeight.w600, color: c.muted))),
          ],
          if (showContactHost) ...[
            const SizedBox(height: 6),
            Text('Contact host to cancel',
                style: PgText.inter(11.5, FontWeight.w500, color: c.faint)),
          ],
```
The full else-chain therefore reads: `if (rated) … else if (canRate(phase)) … else if (canPay) …`, then the independent `if (canCancel)` and `if (showContactHost)` blocks. (An `accepted` stay: not rated, not canRate, canPay → Pay to confirm; plus canCancel → Cancel. A `paid`/upcoming stay: none of rated/canRate/canPay/canCancel → showContactHost note.)

- [ ] **Step 5: Run the row tests + the bookings-hub + my-bookings tests + full suite — expect PASS**

Run: `flutter test test/features/homestay_pay_row_test.dart test/features/my_bookings_screen_test.dart test/features/bookings_hub_test.dart && flutter test`

- [ ] **Step 6: `flutter analyze` clean, then commit**

```bash
git add lib/features/bookings/my_bookings_screen.dart test/features/homestay_pay_row_test.dart
git commit -m "feat: My-bookings - Pay to confirm on accepted stays, contact-host note on paid"
```

---

### Task 6: Host notification when a stay is paid

**Files:**
- Modify: `lib/features/notifications/notification_item.dart` (`receivedStays` loop)
- Test: `test/features/notifications_paid_test.dart` (create)

**Interfaces:**
- Consumes: `receivedStays` list already threaded into `buildNotifications` (Slice 10); `HomestayBooking.status == 'paid'`.
- Produces: a `paid` host notification item.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/notifications_paid_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/features/notifications/notification_item.dart';

HomestayBooking _stay({required String status, int createdAt = 10, int updatedAt = 0}) =>
    HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h', homeName: "Meera's Home", hostName: 'Meera',
        petId: 'x', petName: 'Bruno', ratePerNight: 900, checkIn: DateTime(2027, 1, 10),
        checkOut: DateTime(2027, 1, 13), nights: 3, subtotal: 2700, fee: 150, total: 2850,
        status: status, createdAt: createdAt, updatedAt: updatedAt);

void main() {
  test('host sees a confirmed-and-paid item for a paid received stay', () {
    final items = buildNotifications(myUid: 'h', seenAt: 0, chats: const [], reviews: const [],
        bookings: const [], homestays: const [],
        receivedStays: [_stay(status: 'paid', updatedAt: 500)]);
    final item = items.singleWhere((n) => n.title.contains('confirmed & paid'));
    expect(item.title, "Bruno's stay is confirmed & paid");
    expect(item.timestamp, 500);
    expect(item.route, Routes.bookings);
    expect(item.extra, 1);
    expect(item.read, isFalse);
  });

  test('a non-paid received stay produces no confirmed-and-paid item', () {
    final items = buildNotifications(myUid: 'h', seenAt: 0, chats: const [], reviews: const [],
        bookings: const [], homestays: const [],
        receivedStays: [_stay(status: 'accepted', updatedAt: 500)]);
    expect(items.where((n) => n.title.contains('confirmed & paid')), isEmpty);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `flutter test test/features/notifications_paid_test.dart`

- [ ] **Step 3: Add the `paid` branch** (`notification_item.dart`, the `for (final s in receivedStays)` loop)

In that loop, alongside the existing `if (s.status == 'requested')` / `else if (s.status == 'cancelled')`, add:
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
(Insert as an `else if` in the existing chain — the loop currently is `if (requested) … else if (cancelled) …`; add this as a third `else if`.)

- [ ] **Step 4: Run the new test + existing notification tests + full suite — expect PASS**

Run: `flutter test test/features/notifications_paid_test.dart test/features/notifications_lifecycle_test.dart test/features/notifications_builder_test.dart && flutter test`

- [ ] **Step 5: `flutter analyze` clean, then commit**

```bash
git add lib/features/notifications/notification_item.dart test/features/notifications_paid_test.dart
git commit -m "feat: host notification when a stay is paid & confirmed"
```

---

### Task 7: Final verification + rules deploy + on-device pass

**Files:** none (fixes only if verification finds problems).

- [ ] **Step 1: Full local verification**

```bash
flutter analyze              # No issues found!
flutter test                 # all pass
flutter build apk --debug    # succeeds
```

- [ ] **Step 2: Emulator suites** (mandatory here if Task 3's run was deferred)

```bash
firebase emulators:start --only auth,firestore,functions --project pet-aggregator-app
flutter test integration_test/firebase_repos_test.dart -d emulator-5554   # incl. the new pay matrix rows
```
Kill the emulators after; confirm ports freed.

- [ ] **Step 3: Deploy the rules** (owner-run if the classifier blocks the assistant)

```bash
firebase deploy --only firestore:rules --project pet-aggregator-app
```
Expected: `✔ Deploy complete!`

- [ ] **Step 4: On-device pass** (`flutter run -d emulator-5554`, two accounts; needs the owner's Razorpay Functions from Slice 11 deployed — if not yet done, this step waits on that)

1. Guest requests a stay; host accepts.
2. Guest's My-bookings shows the stay with **Pay to confirm** (chip "Pay to confirm") + Cancel.
3. Tap Pay to confirm → the honest homestay summary → real Razorpay test checkout → pay with `success@razorpay` → Verifying… → back on My-bookings, the stay now reads **Upcoming**, no Cancel (shows "Contact host to cancel"); Firestore doc `status:'paid'` with a `pay_…` `paymentId`.
4. The host's notification feed shows "Bruno's stay is confirmed & paid".
5. Back out of checkout / fail it → stay stays accepted, nothing charged, honest snackbar.

- [ ] **Step 5: Commit any verification fixes** (none expected).

---

## Self-review notes (checked against the spec)

- Spec coverage: model+repo `markPaid` (T1), lifecycle awaitingPayment/canPay + stayPhase (T2), rules + emulator matrix (T3), HomestayPaymentScreen + route (T4), My-bookings Pay/contact-host + fixture migration (T2 step 6 for lifecycle-test fixtures, T5 for the row) (T5), paid notification (T6), verify/deploy/on-device (T7). ReceivedTab needs no change — its ledger already renders `stayPhase`, so an accepted stay auto-shows the "Pay to confirm" chip.
- Type consistency: `markPaid(id, paymentId)`, `HomestayBooking.paymentId`, `BookingPhase.awaitingPayment` (label `'Pay to confirm'`), `canPay(stay, now)`, `Routes.homestayPayment`, `HomestayPaymentScreen({stay})`, `_MyBookingRow(… canPay, onPay, showContactHost)` — identical across tasks and tests.
- The `accepted`→`awaitingPayment/expired` semantic change breaks exactly two lifecycle tests (rewritten in T2) and two my_bookings_screen_test fixtures (migrated to `paid` in T2 step 6). No other test seeds `accepted` expecting completed (grep-verified: only `my_bookings_screen_test.dart`; `notifications_lifecycle_test.dart`'s accepted cases test the guest-side "accepted your request" item, which is unchanged).
- Copy strings (`Pay to confirm`, `Contact host to cancel`, `{petName}'s stay is confirmed & paid`, and all reused Slice-11 payment strings) are verbatim across plan and tests.
- SDK isolation preserved: the new screen imports only `payment_service.dart` (the seam), never `razorpay_flutter`/`cloud_functions`.
