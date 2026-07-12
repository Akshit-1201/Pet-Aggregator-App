# Pawgo Slice 5b: Homestay — Request → Accepted — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a signed-in pet parent request a homestay from a Host profile — pick a date range / pet / optional note, see a price breakdown, and "Send request" writes a real `homestayBookings/{id}` doc with `status: 'requested'`, landing on an honest "Request sent!" screen.

**Architecture:** Feature-first Flutter on the existing repository seam, mirroring Services 4b (`bookings`). A new `HomestayBookingRepository` (interface + Firestore impl + in-memory fake) backs `homestayBookings`; a provider exposes it; the existing `myPetsProvider` feeds the pet selector. Two new screens; no payment screen (payments are Phase 10) and no host-accept (a later slice — rules stay create-only). Tests use in-memory fakes via `pumpPgApp`/`pumpPg`; the emulator integration test covers the real Firestore path.

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `cloud_firestore`, `flutter_riverpod`, `go_router`, `google_fonts`. **No new packages** (date picker is Flutter's built-in `showDateRangePicker`).

**Spec:** `docs/superpowers/specs/2026-07-12-pawgo-homestay-5b-booking-request-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **Live Firestore, no mock data.** UI/tests depend only on repository interfaces; never import `cloud_firestore`/`firebase_auth` outside `data/repositories/firebase/`, `lib/main.dart`, and `integration_test/`.
- **Honest semantics:** the booking is written with `status: 'requested'` and the confirmation says "Request sent!" — never "accepted/confirmed". No host-accept path this slice.
- **No payment screen.** "Send request" writes the booking directly (payments deferred to Phase 10).
- **Flat service fee `HomestayBooking.serviceFee = 150`** (matches the prototype), not a percentage.
- **Real ISO dates stored** (`checkIn`/`checkOut` as `yyyy-MM-dd`); date labels are formatted in-app with const weekday/month arrays (no `intl`).
- Riverpod 3.x: use `AsyncValue.value` (not `valueOrNull`); in tests, `Override` comes from `package:flutter_riverpod/misc.dart`; prefer a repo stream's `.first`.
- `go_router` builders use `(_, _)`; routes that read `extra` use `(_, state)`. Screen tests use the `pumpPgApp`/`pumpPg` harness (`pumpPgApp` accepts an `extra:` arg). Any plain `test()` touching `GoogleFonts` uses `testWidgets`.
- Firestore writes set the server timestamp (`createdAt`) in the repository, never in model `toMap()`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: `HomestayBooking` model

**Files:**
- Create: `lib/data/models/homestay_booking.dart`
- Test: `test/data/homestay_booking_test.dart`

**Interfaces:**
- Produces: `class HomestayBooking { final String id, guestId, hostId, homeName, hostName, petId, petName, note, status; final DateTime checkIn, checkOut; final int ratePerNight, nights, subtotal, fee, total; const HomestayBooking({this.id='', required ..., this.note='', this.status='requested'}); static const int serviceFee = 150; static int nightsBetween(DateTime,DateTime); static String fmtDay(DateTime); Map<String,dynamic> toMap(); factory HomestayBooking.fromMap(String,Map); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/data/homestay_booking_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';

void main() {
  test('serviceFee / nightsBetween / fmtDay', () {
    expect(HomestayBooking.serviceFee, 150);
    expect(HomestayBooking.nightsBetween(DateTime(2026, 7, 12), DateTime(2026, 7, 15)), 3);
    expect(HomestayBooking.fmtDay(DateTime(2024, 1, 1)), 'Mon, 1 Jan'); // 2024-01-01 was a Monday
  });

  test('toMap omits id/createdAt with ISO dates; fromMap restores', () {
    final b = HomestayBooking(guestId: 'g1', hostId: 'h1', homeName: "Meera's Home",
        hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 7, 12), checkOut: DateTime(2026, 7, 15), nights: 3,
        subtotal: 2700, fee: 150, total: 2850, note: 'Friendly boy');
    final m = b.toMap();
    expect(m.containsKey('id'), isFalse);
    expect(m.containsKey('createdAt'), isFalse);
    expect(m['checkIn'], '2026-07-12');
    expect(m['checkOut'], '2026-07-15');
    expect(m['status'], 'requested');
    expect(m['total'], 2850);
    final back = HomestayBooking.fromMap('bk1', m);
    expect(back.id, 'bk1');
    expect(back.petName, 'Bruno');
    expect(back.checkIn, DateTime(2026, 7, 12));
    expect(back.nights, 3);
    expect(back.note, 'Friendly boy');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/homestay_booking_test.dart`
Expected: FAIL — `HomestayBooking` not found.

- [ ] **Step 3: Implement `lib/data/models/homestay_booking.dart`**

```dart
class HomestayBooking {
  final String id, guestId, hostId, homeName, hostName, petId, petName, note, status;
  final DateTime checkIn, checkOut;
  final int ratePerNight, nights, subtotal, fee, total;

  const HomestayBooking({
    this.id = '',
    required this.guestId, required this.hostId, required this.homeName,
    required this.hostName, required this.petId, required this.petName,
    required this.ratePerNight, required this.checkIn, required this.checkOut,
    required this.nights, required this.subtotal, required this.fee, required this.total,
    this.note = '', this.status = 'requested',
  });

  static const int serviceFee = 150;

  static int nightsBetween(DateTime checkIn, DateTime checkOut) =>
      checkOut.difference(checkIn).inDays;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months =
      ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String fmtDay(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
        'guestId': guestId,
        'hostId': hostId,
        'homeName': homeName,
        'hostName': hostName,
        'petId': petId,
        'petName': petName,
        'ratePerNight': ratePerNight,
        'checkIn': _iso(checkIn),
        'checkOut': _iso(checkOut),
        'nights': nights,
        'subtotal': subtotal,
        'fee': fee,
        'total': total,
        'note': note,
        'status': status,
      };

  factory HomestayBooking.fromMap(String id, Map<String, dynamic> m) => HomestayBooking(
        id: id,
        guestId: (m['guestId'] ?? '') as String,
        hostId: (m['hostId'] ?? '') as String,
        homeName: (m['homeName'] ?? '') as String,
        hostName: (m['hostName'] ?? '') as String,
        petId: (m['petId'] ?? '') as String,
        petName: (m['petName'] ?? '') as String,
        ratePerNight: (m['ratePerNight'] ?? 0) as int,
        checkIn: DateTime.parse((m['checkIn'] ?? '1970-01-01') as String),
        checkOut: DateTime.parse((m['checkOut'] ?? '1970-01-01') as String),
        nights: (m['nights'] ?? 0) as int,
        subtotal: (m['subtotal'] ?? 0) as int,
        fee: (m['fee'] ?? 0) as int,
        total: (m['total'] ?? 0) as int,
        note: (m['note'] ?? '') as String,
        status: (m['status'] ?? 'requested') as String,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/homestay_booking_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze lib/data/models/homestay_booking.dart
git add lib/data/models/homestay_booking.dart test/data/homestay_booking_test.dart
git commit -m "feat: add HomestayBooking model with ISO-date serialization + fee/nights helpers"
```

---

### Task 2: `HomestayBookingRepository` interface + in-memory fake

**Files:**
- Create: `lib/data/repositories/homestay_booking_repository.dart`
- Modify: `test/support/fakes.dart` (add `InMemoryHomestayBookingRepository`)
- Test: `test/data/homestay_booking_repository_test.dart`

**Interfaces:**
- Consumes: `HomestayBooking` (Task 1).
- Produces: `abstract interface class HomestayBookingRepository { Future<void> createHomestayBooking(HomestayBooking booking); Stream<List<HomestayBooking>> watchMyHomestayBookings(String guestId); }` and `InMemoryHomestayBookingRepository`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/homestay_booking_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import '../support/fakes.dart';

HomestayBooking _b(String guestId, String petName) => HomestayBooking(
    guestId: guestId, hostId: 'h1', homeName: "Meera's Home", hostName: 'Meera Iyer',
    petId: 'p_$petName', petName: petName, ratePerNight: 900,
    checkIn: DateTime(2026, 7, 12), checkOut: DateTime(2026, 7, 15), nights: 3,
    subtotal: 2700, fee: 150, total: 2850);

void main() {
  test('InMemoryHomestayBookingRepository creates and streams my bookings', () async {
    final repo = InMemoryHomestayBookingRepository();
    expect(await repo.watchMyHomestayBookings('g1').first, isEmpty);
    await repo.createHomestayBooking(_b('g1', 'Bruno'));
    await repo.createHomestayBooking(_b('g2', 'Mochi')); // another guest's — not mine
    final mine = await repo.watchMyHomestayBookings('g1').first;
    expect(mine.single.petName, 'Bruno');
    expect(mine.single.total, 2850);
    expect(mine.single.status, 'requested');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/homestay_booking_repository_test.dart`
Expected: FAIL — types not found.

- [ ] **Step 3: Create `lib/data/repositories/homestay_booking_repository.dart`**

```dart
import '../models/homestay_booking.dart';

abstract interface class HomestayBookingRepository {
  Future<void> createHomestayBooking(HomestayBooking booking);
  Stream<List<HomestayBooking>> watchMyHomestayBookings(String guestId);
}
```

- [ ] **Step 4: Add `InMemoryHomestayBookingRepository` to `test/support/fakes.dart`**

Add these imports next to the existing ones: `import 'package:pet_aggregator_app/data/models/homestay_booking.dart';` and `import 'package:pet_aggregator_app/data/repositories/homestay_booking_repository.dart';`. Then append this class (mirrors `InMemoryBookingRepository`):

```dart
class InMemoryHomestayBookingRepository implements HomestayBookingRepository {
  final List<HomestayBooking> _bookings = [];
  final _controller = StreamController<List<HomestayBooking>>.broadcast();

  @override
  Future<void> createHomestayBooking(HomestayBooking booking) async {
    _bookings.add(booking);
    _controller.add(List.of(_bookings));
  }

  @override
  Stream<List<HomestayBooking>> watchMyHomestayBookings(String guestId) async* {
    List<HomestayBooking> mine() => _bookings.where((b) => b.guestId == guestId).toList();
    yield mine();
    yield* _controller.stream.map((_) => mine());
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/homestay_booking_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze lib/data test/support/fakes.dart test/data/homestay_booking_repository_test.dart
git add lib/data/repositories/homestay_booking_repository.dart test/support/fakes.dart test/data/homestay_booking_repository_test.dart
git commit -m "feat: add HomestayBookingRepository interface + in-memory fake"
```

---

### Task 3: `FirestoreHomestayBookingRepository`

**Files:**
- Create: `lib/data/repositories/firebase/firestore_homestay_booking_repository.dart`

**Interfaces:**
- Consumes: `HomestayBookingRepository`, `HomestayBooking` (Tasks 1–2).
- Produces: `FirestoreHomestayBookingRepository` (verified on the emulator in Task 8).

- [ ] **Step 1: Create `firestore_homestay_booking_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/homestay_booking.dart';
import '../homestay_booking_repository.dart';

class FirestoreHomestayBookingRepository implements HomestayBookingRepository {
  final FirebaseFirestore _db;
  FirestoreHomestayBookingRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('homestayBookings');

  @override
  Future<void> createHomestayBooking(HomestayBooking booking) => _col.add({
        ...booking.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  @override
  Stream<List<HomestayBooking>> watchMyHomestayBookings(String guestId) => _col
      .where('guestId', isEqualTo: guestId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => HomestayBooking.fromMap(d.id, d.data())).toList());
}
```

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze lib/data/repositories/firebase
git add lib/data/repositories/firebase/firestore_homestay_booking_repository.dart
git commit -m "feat: add FirestoreHomestayBookingRepository"
```

---

### Task 4: `homestayBookingRepositoryProvider`

**Files:**
- Modify: `lib/data/repositories/providers.dart`

**Interfaces:**
- Consumes: `HomestayBookingRepository`, `FirestoreHomestayBookingRepository`.
- Produces: `homestayBookingRepositoryProvider` → `Provider<HomestayBookingRepository>`.

No dedicated unit test — this is a trivial provider returning a Firestore impl (instantiating `FirebaseFirestore.instance` in a plain unit test is undesirable). It is exercised by the screen tests (which override it) in Tasks 5–6 and the emulator integration test in Task 8. The existing `myPetsProvider` (from Slice 4b) is reused as-is for the pet selector.

- [ ] **Step 1: Extend `lib/data/repositories/providers.dart`**

Add these imports next to the existing ones: `import 'homestay_booking_repository.dart';` and `import 'firebase/firestore_homestay_booking_repository.dart';`. Then append:

```dart
final homestayBookingRepositoryProvider =
    Provider<HomestayBookingRepository>((ref) => FirestoreHomestayBookingRepository());
```

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze lib/data
git add lib/data/repositories/providers.dart
git commit -m "feat: add homestayBookingRepositoryProvider"
```

---

### Task 5: `HostAcceptedScreen` + route constants + `/host-accepted` route

**Files:**
- Create: `lib/features/homestay/host_accepted_screen.dart`
- Modify: `lib/core/router/routes.dart` (add `hostRequest`, `hostAccepted`)
- Modify: `lib/core/router/app_router.dart` (import + protect both + add `/host-accepted` route)
- Test: `test/features/host_accepted_screen_test.dart`

**Interfaces:**
- Consumes: `HomestayBooking`, `showComingSoon`, `PgImageSlot`, theme, `Routes`.
- Produces: `HostAcceptedScreen({HomestayBooking? booking})` — a `StatelessWidget`; `Routes.hostRequest == '/host-request'`, `Routes.hostAccepted == '/host-accepted'`.

`HostAcceptedScreen` is built before `HomestayRequestScreen` (Task 6) so the request screen's "Send request" navigation target exists and is testable.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/host_accepted_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/features/homestay/host_accepted_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the request-sent summary; Message hints coming soon', (tester) async {
    final b = HomestayBooking(guestId: 'g1', hostId: 'h1', homeName: "Meera's Home",
        hostName: 'Meera Iyer', petId: 'p1', petName: 'Bruno', ratePerNight: 900,
        checkIn: DateTime(2026, 7, 12), checkOut: DateTime(2026, 7, 15), nights: 3,
        subtotal: 2700, fee: 150, total: 2850);
    await pumpPg(tester, HostAcceptedScreen(booking: b));
    expect(find.text('Request sent! 🎉'), findsOneWidget);
    expect(find.textContaining('Bruno'), findsOneWidget);
    expect(find.textContaining('3 nights · ₹2850'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
    await tester.tap(find.textContaining('Message Meera'));
    await tester.pump();
    expect(find.text('Chat is coming soon 🐾'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/host_accepted_screen_test.dart`
Expected: FAIL — `HostAcceptedScreen` not found.

- [ ] **Step 3: Add the route constants**

In `lib/core/router/routes.dart`, add inside `class Routes` (after `hostSetup`):
```dart
  static const hostRequest = '/host-request';
  static const hostAccepted = '/host-accepted';
```

- [ ] **Step 4: Implement `lib/features/homestay/host_accepted_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/homestay_booking.dart';

class HostAcceptedScreen extends StatelessWidget {
  final HomestayBooking? booking;
  const HostAcceptedScreen({super.key, this.booking});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final b = booking;
    if (b == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No booking')));
    }
    final hostFirst = b.hostName.split(' ').first;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 30, 30, 24),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 108, height: 108, alignment: Alignment.center,
              decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
              child: Container(
                width: 78, height: 78, alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFFF8B45E), Color(0xFFF0871E)]),
                  shape: BoxShape.circle),
                child: const Text('🏡', style: TextStyle(fontSize: 34)))),
            const SizedBox(height: 20),
            Text('Request sent! 🎉', textAlign: TextAlign.center,
              style: PgText.poppins(25, FontWeight.w800, color: c.text, ls: -0.4)),
            const SizedBox(height: 10),
            Text('$hostFirst will confirm ${b.petName}\'s stay for '
                 '${HomestayBooking.fmtDay(b.checkIn)} – ${HomestayBooking.fmtDay(b.checkOut)} soon.',
              textAlign: TextAlign.center,
              style: PgText.inter(14.5, FontWeight.w400, color: c.muted, height: 1.55)),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const PgImageSlot(size: 46, circle: true, emoji: '🏡'),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.hostName, style: PgText.poppins(14, FontWeight.w700, color: c.text)),
                  Text('${b.nights} nights · ₹${b.total}',
                    style: PgText.inter(12, FontWeight.w400, color: c.muted)),
                ])),
              ]),
            ),
            const Spacer(),
            SizedBox(width: double.infinity, child: GestureDetector(
              onTap: () => showComingSoon(context, 'Chat'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(16)),
                child: Text('Message $hostFirst',
                  style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white))))),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => context.go(Routes.home),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Back to home', style: PgText.inter(14, FontWeight.w600, color: c.muted)))),
          ]),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Wire the route + protect both constants in `app_router.dart`**

