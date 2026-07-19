# Pawgo Slice 10: Booking Lifecycle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the booking loop — hosts accept/decline homestay requests, guests/parents cancel upcoming bookings, completion is derived from dates, every booking shows an honest status, and Rate unlocks only after completion.

**Architecture:** Thin writes + derived status. Only human decisions are written (`accepted`/`declined`/`cancelled`, each updating exactly `status`+`updatedAt`); a pure module `booking_lifecycle.dart` derives phases (`completed`, `expired`, …) from dates with `now` injected. The existing `MyBookingsScreen` becomes a two-tab hub (My bookings / Received) in a new `lib/features/bookings/` folder. Rules unlock `update` along the valid arrows only.

**Tech Stack:** Flutter stable / Dart ^3.12.2, `cloud_firestore`, `flutter_riverpod` 3.x, `go_router`. No new packages.

**Spec:** `docs/superpowers/specs/2026-07-19-pawgo-booking-lifecycle-design.md`.

## Global Constraints

- Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **All date comparisons are date-only (calendar days, device-local).** No lifecycle function may call `DateTime.now()` internally — callers pass `now`; tests inject fixed dates. Widget tests build fixtures **relative to `DateTime.now()`** (never hardcoded 2026 dates — they rot).
- Transitions write **exactly** `{'status': …, 'updatedAt': <client millis>}` (client `DateTime.now().millisecondsSinceEpoch`, matching the repo's `createdAt` convention). `fromMap` reads `updatedAt` defensively: `(m['updatedAt'] is int) ? … : 0`.
- Stored statuses only: homestay `requested → accepted | declined` (host), `requested/accepted → cancelled` (guest); service `confirmed → cancelled` (parent). **`completed` and `expired` are never stored.**
- Legacy service bookings (no `date` field) are grandfathered: phase `completed`, rateable, never cancellable.
- Riverpod 3.x: `.value` (not `valueOrNull`); `Override` imports from `flutter_riverpod/misc.dart` in tests; screens use the `.value ?? const []` idiom; async handlers guard `context.mounted` after `await`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.
- Copy (exact strings): tabs `My bookings` / `Received`; chips `Pending / Upcoming / Completed / Declined / Cancelled / Expired`; empty received state `No bookings for your listing yet.`; error SnackBar `Couldn't update the booking — try again.`; cancel dialog title `Cancel this booking?`, body `This can't be undone.`, actions `Keep` / `Cancel booking`; decline dialog title `Decline this request?`, confirm `Decline`.

---

### Task 1: Model fields — `Booking.date` + `updatedAt`, `HomestayBooking.updatedAt`, ISO date written on create

**Files:**
- Modify: `lib/data/models/booking.dart`
- Modify: `lib/data/models/homestay_booking.dart`
- Modify: `lib/features/services/booking_screen.dart:39-43` (the `_continue` method)
- Test: `test/data/booking_status_fields_test.dart` (create)
- Test: `test/features/booking_date_wire_test.dart` (create)

**Interfaces:**
- Consumes: existing `Booking` / `HomestayBooking` models.
- Produces: `Booking.date` (`String`, ISO `yyyy-MM-dd`, default `''`), `Booking.updatedAt` (`int`, default 0), `HomestayBooking.updatedAt` (`int`, default 0), `static String Booking.isoDate(DateTime d)`.

- [ ] **Step 1: Write the failing model test**

```dart
// test/data/booking_status_fields_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

void main() {
  test('Booking.date + updatedAt round-trip; default empty/0; non-int degrades', () {
    final b = Booking(id: 'bk1', parentId: 'g', proId: 'p', proName: 'Aarav', petId: 'x',
        petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue 21 Jul', timeSlot: '5:00 PM', date: '2026-07-21', updatedAt: 9);
    final back = Booking.fromMap('bk1', b.toMap());
    expect(back.date, '2026-07-21');
    expect(back.updatedAt, 9);
    expect(Booking.fromMap('bk1', const {}).date, '');
    expect(Booking.fromMap('bk1', const {}).updatedAt, 0);
    expect(Booking.fromMap('bk1', const {'updatedAt': 'x'}).updatedAt, 0);
  });

  test('Booking.isoDate pads to yyyy-MM-dd', () {
    expect(Booking.isoDate(DateTime(2026, 7, 5)), '2026-07-05');
    expect(Booking.isoDate(DateTime(2026, 11, 23)), '2026-11-23');
  });

  test('HomestayBooking.updatedAt round-trips; default 0', () {
    final s = HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h', homeName: 'H',
        hostName: 'M', petId: 'x', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 7, 20), checkOut: DateTime(2026, 7, 23), nights: 3,
        subtotal: 2700, fee: 150, total: 2850, updatedAt: 7);
    expect(HomestayBooking.fromMap('hb1', s.toMap()).updatedAt, 7);
    expect(HomestayBooking.fromMap('hb1', {'checkIn': '2026-07-20', 'checkOut': '2026-07-23'}).updatedAt, 0);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (`date`/`updatedAt`/`isoDate` don't exist)

Run: `flutter test test/data/booking_status_fields_test.dart`

- [ ] **Step 3: Implement the model changes**

In `lib/data/models/booking.dart`:

```dart
class Booking {
  final String id, parentId, proId, proName, petId, petName;
  final ServiceType serviceType;
  final int rate, fee, total, createdAt, updatedAt;
  final String dateLabel, timeSlot, status, date; // date: ISO yyyy-MM-dd ('' = legacy booking)

  const Booking({
    this.id = '',
    required this.parentId, required this.proId, required this.proName,
    required this.petId, required this.petName, required this.serviceType,
    required this.rate, required this.fee, required this.total,
    required this.dateLabel, required this.timeSlot, this.status = 'confirmed',
    this.date = '', this.createdAt = 0, this.updatedAt = 0,
  });

  static int feeFor(int rate) => (rate * 0.1).round();

  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
```

Add to `toMap()` (after `'status': status,`):

```dart
        'date': date,
        'updatedAt': updatedAt,
```

Add to `fromMap` (after the `status:` line):

```dart
        date: (m['date'] ?? '') as String,
        updatedAt: (m['updatedAt'] is int) ? m['updatedAt'] as int : 0,
```

In `lib/data/models/homestay_booking.dart`: add `updatedAt` to the int fields (`final int ratePerNight, nights, subtotal, fee, total, createdAt, updatedAt;`), constructor (`this.updatedAt = 0,` after `this.createdAt = 0,`), `toMap()` (`'updatedAt': updatedAt,` after `'createdAt': createdAt,`), and `fromMap` (`updatedAt: (m['updatedAt'] is int) ? m['updatedAt'] as int : 0,` after the `createdAt:` line).

In `lib/features/services/booking_screen.dart` `_continue`, add `date:` to the Booking (the `_days[_dateIndex]` DateTime is already there):

```dart
    context.push(Routes.payment, extra: Booking(
      parentId: me.uid, proId: pro.uid, proName: pro.name, petId: pet.id, petName: pet.name,
      serviceType: pro.serviceType, rate: pro.rate, fee: fee, total: pro.rate + fee,
      dateLabel: _label(_days[_dateIndex]), timeSlot: _times[_timeIndex],
      date: Booking.isoDate(_days[_dateIndex])));
```

- [ ] **Step 4: Write the failing wire test** (the ISO date actually reaches the stored booking)

```dart
// test/features/booking_date_wire_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
    serviceType: ServiceType.walker, rate: 250, experienceYears: 4);

void main() {
  testWidgets('paying writes the booking with a machine-readable ISO date', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final bookings = InMemoryBookingRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets(uid))),
      bookingRepositoryProvider.overrideWithValue(bookings),
    ], initialLocation: Routes.booking, extra: _pro);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Continue to payment'));
    await tester.tap(find.text('Continue to payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pay ₹'));
    await tester.pumpAndSettle();

    final stored = (await bookings.watchMyBookings(uid).first).single;
    expect(stored.date, Booking.isoDate(DateTime.now())); // default selection = today
  });
}
```

- [ ] **Step 5: Run both test files + the existing model/booking tests — expect PASS**

Run: `flutter test test/data/booking_status_fields_test.dart test/features/booking_date_wire_test.dart test/data/booking_test.dart test/data/homestay_booking_test.dart test/data/booking_createdat_test.dart`

- [ ] **Step 6: `flutter analyze` clean, then commit**

```bash
git add lib/data/models/booking.dart lib/data/models/homestay_booking.dart lib/features/services/booking_screen.dart test/data/booking_status_fields_test.dart test/features/booking_date_wire_test.dart
git commit -m "feat: booking models carry an ISO date + updatedAt (date written on create)"
```

---

### Task 2: `booking_lifecycle.dart` — derived phases + permissions (pure)

**Files:**
- Create: `lib/data/models/booking_lifecycle.dart`
- Test: `test/data/booking_lifecycle_test.dart`

**Interfaces:**
- Consumes: `Booking` (`status`, `date`), `HomestayBooking` (`status`, `checkIn`, `checkOut`) from Task 1.
- Produces: `enum BookingPhase { pending, upcoming, completed, declined, cancelled, expired }` with a `String label` field (`'Pending'` … `'Expired'`); `BookingPhase servicePhase(Booking b, DateTime now)`; `BookingPhase stayPhase(HomestayBooking b, DateTime now)`; `bool canRate(BookingPhase p)`; `bool canCancelService(Booking b, DateTime now)`; `bool canCancelStay(HomestayBooking b, DateTime now)`; `bool canDecide(HomestayBooking b, DateTime now)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/booking_lifecycle_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/booking_lifecycle.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