In `lib/core/router/app_router.dart`: add `import '../../features/homestay/host_accepted_screen.dart';` and `import '../../data/models/homestay_booking.dart';`; add `Routes.hostRequest, Routes.hostAccepted` to the `_protected` set; add this route after the `Routes.host` route:
```dart
      GoRoute(path: Routes.hostAccepted, builder: (_, state) => HostAcceptedScreen(booking: state.extra as HomestayBooking?)),
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/host_accepted_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add lib/features/homestay/host_accepted_screen.dart lib/core/router/routes.dart lib/core/router/app_router.dart test/features/host_accepted_screen_test.dart
git commit -m "feat: add Host-accepted screen (honest 'Request sent') + homestay booking routes"
```

---

### Task 6: `HomestayRequestScreen` + `/host-request` route + rewire "Request to book"

**Files:**
- Create: `lib/features/homestay/homestay_request_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/host-request` route)
- Modify: `lib/features/homestay/host_profile_screen.dart` (rewire "Request to book"; drop the now-unused `pg_snackbar` import)
- Test: `test/features/homestay_request_screen_test.dart`

**Interfaces:**
- Consumes: `Homestay`, `HomestayBooking`, `PetProfile`, `myPetsProvider`, `authRepositoryProvider`, `homestayBookingRepositoryProvider`, `PgAppBar`, `PgPrimaryButton`, `PgTextField`, `PgImageSlot`, `Routes`.
- Produces: `HomestayRequestScreen({Homestay? homestay})`; the `/host-request` route; the Host-profile "Request to book" button now pushes `Routes.hostRequest`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/homestay_request_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _meera = Homestay(uid: 'h1', homeName: "Meera's Home", hostName: 'Meera Iyer',
    area: 'Bandra West', about: 'x', homeType: HomeType.apartment, ratePerNight: 900);

PetProfile _bruno(String ownerId) => PetProfile(id: 'p1', ownerId: ownerId, name: 'Bruno',
    breed: 'Labrador', ageLabel: '2 yrs', sex: 'male', area: 'Bandra West',
    species: Species.dog, vaccinated: true, accentColor: PetProfile.accentFor('Bruno'));

void main() {
  testWidgets('default 3-night range prices correctly; Send writes a requested booking', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final bookings = InMemoryHomestayBookingRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository([_bruno(auth.currentUser!.uid)])),
      homestayBookingRepositoryProvider.overrideWithValue(bookings),
    ], initialLocation: Routes.hostRequest, extra: _meera);
    await tester.pumpAndSettle();

    expect(find.textContaining('2700'), findsWidgets); // 900 * 3 nights
    expect(find.textContaining('2850'), findsWidgets); // + 150 fee
    expect(find.text('Bruno'), findsOneWidget);

    await tester.tap(find.textContaining('Send request to Meera'));
    await tester.pumpAndSettle();

    final mine = await bookings.watchMyHomestayBookings(auth.currentUser!.uid).first;
    expect(mine.single.petName, 'Bruno');
    expect(mine.single.nights, 3);
    expect(mine.single.total, 2850);
    expect(mine.single.status, 'requested');
    expect(find.text('Request sent! 🎉'), findsOneWidget); // navigated to Host-accepted
  });

  testWidgets('empty pets disables Send', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final bookings = InMemoryHomestayBookingRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(bookings),
    ], initialLocation: Routes.hostRequest, extra: _meera);
    await tester.pumpAndSettle();
    expect(find.text('Add a pet to book'), findsOneWidget);
    await tester.tap(find.textContaining('Send request to Meera'));
    await tester.pumpAndSettle();
    expect(await bookings.watchMyHomestayBookings(auth.currentUser!.uid).first, isEmpty);
  });

  testWidgets('Host profile Request-to-book opens the Request screen', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      homestayBookingRepositoryProvider.overrideWithValue(InMemoryHomestayBookingRepository()),
    ], initialLocation: Routes.host, extra: _meera);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request to book'));
    await tester.pumpAndSettle();
    expect(find.text('Request booking'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/homestay_request_screen_test.dart`
Expected: FAIL — `HomestayRequestScreen` / `/host-request` not found.

- [ ] **Step 3: Implement `lib/features/homestay/homestay_request_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/homestay.dart';
import '../../data/models/homestay_booking.dart';
import '../../data/models/pet_profile.dart';
import '../../data/repositories/providers.dart';

class HomestayRequestScreen extends ConsumerStatefulWidget {
  final Homestay? homestay;
  const HomestayRequestScreen({super.key, this.homestay});
  @override
  ConsumerState<HomestayRequestScreen> createState() => _HomestayRequestScreenState();
}

class _HomestayRequestScreenState extends ConsumerState<HomestayRequestScreen> {
  late DateTime _checkIn;
  late DateTime _checkOut;
  String? _petId;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _checkIn = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    _checkOut = _checkIn.add(const Duration(days: 3));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _nights => HomestayBooking.nightsBetween(_checkIn, _checkOut);

  Future<void> _pickDates() async {
    final today = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 1, today.month, today.day),
      initialDateRange: DateTimeRange(start: _checkIn, end: _checkOut),
    );
    if (range != null && range.duration.inDays >= 1) {
      setState(() {
        _checkIn = DateTime(range.start.year, range.start.month, range.start.day);
        _checkOut = DateTime(range.end.year, range.end.month, range.end.day);
      });
    }
  }

  Future<void> _send(Homestay h, List<PetProfile> pets) async {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    final pet = pets.firstWhere((p) => p.id == _petId, orElse: () => pets.first);
    final nights = _nights;
    final subtotal = h.ratePerNight * nights;
    const fee = HomestayBooking.serviceFee;
    final draft = HomestayBooking(
      guestId: me.uid, hostId: h.uid, homeName: h.homeName, hostName: h.hostName,
      petId: pet.id, petName: pet.name, ratePerNight: h.ratePerNight,
      checkIn: _checkIn, checkOut: _checkOut, nights: nights,
      subtotal: subtotal, fee: fee, total: subtotal + fee, note: _note.text.trim());
    setState(() => _saving = true);
    await ref.read(homestayBookingRepositoryProvider).createHomestayBooking(draft);
    if (mounted) context.go(Routes.hostAccepted, extra: draft);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final h = widget.homestay;
    if (h == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No home selected')));
    }
    final pets = ref.watch(myPetsProvider).value ?? const <PetProfile>[];
    if (pets.isNotEmpty && (_petId == null || !pets.any((p) => p.id == _petId))) {
      _petId = pets.first.id;
    }
    final nights = _nights;
    final subtotal = h.ratePerNight * nights;
    const fee = HomestayBooking.serviceFee;
    final total = subtotal + fee;
    final hostFirst = h.hostName.split(' ').first;
    final nightWord = nights == 1 ? 'night' : 'nights';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Request booking', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const PgImageSlot(size: 52, radius: 14, emoji: '🏡'),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(h.homeName, style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
                      Text('${h.area} · ${h.reviewCount == 0 ? 'New' : '★ ${h.rating.toStringAsFixed(1)}'}',
                        style: PgText.inter(12, FontWeight.w400, color: c.muted)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 20),
                Text('Dates', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                GestureDetector(
                  onTap: _pickDates,
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(15)),
                    child: Row(children: [
                      Icon(Icons.calendar_today, size: 17, color: c.brand),
                      const SizedBox(width: 12),
                      Expanded(child: Text(
                        '${HomestayBooking.fmtDay(_checkIn)} → ${HomestayBooking.fmtDay(_checkOut)}',
                        style: PgText.inter(13.5, FontWeight.w600, color: c.text))),
                      Text('$nights $nightWord', style: PgText.inter(12.5, FontWeight.w600, color: c.muted)),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                Text('For', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                if (pets.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(15)),
                    child: Text('Add a pet to book', style: PgText.inter(14, FontWeight.w600, color: c.muted)))
                else
                  Column(children: [
                    for (final p in pets)
                      GestureDetector(
                        onTap: () => setState(() => _petId = p.id),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: c.surface,
                            border: Border.all(color: _petId == p.id ? c.brand : c.border,
                              width: _petId == p.id ? 2 : 1),
                            borderRadius: BorderRadius.circular(15)),
                          child: Row(children: [
                            const PgImageSlot(size: 44, circle: true),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: PgText.poppins(14, FontWeight.w700, color: c.text)),
                              Text('${p.breed} · ${p.ageLabel}',
                                style: PgText.inter(12, FontWeight.w400, color: c.muted)),
                            ])),
                            if (_petId == p.id) Icon(Icons.check_circle, color: c.brand, size: 22),
                          ]),
                        ),
                      ),
                  ]),
                const SizedBox(height: 8),
                Text('Note to host (optional)', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                PgTextField(label: '', controller: _note, hint: 'Anything the host should know?'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    _priceRow('₹${h.ratePerNight} × $nights $nightWord', '₹$subtotal', c),
                    const SizedBox(height: 9),
                    _priceRow('Service fee', '₹$fee', c),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Container(height: 1, color: c.border)),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Total', style: PgText.poppins(15, FontWeight.w700, color: c.text)),
                      Text('₹$total', style: PgText.poppins(15, FontWeight.w800, color: c.brand)),
                    ]),
                  ]),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(22, 13, 22, 18),
            child: PgPrimaryButton(
              label: _saving ? 'Sending…' : 'Send request to $hostFirst',
              onPressed: (pets.isEmpty || _saving) ? () {} : () => _send(h, pets)),
          ),
        ]),
      ),
    );
  }

  Widget _priceRow(String label, String value, PgColors c) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
        Text(value, style: PgText.inter(13.5, FontWeight.w600, color: c.text)),
      ]);
}
```

- [ ] **Step 4: Add the `/host-request` route**

In `lib/core/router/app_router.dart`: add `import '../../features/homestay/homestay_request_screen.dart';` and this route (next to `Routes.hostAccepted`):
```dart
      GoRoute(path: Routes.hostRequest, builder: (_, state) => HomestayRequestScreen(homestay: state.extra as Homestay?)),