final _now = DateTime(2026, 7, 19, 14, 30); // fixed "today" — time of day must not matter

Booking _svc({String status = 'confirmed', String date = ''}) => Booking(
    id: 'bk1', parentId: 'g', proId: 'p', proName: 'Aarav', petId: 'x', petName: 'Bruno',
    serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
    dateLabel: 'Tue', timeSlot: '5:00 PM', status: status, date: date);

HomestayBooking _stay({String status = 'requested', DateTime? checkIn, DateTime? checkOut}) =>
    HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h', homeName: 'H', hostName: 'M',
        petId: 'x', petName: 'Bruno', ratePerNight: 900,
        checkIn: checkIn ?? DateTime(2026, 7, 21), checkOut: checkOut ?? DateTime(2026, 7, 24),
        nights: 3, subtotal: 2700, fee: 150, total: 2850, status: status);

void main() {
  group('servicePhase', () {
    test('cancelled wins over any date', () =>
        expect(servicePhase(_svc(status: 'cancelled', date: '2026-07-25'), _now), BookingPhase.cancelled));
    test('legacy (no date) is completed', () =>
        expect(servicePhase(_svc(), _now), BookingPhase.completed));
    test('unparseable date behaves like legacy', () =>
        expect(servicePhase(_svc(date: 'garbage'), _now), BookingPhase.completed));
    test('today and tomorrow are upcoming', () {
      expect(servicePhase(_svc(date: '2026-07-19'), _now), BookingPhase.upcoming);
      expect(servicePhase(_svc(date: '2026-07-20'), _now), BookingPhase.upcoming);
    });
    test('yesterday is completed', () =>
        expect(servicePhase(_svc(date: '2026-07-18'), _now), BookingPhase.completed));
  });

  group('stayPhase', () {
    test('declined / cancelled map directly', () {
      expect(stayPhase(_stay(status: 'declined'), _now), BookingPhase.declined);
      expect(stayPhase(_stay(status: 'cancelled'), _now), BookingPhase.cancelled);
    });
    test('requested is pending up to and including check-in day', () {
      expect(stayPhase(_stay(checkIn: DateTime(2026, 7, 21)), _now), BookingPhase.pending);
      expect(stayPhase(_stay(checkIn: DateTime(2026, 7, 19)), _now), BookingPhase.pending);
    });
    test('requested past check-in is expired', () =>
        expect(stayPhase(_stay(checkIn: DateTime(2026, 7, 18)), _now), BookingPhase.expired));
    test('accepted is upcoming up to and including checkout day', () =>
        expect(stayPhase(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 15), checkOut: DateTime(2026, 7, 19)), _now),
            BookingPhase.upcoming));
    test('accepted past checkout is completed', () =>
        expect(stayPhase(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 10), checkOut: DateTime(2026, 7, 18)), _now),
            BookingPhase.completed));
  });

  group('permissions', () {
    test('canRate only when completed', () {
      expect(canRate(BookingPhase.completed), isTrue);
      for (final p in BookingPhase.values.where((p) => p != BookingPhase.completed)) {
        expect(canRate(p), isFalse);
      }
    });
    test('canCancelService: strictly before the date; never legacy or cancelled', () {
      expect(canCancelService(_svc(date: '2026-07-20'), _now), isTrue);
      expect(canCancelService(_svc(date: '2026-07-19'), _now), isFalse); // day-of
      expect(canCancelService(_svc(), _now), isFalse);                    // legacy
      expect(canCancelService(_svc(status: 'cancelled', date: '2026-07-25'), _now), isFalse);
    });
    test('canCancelStay: requested until expiry; accepted strictly before check-in', () {
      expect(canCancelStay(_stay(checkIn: DateTime(2026, 7, 19)), _now), isTrue);   // pending, check-in today
      expect(canCancelStay(_stay(checkIn: DateTime(2026, 7, 18)), _now), isFalse);  // expired
      expect(canCancelStay(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 20)), _now), isTrue);
      expect(canCancelStay(_stay(status: 'accepted', checkIn: DateTime(2026, 7, 19)), _now), isFalse); // starts today
      expect(canCancelStay(_stay(status: 'declined'), _now), isFalse);
    });
    test('canDecide: only live requests', () {
      expect(canDecide(_stay(checkIn: DateTime(2026, 7, 19)), _now), isTrue);
      expect(canDecide(_stay(checkIn: DateTime(2026, 7, 18)), _now), isFalse); // expired
      expect(canDecide(_stay(status: 'accepted'), _now), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (file doesn't exist)

Run: `flutter test test/data/booking_lifecycle_test.dart`

- [ ] **Step 3: Implement the pure module**

```dart
// lib/data/models/booking_lifecycle.dart
//
// Derived booking phases + permissions. Pure: no SDK imports, `now` injected.
// Only human decisions are ever stored ('accepted'/'declined'/'cancelled');
// 'completed' and 'expired' exist only here, derived from calendar dates.
import 'booking.dart';
import 'homestay_booking.dart';

enum BookingPhase {
  pending('Pending'),
  upcoming('Upcoming'),
  completed('Completed'),
  declined('Declined'),
  cancelled('Cancelled'),
  expired('Expired');

  final String label;
  const BookingPhase(this.label);
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

BookingPhase servicePhase(Booking b, DateTime now) {
  if (b.status == 'cancelled') return BookingPhase.cancelled;
  final d = DateTime.tryParse(b.date);
  if (d == null) return BookingPhase.completed; // legacy: no machine date, grandfathered
  return _day(d).isBefore(_day(now)) ? BookingPhase.completed : BookingPhase.upcoming;
}

BookingPhase stayPhase(HomestayBooking b, DateTime now) {
  switch (b.status) {
    case 'declined':
      return BookingPhase.declined;
    case 'cancelled':
      return BookingPhase.cancelled;
    case 'accepted':
      return _day(b.checkOut).isBefore(_day(now)) ? BookingPhase.completed : BookingPhase.upcoming;
    default: // 'requested'
      return _day(b.checkIn).isBefore(_day(now)) ? BookingPhase.expired : BookingPhase.pending;
  }
}

bool canRate(BookingPhase p) => p == BookingPhase.completed;

bool canCancelService(Booking b, DateTime now) {
  final d = DateTime.tryParse(b.date);
  return b.status == 'confirmed' && d != null && _day(now).isBefore(_day(d));
}

bool canCancelStay(HomestayBooking b, DateTime now) =>
    (b.status == 'requested' && !_day(b.checkIn).isBefore(_day(now))) ||
    (b.status == 'accepted' && _day(now).isBefore(_day(b.checkIn)));

bool canDecide(HomestayBooking b, DateTime now) =>
    b.status == 'requested' && !_day(b.checkIn).isBefore(_day(now));
```

- [ ] **Step 4: Run it — expect PASS**

Run: `flutter test test/data/booking_lifecycle_test.dart`

- [ ] **Step 5: `flutter analyze` clean, then commit**

```bash
git add lib/data/models/booking_lifecycle.dart test/data/booking_lifecycle_test.dart
git commit -m "feat: pure booking lifecycle phases + permissions (derived completion)"
```

---

### Task 3: Repositories — received streams + transitions (interfaces, Firestore impls, fakes, providers)

**Files:**
- Modify: `lib/data/repositories/booking_repository.dart`
- Modify: `lib/data/repositories/homestay_booking_repository.dart`
- Modify: `lib/data/repositories/firebase/firestore_booking_repository.dart`
- Modify: `lib/data/repositories/firebase/firestore_homestay_booking_repository.dart`
- Modify: `lib/data/repositories/providers.dart`
- Modify: `test/support/fakes.dart` (`InMemoryBookingRepository`, `InMemoryHomestayBookingRepository`)
- Test: `test/data/booking_transitions_test.dart` (create)

**Interfaces:**
- Consumes: models from Task 1.
- Produces: `BookingRepository.watchBookingsForPro(String proId)`, `BookingRepository.cancelBooking(String id)`; `HomestayBookingRepository.watchBookingsForHost(String hostId)`, `.acceptRequest(String id)`, `.declineRequest(String id)`, `.cancelStay(String id)`; providers `receivedServiceBookingsProvider` (`StreamProvider<List<Booking>>`) and `receivedStayBookingsProvider` (`StreamProvider<List<HomestayBooking>>`) that emit `const []` when the user has no pro/homestay listing. Received streams sort newest-first by `createdAt`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/booking_transitions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import '../support/fakes.dart';

Booking _svc(String id, {String parentId = 'g', String proId = 'p', int createdAt = 0}) => Booking(
    id: id, parentId: parentId, proId: proId, proName: 'Aarav', petId: 'x', petName: 'Bruno',
    serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
    dateLabel: 'Tue', timeSlot: '5:00 PM', date: '2027-01-10', createdAt: createdAt);

HomestayBooking _stay(String id, {String guestId = 'g', String hostId = 'h'}) => HomestayBooking(
    id: id, guestId: guestId, hostId: hostId, homeName: 'H', hostName: 'M', petId: 'x',
    petName: 'Bruno', ratePerNight: 900, checkIn: DateTime(2027, 1, 10),
    checkOut: DateTime(2027, 1, 13), nights: 3, subtotal: 2700, fee: 150, total: 2850);

void main() {
  test('watchBookingsForPro filters by proId, newest first', () async {
    final repo = InMemoryBookingRepository();
    await repo.createBooking(_svc('a', proId: 'me', createdAt: 1));
    await repo.createBooking(_svc('b', proId: 'me', createdAt: 2));
    await repo.createBooking(_svc('c', proId: 'other', createdAt: 3));
    final mine = await repo.watchBookingsForPro('me').first;
    expect(mine.map((b) => b.id).toList(), ['b', 'a']);
  });

  test('cancelBooking flips status + stamps updatedAt', () async {
    final repo = InMemoryBookingRepository();
    await repo.createBooking(_svc('a'));
    await repo.cancelBooking('a');
    final b = (await repo.watchMyBookings('g').first).single;
    expect(b.status, 'cancelled');
    expect(b.updatedAt, greaterThan(0));
  });

  test('watchBookingsForHost filters by hostId', () async {
    final repo = InMemoryHomestayBookingRepository();
    await repo.createHomestayBooking(_stay('s1', hostId: 'me'));
    await repo.createHomestayBooking(_stay('s2', hostId: 'other'));
    final mine = await repo.watchBookingsForHost('me').first;
    expect(mine.single.id, 's1');
  });

  test('accept / decline / cancel set status + updatedAt', () async {
    final repo = InMemoryHomestayBookingRepository();
    await repo.createHomestayBooking(_stay('s1'));
    await repo.acceptRequest('s1');
    var s = (await repo.watchMyHomestayBookings('g').first).firstWhere((x) => x.id == 's1');
    expect(s.status, 'accepted');
    expect(s.updatedAt, greaterThan(0));

    await repo.createHomestayBooking(_stay('s2'));
    await repo.declineRequest('s2');
    s = (await repo.watchMyHomestayBookings('g').first).firstWhere((x) => x.id == 's2');
    expect(s.status, 'declined');

    await repo.cancelStay('s1');
    s = (await repo.watchMyHomestayBookings('g').first).firstWhere((x) => x.id == 's1');
    expect(s.status, 'cancelled');
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (methods don't exist)

Run: `flutter test test/data/booking_transitions_test.dart`

- [ ] **Step 3: Extend the interfaces**

`lib/data/repositories/booking_repository.dart`:

```dart
import '../models/booking.dart';

abstract interface class BookingRepository {
  Future<void> createBooking(Booking booking);
  Stream<List<Booking>> watchMyBookings(String parentId);
  Stream<List<Booking>> watchBookingsForPro(String proId);
  Future<void> cancelBooking(String id);
}
```

`lib/data/repositories/homestay_booking_repository.dart`:

```dart
import '../models/homestay_booking.dart';

abstract interface class HomestayBookingRepository {
  Future<void> createHomestayBooking(HomestayBooking booking);
  Stream<List<HomestayBooking>> watchMyHomestayBookings(String guestId);
  Stream<List<HomestayBooking>> watchBookingsForHost(String hostId);
  Future<void> acceptRequest(String id);
  Future<void> declineRequest(String id);
  Future<void> cancelStay(String id);
}
```

- [ ] **Step 4: Extend the Firestore impls**

Add to `FirestoreBookingRepository`:

```dart
  @override
  Stream<List<Booking>> watchBookingsForPro(String proId) => _col
      .where('proId', isEqualTo: proId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Booking.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Future<void> cancelBooking(String id) => _col.doc(id).update({
        'status': 'cancelled',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
```

Add to `FirestoreHomestayBookingRepository`:

```dart
  @override
  Stream<List<HomestayBooking>> watchBookingsForHost(String hostId) => _col
      .where('hostId', isEqualTo: hostId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => HomestayBooking.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  Future<void> _setStatus(String id, String status) => _col.doc(id).update({
        'status': status,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

  @override
  Future<void> acceptRequest(String id) => _setStatus(id, 'accepted');

  @override
  Future<void> declineRequest(String id) => _setStatus(id, 'declined');

  @override
  Future<void> cancelStay(String id) => _setStatus(id, 'cancelled');
```

(No `orderBy` in the queries — a `where` + `orderBy` on different fields would need a composite index; the client-side sort avoids that.)

- [ ] **Step 5: Extend the in-memory fakes** (`test/support/fakes.dart`)

Add inside `InMemoryBookingRepository`:

```dart
  @override
  Stream<List<Booking>> watchBookingsForPro(String proId) async* {
    List<Booking> mine() => (_bookings.where((b) => b.proId == proId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    yield mine();
    yield* _controller.stream.map((_) => mine());
  }

  @override
  Future<void> cancelBooking(String id) async {
    final i = _bookings.indexWhere((b) => b.id == id);
    if (i == -1) return;
    _bookings[i] = Booking.fromMap(id, {..._bookings[i].toMap(),
        'status': 'cancelled', 'updatedAt': DateTime.now().millisecondsSinceEpoch});
    _controller.add(List.of(_bookings));
  }
```

Add inside `InMemoryHomestayBookingRepository`:

```dart
  @override
  Stream<List<HomestayBooking>> watchBookingsForHost(String hostId) async* {
    List<HomestayBooking> mine() => (_bookings.where((b) => b.hostId == hostId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    yield mine();
    yield* _controller.stream.map((_) => mine());
  }

  Future<void> _setStatus(String id, String status) async {
    final i = _bookings.indexWhere((b) => b.id == id);
    if (i == -1) return;
    _bookings[i] = HomestayBooking.fromMap(id, {..._bookings[i].toMap(),
        'status': status, 'updatedAt': DateTime.now().millisecondsSinceEpoch});
    _controller.add(List.of(_bookings));
  }

  @override
  Future<void> acceptRequest(String id) => _setStatus(id, 'accepted');

  @override
  Future<void> declineRequest(String id) => _setStatus(id, 'declined');

  @override
  Future<void> cancelStay(String id) => _setStatus(id, 'cancelled');
```

- [ ] **Step 6: Add the received providers** (`lib/data/repositories/providers.dart`, after `myHomestayBookingsProvider`)

```dart
final receivedServiceBookingsProvider = StreamProvider<List<Booking>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null || ref.watch(currentProProvider).value == null) {
    return Stream.value(const []);
  }
  return ref.watch(bookingRepositoryProvider).watchBookingsForPro(user.uid);
});

final receivedStayBookingsProvider = StreamProvider<List<HomestayBooking>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null || ref.watch(currentHomestayProvider).value == null) {
    return Stream.value(const []);
  }
  return ref.watch(homestayBookingRepositoryProvider).watchBookingsForHost(user.uid);
});
```

(Provider behavior is exercised through the Received-tab widget tests in Task 6 — per the repo's Riverpod gotcha, avoid `StreamProvider.future` in bare unit tests.)

- [ ] **Step 7: Run the new test + full test suite — expect PASS**

Run: `flutter test test/data/booking_transitions_test.dart && flutter test`

- [ ] **Step 8: `flutter analyze` clean, then commit**

```bash
git add lib/data/repositories test/support/fakes.dart test/data/booking_transitions_test.dart
git commit -m "feat: received-booking streams + status transitions on the booking repos"
```

---

### Task 4: Firestore rules — unlock the transition arrows + emulator matrix test

**Files:**
- Modify: `firestore.rules` (the `bookings` and `homestayBookings` matches)
- Modify: `integration_test/firebase_repos_test.dart` (append one test)

**Interfaces:**
- Consumes: repo transition methods from Task 3 (`acceptRequest`, `declineRequest`, `cancelStay`, `cancelBooking`, `watchBookingsForHost`, `watchBookingsForPro`), `AuthRepository.signIn`.
- Produces: rules that allow exactly the spec's arrows. Deploy happens in Task 8.

- [ ] **Step 1: Edit `firestore.rules`**

Replace `allow update, delete: if false;` in `match /bookings/{id}` with:

```
      allow update: if request.auth != null
                    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt'])
                    && resource.data.parentId == request.auth.uid
                    && resource.data.status == 'confirmed'
                    && request.resource.data.status == 'cancelled';
      allow delete: if false;
```

Replace `allow update, delete: if false;` in `match /homestayBookings/{id}` with:

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
      allow delete: if false;
```

- [ ] **Step 2: Append the matrix test to `integration_test/firebase_repos_test.dart`**

```dart
  testWidgets('booking lifecycle transitions obey the rules matrix (real Firestore emulators)',
      (tester) async {
    final auth = FirebaseAuthRepository();
    final stays = FirestoreHomestayBookingRepository();
    final bookings = FirestoreBookingRepository();
    final db = FirebaseFirestore.instance;
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final host = await auth.signUp(email: 'lh_$stamp@x.com', password: 'secret1');
    await auth.signOut();
    final guest = await auth.signUp(email: 'lg_$stamp@x.com', password: 'secret1');

    // Guest requests a stay with the host.
    await stays.createHomestayBooking(HomestayBooking(guestId: guest.uid, hostId: host.uid,
        homeName: 'H', hostName: 'M', petId: 'p', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2027, 1, 10), checkOut: DateTime(2027, 1, 13), nights: 3,
        subtotal: 2700, fee: 150, total: 2850));
    final stayId =
        (await stays.watchMyHomestayBookings(guest.uid).firstWhere((l) => l.isNotEmpty)).single.id;

    // Guest cannot accept their own request.
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update({'status': 'accepted', 'updatedAt': 1}),
        throwsA(isA<FirebaseException>()));

    // Host accepts via the repo (writes status + updatedAt only).
    await auth.signOut();
    await auth.signIn(email: 'lh_$stamp@x.com', password: 'secret1');
    await stays.acceptRequest(stayId);
    final accepted = (await stays.watchBookingsForHost(host.uid).firstWhere(
            (l) => l.any((s) => s.id == stayId && s.status == 'accepted')))
        .firstWhere((s) => s.id == stayId);
    expect(accepted.updatedAt, greaterThan(0));

    // Host cannot re-decide, cancel, or touch other fields once decided.
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update({'status': 'declined', 'updatedAt': 2}),
        throwsA(isA<FirebaseException>()));
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update({'status': 'cancelled', 'updatedAt': 2}),
        throwsA(isA<FirebaseException>()));
    await expectLater(
        db.collection('homestayBookings').doc(stayId).update({'total': 1, 'updatedAt': 2}),
        throwsA(isA<FirebaseException>()));

    // Guest can cancel the accepted stay.
    await auth.signOut();
    await auth.signIn(email: 'lg_$stamp@x.com', password: 'secret1');
    await stays.cancelStay(stayId);
    final cancelled = await stays
        .watchMyHomestayBookings(guest.uid)
        .firstWhere((l) => l.any((s) => s.id == stayId && s.status == 'cancelled'));
    expect(cancelled.firstWhere((s) => s.id == stayId).status, 'cancelled');

    // Service booking: parent cancels; pro-side stream sees it; invalid targets rejected.
    await bookings.createBooking(Booking(parentId: guest.uid, proId: host.uid, proName: 'Aarav',
        petId: 'p', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25,
        total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM', date: '2027-01-10'));
    final bkId = (await bookings.watchMyBookings(guest.uid).firstWhere((l) => l.isNotEmpty)).single.id;
    await expectLater(
        db.collection('bookings').doc(bkId).update({'status': 'paused', 'updatedAt': 1}),
        throwsA(isA<FirebaseException>()));
    await bookings.cancelBooking(bkId);

    await auth.signOut();
    await auth.signIn(email: 'lh_$stamp@x.com', password: 'secret1');
    final proSide = await bookings.watchBookingsForPro(host.uid).firstWhere((l) => l.isNotEmpty);
    expect(proSide.single.status, 'cancelled');
    // The pro cannot resurrect a cancelled booking.
    await expectLater(
        db.collection('bookings').doc(bkId).update({'status': 'confirmed', 'updatedAt': 9}),
        throwsA(isA<FirebaseException>()));

    await auth.signOut();
  });
```

- [ ] **Step 3: Run against the local emulators** (they load the local `firestore.rules`, so this validates before any deploy)

Run (two terminals):
```bash
firebase emulators:start --only auth,firestore --project pet-aggregator-app
flutter test integration_test/firebase_repos_test.dart -d emulator-5554
```
Expected: all tests pass, including the new matrix test. (If no Android emulator is running, start it first; this suite already exists and runs this way.)

- [ ] **Step 4: `flutter analyze` clean, then commit** (deploy of the rules happens in Task 8)

```bash
git add firestore.rules integration_test/firebase_repos_test.dart
git commit -m "feat: rules allow accept/decline/cancel booking transitions (+ emulator matrix test)"
```

---

### Task 5: Bookings hub — move to `features/bookings/`, tabs, phase chips, gated Rate, guest cancel

**Files:**
- Move: `lib/features/reviews/my_bookings_screen.dart` → `lib/features/bookings/my_bookings_screen.dart` (rewritten below)
- Create: `lib/features/bookings/phase_chip.dart`
- Create: `lib/features/bookings/booking_dialogs.dart`
- Create: `lib/features/bookings/received_tab.dart` (a stub this task; real content in Task 6)
- Modify: `lib/core/router/app_router.dart` (import path + `initialTab` extra)
- Modify: `test/features/my_bookings_screen_test.dart` (fixtures + overrides)
- Test: `test/features/bookings_hub_test.dart` (create)

**Interfaces:**
- Consumes: `BookingPhase`/`servicePhase`/`stayPhase`/`canRate`/`canCancelService`/`canCancelStay` (Task 2); `receivedServiceBookingsProvider`/`receivedStayBookingsProvider`, `cancelBooking`, `cancelStay` (Task 3); existing `myBookingsProvider`, `myHomestayBookingsProvider`, `myReviewedBookingIdsProvider`, `currentProProvider`, `currentHomestayProvider`.
- Produces: `MyBookingsScreen({int initialTab = 0})` (0 = My bookings, 1 = Received); `PhaseChip(BookingPhase phase)`; `Future<void> confirmAndRun(BuildContext context, {required String title, required String message, required String confirmLabel, required Future<void> Function() action})`; `Widget sectionLabel(PgColors c, String text)` (top-level, reused by Task 6); `ReceivedTab` (const, no params).

- [ ] **Step 1: Update the two existing tests so they stay honest under gating** (`test/features/my_bookings_screen_test.dart`)

Both tests currently seed a `requested` homestay with future dates and expect Rate — under gating that's `pending`. Change each `HomestayBooking` fixture to a **completed** stay (accepted, dates in the past, relative to now) and add the pro/homestay repo overrides the hub now watches:

In both testWidgets, replace the `HomestayBooking(...)` fixture with:

```dart
    final now = DateTime.now();
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(HomestayBooking(id: 'hb1', guestId: uid, hostId: 'host1',
        homeName: "Meera's Home", hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: now.subtract(const Duration(days: 5)), checkOut: now.subtract(const Duration(days: 2)),
        nights: 3, subtotal: 2700, fee: 150, total: 2850, status: 'accepted'));
```

And add to both `overrides:` lists:

```dart
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
```

(The service fixtures have no `date` → legacy → completed → still rateable; no change needed there.)

- [ ] **Step 2: Write the failing hub test**

```dart
// test/features/bookings_hub_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

HomestayBooking _stay(String id, String guestId, {String status = 'requested',
        String hostId = 'host1', DateTime? checkIn, DateTime? checkOut}) =>
    HomestayBooking(id: id, guestId: guestId, hostId: hostId, homeName: "Meera's Home",
        hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: checkIn ?? DateTime.now().add(const Duration(days: 3)),
        checkOut: checkOut ?? DateTime.now().add(const Duration(days: 6)),
        nights: 3, subtotal: 2700, fee: 150, total: 2850, status: status);

Future<(FakeAuthRepository, String)> _me() async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  return (auth, auth.currentUser!.uid);
}

void main() {
  testWidgets('plain pet parent: no Received tab, title stays My Bookings', (tester) async {
    final (auth, uid) = await _me();
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(_stay('hb1', uid));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(hbookings),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    expect(find.text('My Bookings'), findsOneWidget);
    expect(find.text('Received'), findsNothing);
  });

  testWidgets('chips reflect phases; Rate hidden until completed', (tester) async {
    final (auth, uid) = await _me();
    final bookings = InMemoryBookingRepository();
    await bookings.createBooking(Booking(id: 'bk1', parentId: uid, proId: 'pro1',
        proName: 'Aarav Sharma', petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker,
        rate: 250, fee: 25, total: 275, dateLabel: 'Tue', timeSlot: '5:00 PM',
        date: Booking.isoDate(DateTime.now().add(const Duration(days: 2)))));
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(_stay('hb1', uid));                       // Pending
    await hbookings.createHomestayBooking(_stay('hb2', uid, status: 'declined'));   // Declined
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(bookings),
      homestayBookingRepositoryProvider.overrideWithValue(hbookings),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    expect(find.text('Upcoming'), findsOneWidget);   // the future service booking
    expect(find.text('Pending'), findsOneWidget);    // hb1
    expect(find.text('Declined'), findsOneWidget);   // hb2
    expect(find.text('Rate'), findsNothing);         // nothing completed yet
  });

  testWidgets('guest cancels a pending request via the confirm dialog', (tester) async {
    final (auth, uid) = await _me();
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(_stay('hb1', uid));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(hbookings),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this booking?'), findsOneWidget);
    await tester.tap(find.text('Keep'));               // dismiss: nothing happens
    await tester.pumpAndSettle();
    expect(find.text('Pending'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel booking'));      // confirm
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsOneWidget);
    expect((await hbookings.watchMyHomestayBookings(uid).first).single.status, 'cancelled');
  });

  testWidgets('a host sees the Received tab and the Bookings title', (tester) async {
    final (auth, uid) = await _me();
    final homestays = InMemoryHomestayRepository();
    await homestays.upsertHomestay(Homestay(uid: uid, homeName: 'My Home', hostName: 'Me',
        area: 'Khar', about: '', homeType: HomeType.apartment, ratePerNight: 900));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
      reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(homestays),
    ], initialLocation: Routes.bookings);
    await tester.pumpAndSettle();

    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('My bookings'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run both hub test files — expect FAIL**

Run: `flutter test test/features/bookings_hub_test.dart test/features/my_bookings_screen_test.dart`

- [ ] **Step 4: Create the shared pieces**

```dart
// lib/features/bookings/phase_chip.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/booking_lifecycle.dart';

class PhaseChip extends StatelessWidget {
  final BookingPhase phase;
  const PhaseChip(this.phase, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    // One-off accents match the notification-feed accent precedent.
    final (Color bg, Color fg) = switch (phase) {
      BookingPhase.upcoming => (c.brandSoft, c.brand),
      BookingPhase.completed => (const Color(0x1A34B27B), const Color(0xFF34B27B)),
      BookingPhase.declined => (const Color(0x1AE5484D), const Color(0xFFE5484D)),
      BookingPhase.pending ||
      BookingPhase.cancelled ||
      BookingPhase.expired => (c.border, c.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(phase.label, style: PgText.inter(11.5, FontWeight.w700, color: fg)),
    );
  }
}
```

```dart
// lib/features/bookings/booking_dialogs.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Confirms [title]/[message], then runs [action]. On failure shows a SnackBar
/// (the booking streams re-emit the true state either way).
Future<void> confirmAndRun(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Future<void> Function() action,
}) async {
  final c = context.pg;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(title, style: PgText.poppins(16, FontWeight.w700, color: c.text)),
      content: Text(message, style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text('Keep', style: PgText.inter(13.5, FontWeight.w600, color: c.muted))),
        TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(confirmLabel, style: PgText.inter(13.5, FontWeight.w700, color: c.brand))),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await action();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update the booking — try again.")));
  }
}
```

```dart
// lib/features/bookings/received_tab.dart  (stub — Task 6 replaces the body)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class ReceivedTab extends ConsumerWidget {
  const ReceivedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(30),
            child: Text('No bookings for your listing yet.',
                textAlign: TextAlign.center,
                style: PgText.inter(13.5, FontWeight.w400, color: c.muted))));
  }
}
```

- [ ] **Step 5: Move + rewrite the hub screen**

```bash
git mv lib/features/reviews/my_bookings_screen.dart lib/features/bookings/my_bookings_screen.dart
```

Then replace its full contents:

```dart
// lib/features/bookings/my_bookings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/booking.dart';
import '../../data/models/booking_lifecycle.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/models/review.dart';
import '../../data/repositories/providers.dart';
import 'booking_dialogs.dart';
import 'phase_chip.dart';
import 'received_tab.dart';

class MyBookingsScreen extends ConsumerStatefulWidget {
  final int initialTab; // 0 = My bookings · 1 = Received
  const MyBookingsScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final hasListing = ref.watch(currentProProvider).value != null ||
        ref.watch(currentHomestayProvider).value != null;
    final tab = hasListing ? _tab : 0;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PgAppBar(
              title: hasListing ? 'Bookings' : 'My Bookings',
              onBack: () => context.canPop() ? context.pop() : context.go(Routes.home)),
          if (hasListing)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
              child: Row(children: [
                _tabChip(c, 'My bookings', 0),
                const SizedBox(width: 8),
                _tabChip(c, 'Received', 1),
              ]),
            ),
          Expanded(child: tab == 1 ? const ReceivedTab() : const _MyBookingsTab()),
        ]),
      ),
    );
  }

  Widget _tabChip(PgColors c, String label, int index) {
    final selected = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.brand : c.surface,
          border: selected ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: PgText.inter(13, FontWeight.w600, color: selected ? Colors.white : c.text)),
      ),
    );
  }
}

Widget sectionLabel(PgColors c, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(text, style: PgText.poppins(14, FontWeight.w700, color: c.muted)),
    );

class _MyBookingsTab extends ConsumerWidget {
  const _MyBookingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final services = ref.watch(myBookingsProvider).value ?? const <Booking>[];
    final stays = ref.watch(myHomestayBookingsProvider).value ?? const <HomestayBooking>[];
    final rated = ref.watch(myReviewedBookingIdsProvider).value ?? const <String>{};
    final now = DateTime.now();

    if (services.isEmpty && stays.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(30),
              child: Text('No bookings yet — book a service or a homestay to get started.',
                  textAlign: TextAlign.center,
                  style: PgText.inter(13.5, FontWeight.w400, color: c.muted))));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (services.isNotEmpty) ...[
          sectionLabel(c, 'Services'),
          for (final b in services)
            _MyBookingRow(
              emoji: '🧑',
              name: b.proName,
              detail: '${b.serviceType.label} · ${b.dateLabel}',
              phase: servicePhase(b, now),
              rated: rated.contains(b.id),
              canCancel: canCancelService(b, now),
              onCancel: () => confirmAndRun(context,
                  title: 'Cancel this booking?',
                  message: "This can't be undone.",
                  confirmLabel: 'Cancel booking',
                  action: () => ref.read(bookingRepositoryProvider).cancelBooking(b.id)),
              onRate: () => context.push(Routes.rate,
                  extra: ReviewTarget(
                      type: ReviewTargetType.pro, id: b.proId, name: b.proName,
                      subtitle: '${b.serviceType.label} · ${b.dateLabel}', bookingId: b.id)),
            ),
        ],
        if (stays.isNotEmpty) ...[
          sectionLabel(c, 'Homestays'),
          for (final s in stays)
            _MyBookingRow(
              emoji: '🏡',
              name: s.homeName,
              detail: '${s.hostName} · ${HomestayBooking.fmtDay(s.checkIn)} · ${s.nights} nights',
              phase: stayPhase(s, now),
              rated: rated.contains(s.id),
              canCancel: canCancelStay(s, now),
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
        ],
      ],
    );
  }
}

class _MyBookingRow extends StatelessWidget {
  final String emoji, name, detail;
  final BookingPhase phase;
  final bool rated, canCancel;
  final VoidCallback onRate, onCancel;
  const _MyBookingRow(
      {required this.emoji, required this.name, required this.detail, required this.phase,
      required this.rated, required this.canCancel, required this.onRate, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        PgImageSlot(size: 46, circle: true, emoji: emoji),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
          const SizedBox(height: 2),
          Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
        ])),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          PhaseChip(phase),
          if (rated) ...[
            const SizedBox(height: 6),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: c.brandSoft, borderRadius: BorderRadius.circular(20)),
                child: Text('★ Rated',
                    style: PgText.inter(12.5, FontWeight.w700, color: c.brand))),
          ] else if (canRate(phase)) ...[
            const SizedBox(height: 6),
            GestureDetector(
                onTap: onRate,
                child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [c.brand, c.brand2]),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('Rate',
                        style: PgText.poppins(13, FontWeight.w700, color: Colors.white)))),
          ] else if (canCancel) ...[
            const SizedBox(height: 6),
            GestureDetector(
                onTap: onCancel,
                child: Text('Cancel',
                    style: PgText.inter(12.5, FontWeight.w600, color: c.muted))),
          ],
        ]),
      ]),
    );
  }
}
```

- [ ] **Step 6: Update the router** (`lib/core/router/app_router.dart`)

Change the my_bookings import to `import '../../features/bookings/my_bookings_screen.dart';` and the route to:

```dart
      GoRoute(path: Routes.bookings, builder: (_, state) =>
          MyBookingsScreen(initialTab: state.extra is int ? state.extra as int : 0)),
```

Also update the import at the top of `test/features/my_bookings_screen_test.dart` if it imports the screen directly (it currently doesn't — it navigates by route).

- [ ] **Step 7: Run the hub tests + full suite — expect PASS**

Run: `flutter test test/features/bookings_hub_test.dart test/features/my_bookings_screen_test.dart && flutter test`

- [ ] **Step 8: `flutter analyze` clean, then commit**

```bash
git add -A lib/features/bookings lib/features/reviews lib/core/router/app_router.dart test/features/bookings_hub_test.dart test/features/my_bookings_screen_test.dart
git commit -m "feat: Bookings hub - tabs, status chips, gated Rate, guest cancel"
```

---

### Task 6: Received tab — host accept/decline + supply-side ledger

**Files:**
- Modify: `lib/features/bookings/received_tab.dart` (replace the stub body)
- Test: `test/features/received_tab_test.dart` (create)

**Interfaces:**
- Consumes: `receivedStayBookingsProvider`, `receivedServiceBookingsProvider`, `acceptRequest`, `declineRequest` (Task 3); `canDecide`, `stayPhase`, `servicePhase`, `BookingPhase` (Task 2); `PhaseChip`, `confirmAndRun`, `sectionLabel` (Task 5).
- Produces: the final `ReceivedTab` widget.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/received_tab_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

HomestayBooking _request(String id, String hostId, {String note = ''}) => HomestayBooking(
    id: id, guestId: 'guest1', hostId: hostId, homeName: 'My Home', hostName: 'Me',
    petId: 'p1', petName: 'Bruno', ratePerNight: 900,
    checkIn: DateTime.now().add(const Duration(days: 3)),
    checkOut: DateTime.now().add(const Duration(days: 6)),
    nights: 3, subtotal: 2700, fee: 150, total: 2850, note: note);

Future<void> _pumpAsHost(WidgetTester tester,
    {required FakeAuthRepository auth,
    required InMemoryHomestayBookingRepository hbookings,
    InMemoryBookingRepository? bookings,
    InMemoryProRepository? pros,
    InMemoryHomestayRepository? homestays}) async {
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    bookingRepositoryProvider.overrideWithValue(bookings ?? InMemoryBookingRepository()),
    homestayBookingRepositoryProvider.overrideWithValue(hbookings),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
    proRepositoryProvider.overrideWithValue(pros ?? InMemoryProRepository()),
    homestayRepositoryProvider.overrideWithValue(homestays ?? InMemoryHomestayRepository()),
  ], initialLocation: Routes.bookings);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Received'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('host sees a pending request and Accept flips it to Upcoming', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'host@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final homestays = InMemoryHomestayRepository();
    await homestays.upsertHomestay(Homestay(uid: uid, homeName: 'My Home', hostName: 'Me',
        area: 'Khar', about: '', homeType: HomeType.apartment, ratePerNight: 900));
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(_request('hb1', uid, note: 'Friendly boy'));

    await _pumpAsHost(tester, auth: auth, hbookings: hbookings, homestays: homestays);

    expect(find.text('Stay request · Bruno'), findsOneWidget);
    expect(find.text('“Friendly boy”'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Upcoming'), findsOneWidget);
    final stored = (await hbookings.watchBookingsForHost(uid).first).single;
    expect(stored.status, 'accepted');
    expect(stored.updatedAt, greaterThan(0));
  });

  testWidgets('Decline asks for confirmation first', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'host@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final homestays = InMemoryHomestayRepository();
    await homestays.upsertHomestay(Homestay(uid: uid, homeName: 'My Home', hostName: 'Me',
        area: 'Khar', about: '', homeType: HomeType.apartment, ratePerNight: 900));
    final hbookings = InMemoryHomestayBookingRepository();
    await hbookings.createHomestayBooking(_request('hb1', uid));

    await _pumpAsHost(tester, auth: auth, hbookings: hbookings, homestays: homestays);

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(find.text('Decline this request?'), findsOneWidget);
    await tester.tap(find.text('Decline').last); // the dialog's confirm action
    await tester.pumpAndSettle();
    expect(find.text('Declined'), findsOneWidget);
    expect((await hbookings.watchBookingsForHost(uid).first).single.status, 'declined');
  });

  testWidgets('a pro sees a read-only ledger of their service bookings', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'pro@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final pros = InMemoryProRepository();
    await pros.upsertPro(Pro(uid: uid, name: 'Me', area: 'Khar', bio: '',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 2));
    final bookings = InMemoryBookingRepository();
    await bookings.createBooking(Booking(id: 'bk1', parentId: 'guest1', proId: uid,
        proName: 'Me', petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker,
        rate: 250, fee: 25, total: 275, dateLabel: 'Tue', timeSlot: '5:00 PM',
        date: Booking.isoDate(DateTime.now().add(const Duration(days: 2)))));

    await _pumpAsHost(tester, auth: auth,
        hbookings: InMemoryHomestayBookingRepository(), bookings: bookings, pros: pros);

    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Accept'), findsNothing); // service bookings are never actionable
  });

  testWidgets('empty received state', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'host@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final homestays = InMemoryHomestayRepository();
    await homestays.upsertHomestay(Homestay(uid: uid, homeName: 'My Home', hostName: 'Me',
        area: 'Khar', about: '', homeType: HomeType.apartment, ratePerNight: 900));

    await _pumpAsHost(tester, auth: auth,
        hbookings: InMemoryHomestayBookingRepository(), homestays: homestays);

    expect(find.text('No bookings for your listing yet.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (stub has no request cards)

Run: `flutter test test/features/received_tab_test.dart`

- [ ] **Step 3: Implement the real `ReceivedTab`** (replace the whole stub file)

```dart
// lib/features/bookings/received_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/booking.dart';
import '../../data/models/booking_lifecycle.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/repositories/providers.dart';
import 'booking_dialogs.dart';
import 'my_bookings_screen.dart' show sectionLabel;
import 'phase_chip.dart';

class ReceivedTab extends ConsumerWidget {
  const ReceivedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final stays = ref.watch(receivedStayBookingsProvider).value ?? const <HomestayBooking>[];
    final services = ref.watch(receivedServiceBookingsProvider).value ?? const <Booking>[];
    final now = DateTime.now();

    if (stays.isEmpty && services.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(30),
              child: Text('No bookings for your listing yet.',
                  textAlign: TextAlign.center,
                  style: PgText.inter(13.5, FontWeight.w400, color: c.muted))));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (stays.isNotEmpty) ...[
          sectionLabel(c, 'Homestay stays'),
          for (final s in stays)
            if (canDecide(s, now))
              _RequestCard(s)
            else
              _LedgerRow(
                  emoji: '🐾',
                  name: s.petName,
                  detail:
                      '${HomestayBooking.fmtDay(s.checkIn)} · ${s.nights} nights · ₹${s.total}',
                  phase: stayPhase(s, now)),
        ],
        if (services.isNotEmpty) ...[
          sectionLabel(c, 'Service bookings'),
          for (final b in services)
            _LedgerRow(
                emoji: '🐾',
                name: b.petName,
                detail: '${b.serviceType.label} · ${b.dateLabel} · ${b.timeSlot}',
                phase: servicePhase(b, now)),
        ],
      ],
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final HomestayBooking s;
  const _RequestCard(this.s);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PgImageSlot(size: 46, circle: true, emoji: '🐾'),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Stay request · ${s.petName}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
            const SizedBox(height: 2),
            Text(
                '${HomestayBooking.fmtDay(s.checkIn)} → ${HomestayBooking.fmtDay(s.checkOut)}'
                ' · ${s.nights} nights · ₹${s.total}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
          ])),
          const SizedBox(width: 10),
          const PhaseChip(BookingPhase.pending),
        ]),
        if (s.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('“${s.note}”', style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: GestureDetector(
                  onTap: () async {
                    try {
                      await ref.read(homestayBookingRepositoryProvider).acceptRequest(s.id);
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("Couldn't update the booking — try again.")));
                    }
                  },
                  child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [c.brand, c.brand2]),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('Accept',
                          style: PgText.poppins(13.5, FontWeight.w700, color: Colors.white))))),
          const SizedBox(width: 10),
          Expanded(
              child: GestureDetector(
                  onTap: () => confirmAndRun(context,
                      title: 'Decline this request?',
                      message: "This can't be undone.",
                      confirmLabel: 'Decline',
                      action: () =>
                          ref.read(homestayBookingRepositoryProvider).declineRequest(s.id)),
                  child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          border: Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('Decline',
                          style: PgText.poppins(13.5, FontWeight.w600, color: c.text))))),
        ]),
      ]),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  final String emoji, name, detail;
  final BookingPhase phase;
  const _LedgerRow(
      {required this.emoji, required this.name, required this.detail, required this.phase});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        PgImageSlot(size: 46, circle: true, emoji: emoji),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
          const SizedBox(height: 2),
          Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
        ])),
        const SizedBox(width: 10),
        PhaseChip(phase),
      ]),
    );
  }
}
```

- [ ] **Step 4: Run the received-tab tests + full suite — expect PASS**

Run: `flutter test test/features/received_tab_test.dart && flutter test`

- [ ] **Step 5: `flutter analyze` clean, then commit**

```bash
git add lib/features/bookings/received_tab.dart test/features/received_tab_test.dart
git commit -m "feat: Received tab - host accept/decline + supply-side ledger"
```

---

### Task 7: Lifecycle notifications — request received / decided / cancelled

**Files:**
- Modify: `lib/features/notifications/notification_item.dart`
- Modify: `lib/data/repositories/providers.dart` (`notificationsProvider`)
- Test: `test/features/notifications_lifecycle_test.dart` (create)

**Interfaces:**
- Consumes: `receivedServiceBookingsProvider` / `receivedStayBookingsProvider` (Task 3); `updatedAt` fields (Task 1).
- Produces: `buildNotifications` grows two **optional** params (existing call sites keep compiling): `List<Booking> receivedBookings = const []`, `List<HomestayBooking> receivedStays = const []`. New items deep-link to `Routes.bookings` with `extra` = target tab (int: 0 my / 1 received).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/notifications_lifecycle_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/features/notifications/notification_item.dart';

Booking _svc({String status = 'confirmed', int createdAt = 10, int updatedAt = 0}) => Booking(
    id: 'bk1', parentId: 'g', proId: 'p', proName: 'Aarav', petId: 'x', petName: 'Bruno',
    serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275, dateLabel: 'Tue',
    timeSlot: '5:00 PM', status: status, createdAt: createdAt, updatedAt: updatedAt);

HomestayBooking _stay({String status = 'requested', int createdAt = 10, int updatedAt = 0}) =>
    HomestayBooking(id: 'hb1', guestId: 'g', hostId: 'h', homeName: "Meera's Home",
        hostName: 'Meera', petId: 'x', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2027, 1, 10), checkOut: DateTime(2027, 1, 13), nights: 3,
        subtotal: 2700, fee: 150, total: 2850, status: status,
        createdAt: createdAt, updatedAt: updatedAt);

List<NotificationItem> _build({List<Booking> bookings = const [],
        List<HomestayBooking> homestays = const [],
        List<Booking> receivedBookings = const [],
        List<HomestayBooking> receivedStays = const [],
        int seenAt = 0}) =>
    buildNotifications(myUid: 'me', seenAt: seenAt, chats: const [], reviews: const [],
        bookings: bookings, homestays: homestays,
        receivedBookings: receivedBookings, receivedStays: receivedStays);

void main() {
  test('host sees a new-request item deep-linking to the Received tab', () {
    final items = _build(receivedStays: [_stay(createdAt: 100)]);
    final item = items.singleWhere((n) => n.title.startsWith('New booking request'));
    expect(item.title, "New booking request from Bruno's parent");
    expect(item.route, Routes.bookings);
    expect(item.extra, 1);
    expect(item.timestamp, 100);
    expect(item.read, isFalse);
  });

  test('guest sees accepted/declined items stamped with updatedAt', () {
    final acc = _build(homestays: [_stay(status: 'accepted', updatedAt: 200)]);
    final item = acc.singleWhere((n) => n.title.contains('accepted'));
    expect(item.title, "Meera's Home accepted your request");
    expect(item.timestamp, 200);
    expect(item.extra, 0);

    final dec = _build(homestays: [_stay(status: 'declined', updatedAt: 300)]);
    expect(dec.singleWhere((n) => n.title.contains('declined')).timestamp, 300);
  });

  test('a decided item with updatedAt 0 falls back to createdAt', () {
    final items = _build(homestays: [_stay(status: 'accepted', createdAt: 40, updatedAt: 0)]);
    expect(items.singleWhere((n) => n.title.contains('accepted')).timestamp, 40);
  });

  test('supply side sees cancellation items', () {
    final items = _build(
        receivedStays: [_stay(status: 'cancelled', updatedAt: 500)],
        receivedBookings: [_svc(status: 'cancelled', updatedAt: 600)]);
    expect(items.singleWhere((n) => n.title == "Bruno's stay was cancelled").timestamp, 500);
    expect(items.singleWhere((n) => n.title == "Bruno's booking was cancelled").timestamp, 600);
  });

  test('a cancelled service booking no longer claims "Booking confirmed"', () {
    final items = _build(bookings: [_svc(status: 'cancelled')]);
    expect(items.where((n) => n.title.startsWith('Booking confirmed')), isEmpty);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (params don't exist)

Run: `flutter test test/features/notifications_lifecycle_test.dart`

- [ ] **Step 3: Extend `buildNotifications`** (`lib/features/notifications/notification_item.dart`)

Add the two optional params to the signature (after `required List<HomestayBooking> homestays,`):

```dart
  List<Booking> receivedBookings = const [],
  List<HomestayBooking> receivedStays = const [],
```

Add a helper above `buildNotifications`:

```dart
int _eventTs(int updatedAt, int createdAt) => updatedAt > 0 ? updatedAt : createdAt;
```

In the existing `for (final b in bookings)` loop, skip cancelled bookings (first line of the loop body):

```dart
    if (b.status == 'cancelled') continue;
```

After the existing `for (final s in homestays)` loop, add:

```dart
  for (final s in homestays) {
    if (s.status != 'accepted' && s.status != 'declined') continue;
    final ok = s.status == 'accepted';
    final ts = _eventTs(s.updatedAt, s.createdAt);
    items.add(NotificationItem(
        type: PgNotificationType.homestay,
        icon: ok ? '✅' : '❌',
        accent: ok ? const Color(0xFF34B27B) : const Color(0xFFE5484D),
        title: '${s.homeName} ${ok ? 'accepted' : 'declined'} your request',
        body: '${HomestayBooking.fmtDay(s.checkIn)} · ${s.nights} nights',
        timestamp: ts, route: Routes.bookings, extra: 0, read: !unread(ts)));
  }

  for (final s in receivedStays) {
    if (s.status == 'requested') {
      items.add(NotificationItem(
          type: PgNotificationType.homestay,
          icon: '🏡', accent: const Color(0xFFF97316),
          title: "New booking request from ${s.petName}'s parent",
          body: '${HomestayBooking.fmtDay(s.checkIn)} → ${HomestayBooking.fmtDay(s.checkOut)}'
              ' · ₹${s.total}',
          timestamp: s.createdAt, route: Routes.bookings, extra: 1,
          read: !unread(s.createdAt)));
    } else if (s.status == 'cancelled') {
      final ts = _eventTs(s.updatedAt, s.createdAt);
      items.add(NotificationItem(
          type: PgNotificationType.homestay,
          icon: '↩️', accent: const Color(0xFF9AA0A6),
          title: "${s.petName}'s stay was cancelled",
          body: '${s.homeName} · ${s.nights} nights',
          timestamp: ts, route: Routes.bookings, extra: 1, read: !unread(ts)));
    }
  }

  for (final b in receivedBookings) {
    if (b.status != 'cancelled') continue;
    final ts = _eventTs(b.updatedAt, b.createdAt);
    items.add(NotificationItem(
        type: PgNotificationType.booking,
        icon: '↩️', accent: const Color(0xFF9AA0A6),
        title: "${b.petName}'s booking was cancelled",
        body: '${b.serviceType.label} · ${b.dateLabel}',
        timestamp: ts, route: Routes.bookings, extra: 1, read: !unread(ts)));
  }
```

- [ ] **Step 4: Wire the provider** — in `notificationsProvider` (`lib/data/repositories/providers.dart`), add after the `homestays:` line:

```dart
    receivedBookings: ref.watch(receivedServiceBookingsProvider).value ?? const [],
    receivedStays: ref.watch(receivedStayBookingsProvider).value ?? const [],
```

- [ ] **Step 5: Run the new tests + the existing notification tests + full suite — expect PASS**

Run: `flutter test test/features/notifications_lifecycle_test.dart test/features/notifications_builder_test.dart test/features/notifications_screen_test.dart test/data/notifications_provider_test.dart && flutter test`

- [ ] **Step 6: `flutter analyze` clean, then commit**

```bash
git add lib/features/notifications/notification_item.dart lib/data/repositories/providers.dart test/features/notifications_lifecycle_test.dart
git commit -m "feat: lifecycle notifications - request received, request decided, booking cancelled"
```

---

### Task 8: Final verification — full suite, rules deploy, device smoke test

**Files:**
- No new code (fixes only if verification finds problems).

- [ ] **Step 1: Full local verification**

```bash
flutter analyze          # expect: No issues found!
flutter test             # expect: all pass
flutter build apk --debug  # expect: build succeeds (native plugins unchanged, sanity only)
```

- [ ] **Step 2: Emulator rules matrix** (if not already run in Task 4, or re-run after any rules edit)

```bash
firebase emulators:start --only auth,firestore --project pet-aggregator-app
flutter test integration_test/firebase_repos_test.dart -d emulator-5554
```

- [ ] **Step 3: Deploy the rules to production**

```bash
firebase deploy --only firestore:rules --project pet-aggregator-app
```
Expected: `✔ Deploy complete!`

- [ ] **Step 4: On-device smoke test** (`flutter run -d emulator-5554`, two accounts)

1. Account A (host with a homestay listing): Bookings shows the two tabs.
2. Account B: request a stay with A's homestay → My bookings shows **Pending** + Cancel.
3. Account A: Received shows the request card → Accept → B's row flips to **Upcoming**; B's notification bell shows "accepted".
4. Account B: cancel an upcoming booking (confirm dialog) → A gets the "cancelled" notification item.
5. Book a service for a future date → **Upcoming**, no Rate; a legacy booking (created before this slice) still shows Rate.

- [ ] **Step 5: Commit any verification fixes + the pre-existing generated-plugin housekeeping**

```bash
git add linux/flutter macos/Flutter windows/flutter
git commit -m "chore: commit regenerated desktop plugin registrants"
```

---

## Self-review notes (checked against the spec)

- Every spec section maps to a task: lifecycle model → 1–2, repositories → 3, rules → 4, hub/tabs/chips/Rate-gating/cancel → 5, Received/accept/decline → 6, notifications → 7, error handling (SnackBar + confirm dialogs) → 5–6, testing/DoD → all + 8.
- Type/name consistency: `BookingPhase`, `servicePhase`, `stayPhase`, `canRate`, `canCancelService`, `canCancelStay`, `canDecide`, `acceptRequest`, `declineRequest`, `cancelStay`, `cancelBooking`, `watchBookingsForPro`, `watchBookingsForHost`, `receivedServiceBookingsProvider`, `receivedStayBookingsProvider`, `PhaseChip`, `confirmAndRun`, `sectionLabel`, `ReceivedTab`, `MyBookingsScreen.initialTab` are used with identical spellings across tasks.
- `updatedAt` uses client millis (not `FieldValue.serverTimestamp()`): the models' defensive `is int` read would degrade a server `Timestamp` to 0 forever; client millis matches the repo's `createdAt` convention. This is a deliberate, documented deviation from the spec's "server timestamp" phrasing with identical rules behavior.