```

- [ ] **Step 5: Rewire "Request to book" in `host_profile_screen.dart`**

Two edits in `lib/features/homestay/host_profile_screen.dart`:
1. Add `import '../../core/router/routes.dart';` and **remove** `import '../../core/widgets/pg_snackbar.dart';` (it becomes unused).
2. Change the bottom button's `onTap` from `() => showComingSoon(context, 'Booking')` to:
```dart
              onTap: () => context.push(Routes.hostRequest, extra: h),
```
(`go_router` is already imported in this file; `h` is the non-null `Homestay` in scope.)

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/homestay_request_screen_test.dart`
Expected: PASS (all three tests).

- [ ] **Step 7: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/homestay/homestay_request_screen.dart lib/core/router/app_router.dart lib/features/homestay/host_profile_screen.dart test/features/homestay_request_screen_test.dart
git commit -m "feat: add Homestay request screen + /host-request; wire Request-to-book to the flow"
```
Expected: whole suite green, analyze clean.

---

### Task 7: Firestore rules for `homestayBookings`; deploy

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Add the `homestayBookings` block to `firestore.rules`**

Inside `match /databases/{database}/documents { ... }`, after the `homestays` block:
```
    match /homestayBookings/{id} {
      allow read: if request.auth != null
                  && (resource.data.guestId == request.auth.uid
                      || resource.data.hostId == request.auth.uid);
      allow create: if request.auth != null
                  && request.resource.data.guestId == request.auth.uid;
      allow update, delete: if false;
    }
```

- [ ] **Step 2: Deploy the rules**

Run: `firebase deploy --only firestore:rules --project pet-aggregator-app`
Expected: `Deploy complete!`

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "chore: add + deploy Firestore rules for homestayBookings (guest-create, guest/host-read)"
```

---

### Task 8: Emulator integration test + final verification

**Files:**
- Modify: `integration_test/firebase_repos_test.dart` (add a `homestayBookings` round-trip test)

- [ ] **Step 1: Append a homestayBookings test to `integration_test/firebase_repos_test.dart`**

Add `import 'package:pet_aggregator_app/data/models/homestay_booking.dart';` and `import 'package:pet_aggregator_app/data/repositories/firebase/firestore_homestay_booking_repository.dart';` with the other imports, then add this `testWidgets` inside `main()`:
```dart
  testWidgets('homestayBookings create + watch round-trip (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final repo = FirestoreHomestayBookingRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'hb_$stamp@x.com', password: 'secret1');

    await repo.createHomestayBooking(HomestayBooking(guestId: me.uid, hostId: 'host_$stamp',
        homeName: "Meera's Home", hostName: 'Meera Iyer', petId: 'pet_$stamp', petName: 'Bruno',
        ratePerNight: 900, checkIn: DateTime(2026, 7, 12), checkOut: DateTime(2026, 7, 15),
        nights: 3, subtotal: 2700, fee: 150, total: 2850, note: 'Friendly boy'));
    final mine = await repo.watchMyHomestayBookings(me.uid).firstWhere((l) => l.isNotEmpty);
    expect(mine.single.petName, 'Bruno');
    expect(mine.single.total, 2850);
    expect(mine.single.status, 'requested');
    expect(mine.single.checkIn, DateTime(2026, 7, 12));

    await auth.signOut();
  });
```

- [ ] **Step 2: Start emulators + run the integration test**

```bash
firebase emulators:start --only auth,firestore --project pet-aggregator-app   # one terminal
flutter test integration_test/firebase_repos_test.dart -d emulator-5554        # another
```
Expected: all integration tests pass. (If an emulator is already running on ports 8080/9099, reuse it — the Firestore emulator hot-reloads `firestore.rules`.) Stop the emulators after if you started them.

- [ ] **Step 3: Full green gate**

```bash
flutter test
flutter analyze
flutter build apk --debug
```
Expected: unit/widget tests pass, analyze clean, APK builds.

- [ ] **Step 4: Manual walkthrough (real cloud)**

Run: `flutter run -d emulator-5554`. Sign in as a pet-parent account with at least one pet → Home 🏡 Homestay → open a host → "Request to book" → pick a date range, pick the pet, add a note → "Send request" → the "Request sent!" screen shows the summary. Confirm a `homestayBookings/{id}` doc exists in the console with `status: 'requested'`.

- [ ] **Step 5: Commit**

```bash
git add integration_test/firebase_repos_test.dart
git commit -m "test: verify homestayBookings create/watch against Firestore emulators"
```

---

## Self-Review

**Spec coverage:**
- `homestayBookings` collection + `HomestayBooking` model → Tasks 1, 3. ✓
- `HomestayBookingRepository` + fake + Firestore + provider → Tasks 2–4. ✓
- HomestayRequestScreen (date range / pet / note / price; writes `requested` booking) → Task 6. ✓
- HostAcceptedScreen (honest "Request sent" + summary + Message/Back) → Task 5. ✓
- Rewire "Request to book" → Task 6. ✓
- Routes (`hostRequest`, `hostAccepted`) + create-only rules + deploy → Tasks 5, 7. ✓
- Reuse `myPetsProvider` → Task 6 (no new provider needed for pets). ✓
- TDD fakes + emulator integration → each task + Task 8. ✓
- Out-of-scope (payment/Razorpay, host-accept update, My-bookings UI, chat, reviews, availability) → none implemented; rules stay create-only. ✓

**Placeholder scan:** No "TBD/TODO". Every code step is complete. "Message" intentionally calls `showComingSoon` (chat is Phase 7). The `showDateRangePicker` dialog interaction is not unit-tested; tests assert the deterministic default 3-night range/total (check-in tomorrow → +3 days is always 3 nights regardless of run date).

**Type consistency:**
- `HomestayBooking` fields (`id, guestId, hostId, homeName, hostName, petId, petName, ratePerNight, checkIn, checkOut, nights, subtotal, fee, total, note, status`) + `serviceFee`/`nightsBetween`/`fmtDay` identical across Task 1 (model), Task 2 (fake test), Task 5 (accepted screen), Task 6 (request screen), Task 8 (integration). ✓
- `HomestayBookingRepository` methods (`createHomestayBooking`, `watchMyHomestayBookings`) match between interface (Task 2), fake (Task 2), Firestore (Task 3), provider (Task 4), and callers (Tasks 6, 8). ✓
- `homestayBookingRepositoryProvider` defined Task 4, consumed Task 6. `myPetsProvider` reused (defined in Slice 4b). ✓
- `Routes.hostRequest`/`Routes.hostAccepted` added Task 5, used Task 5 (`/host-accepted` route + `_protected`), Task 6 (`/host-request` route, `context.push` from host profile, `context.go(hostAccepted)` from request screen). ✓
- Host-profile rewire drops the now-unused `pg_snackbar` import and adds `routes.dart` (Task 6) — prevents an unused-import analyzer error. ✓
- `showComingSoon(context, label)` reused in Task 5 (Chat). `myPetsProvider` empty-state disables the send button (Task 6), mirroring Slice 4b's `BookingScreen`. ✓
