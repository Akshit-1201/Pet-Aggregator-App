# Pawgo Slice 4b: Services — Booking & Payment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a pet parent book a pro end to end on live Firestore — pick date/time/pet → UI-only payment → a real `bookings/{id}` doc → confirmation — wiring the "Book" buttons Slice 4a left as coming-soon.

**Architecture:** Feature-first Flutter on the existing repository seam. A new `Booking` model + `BookingRepository` (interface + Firestore impl + fake) backs `bookings`. The three booking screens pass a `Booking` draft between them via go_router `extra`; the payment step persists it. Tests use in-memory fakes via `pumpPgApp`; the emulator integration test covers the real Firestore path. Razorpay is deferred (Phase 10) — "Pay" writes the booking, no charge.

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `cloud_firestore`, `flutter_riverpod`, `go_router`, `google_fonts`. **No new packages.**

**Spec:** `docs/superpowers/specs/2026-07-12-pawgo-services-4b-booking-payment-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **Live Firestore, no mock data.** UI/tests depend only on repository interfaces; never import `cloud_firestore`/`firebase_auth` outside `data/repositories/firebase/`, `lib/main.dart`, and `integration_test/`.
- **Payment is UI-only** (Razorpay = Phase 10): "Pay" writes a `bookings` doc with `status: 'confirmed'`, no charge. Out of scope: a My-bookings list UI, reviews, chat, real scheduling.
- Riverpod 3.x: `AsyncValue.value` (not `valueOrNull`); tests import `Override` from `package:flutter_riverpod/misc.dart`; prefer a repo stream's `.first` over `StreamProvider.future`.
- `go_router` builders use `(_, _)`; routes reading `extra` use `(_, state)`. Screen tests use `pumpPgApp`. Any plain `test()` touching `GoogleFonts` uses `testWidgets`.
- Firestore writes set `createdAt` via `FieldValue.serverTimestamp()` in the repository, never in model `toMap()`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: `Booking` model

**Files:**
- Create: `lib/data/models/booking.dart`
- Test: `test/data/booking_test.dart`

**Interfaces:**
- Produces: `class Booking { final String id, parentId, proId, proName, petId, petName; final ServiceType serviceType; final int rate, fee, total; final String dateLabel, timeSlot, status; const Booking({this.id='', required ..., this.status='confirmed'}); static int feeFor(int rate); Map<String,dynamic> toMap(); factory Booking.fromMap(String id, Map<String,dynamic>); }` (reuses `ServiceType` from `pro.dart`).

- [ ] **Step 1: Write the failing test**

```dart
// test/data/booking_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

void main() {
  test('feeFor is 10% rounded; total helper math', () {
    expect(Booking.feeFor(250), 25);
    expect(Booking.feeFor(255), 26); // 25.5 -> 26
  });

  test('toMap omits id/createdAt; fromMap restores', () {
    const b = Booking(parentId: 'u1', proId: 'p1', proName: 'Aarav', petId: 'pet1',
        petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25, total: 275,
        dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM');
    final m = b.toMap();
    expect(m.containsKey('id'), isFalse);
    expect(m.containsKey('createdAt'), isFalse);
    expect(m['serviceType'], 'walker');
    expect(m['total'], 275);
    expect(m['status'], 'confirmed');
    final back = Booking.fromMap('b1', m);
    expect(back.id, 'b1');
    expect(back.proName, 'Aarav');
    expect(back.timeSlot, '5:00 PM');
    expect(back.serviceType, ServiceType.walker);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/booking_test.dart`
Expected: FAIL — `Booking` not found.

- [ ] **Step 3: Implement `lib/data/models/booking.dart`**

```dart
import 'pro.dart';

class Booking {
  final String id, parentId, proId, proName, petId, petName;
  final ServiceType serviceType;
  final int rate, fee, total;
  final String dateLabel, timeSlot, status;

  const Booking({
    this.id = '',
    required this.parentId, required this.proId, required this.proName,
    required this.petId, required this.petName, required this.serviceType,
    required this.rate, required this.fee, required this.total,
    required this.dateLabel, required this.timeSlot, this.status = 'confirmed',
  });

  static int feeFor(int rate) => (rate * 0.1).round();

  Map<String, dynamic> toMap() => {
        'parentId': parentId,
        'proId': proId,
        'proName': proName,
        'petId': petId,
        'petName': petName,
        'serviceType': serviceType.storageKey,
        'rate': rate,
        'fee': fee,
        'total': total,
        'dateLabel': dateLabel,
        'timeSlot': timeSlot,
        'status': status,
      };

  factory Booking.fromMap(String id, Map<String, dynamic> m) => Booking(
        id: id,
        parentId: (m['parentId'] ?? '') as String,
        proId: (m['proId'] ?? '') as String,
        proName: (m['proName'] ?? '') as String,
        petId: (m['petId'] ?? '') as String,
        petName: (m['petName'] ?? '') as String,
        serviceType: ServiceType.fromStorage((m['serviceType'] ?? 'walker') as String),
        rate: (m['rate'] ?? 0) as int,
        fee: (m['fee'] ?? 0) as int,
        total: (m['total'] ?? 0) as int,
        dateLabel: (m['dateLabel'] ?? '') as String,
        timeSlot: (m['timeSlot'] ?? '') as String,
        status: (m['status'] ?? 'confirmed') as String,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/booking_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze lib/data/models/booking.dart
git add lib/data/models/booking.dart test/data/booking_test.dart
git commit -m "feat: add Booking model with Firestore serialization + feeFor"
```

---

### Task 2: `BookingRepository` interface + in-memory fake

**Files:**
- Create: `lib/data/repositories/booking_repository.dart`
- Modify: `test/support/fakes.dart` (add `InMemoryBookingRepository`)
- Test: `test/data/booking_repository_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class BookingRepository { Future<void> createBooking(Booking booking); Stream<List<Booking>> watchMyBookings(String parentId); }`
  - `InMemoryBookingRepository` fake.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/booking_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import '../support/fakes.dart';

void main() {
  test('InMemoryBookingRepository creates and streams my bookings', () async {
    final repo = InMemoryBookingRepository();
    expect(await repo.watchMyBookings('u1').first, isEmpty);
    await repo.createBooking(const Booking(parentId: 'u1', proId: 'p1', proName: 'Aarav',
        petId: 'pet1', petName: 'Bruno', serviceType: ServiceType.walker,
        rate: 250, fee: 25, total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM'));
    // Another parent's booking is not mine.
    await repo.createBooking(const Booking(parentId: 'other', proId: 'p1', proName: 'Aarav',
        petId: 'x', petName: 'Y', serviceType: ServiceType.walker,
        rate: 250, fee: 25, total: 275, dateLabel: 'Wed', timeSlot: '8:00 AM'));
    final mine = await repo.watchMyBookings('u1').first;
    expect(mine.length, 1);
    expect(mine.single.petName, 'Bruno');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/booking_repository_test.dart`
Expected: FAIL — types not found.

- [ ] **Step 3: Create `lib/data/repositories/booking_repository.dart`**

```dart
import '../models/booking.dart';

abstract interface class BookingRepository {
  Future<void> createBooking(Booking booking);
  Stream<List<Booking>> watchMyBookings(String parentId);
}
```

- [ ] **Step 4: Add `InMemoryBookingRepository` to `test/support/fakes.dart`**

Add imports at the top: `import 'package:pet_aggregator_app/data/models/booking.dart';` and `import 'package:pet_aggregator_app/data/repositories/booking_repository.dart';`. Then append:

```dart
class InMemoryBookingRepository implements BookingRepository {
  final List<Booking> _bookings = [];
  final _controller = StreamController<List<Booking>>.broadcast();

  @override
  Future<void> createBooking(Booking booking) async {
    _bookings.add(booking);
    _controller.add(List.of(_bookings));
  }

  @override
  Stream<List<Booking>> watchMyBookings(String parentId) async* {
    List<Booking> mine() => _bookings.where((b) => b.parentId == parentId).toList();
    yield mine();
    yield* _controller.stream.map((_) => mine());
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/booking_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze lib/data
git add lib/data/repositories/booking_repository.dart test/support/fakes.dart test/data/booking_repository_test.dart
git commit -m "feat: add BookingRepository interface + in-memory fake"
```

---

### Task 3: `FirestoreBookingRepository`

**Files:**
- Create: `lib/data/repositories/firebase/firestore_booking_repository.dart`

**Interfaces:**
- Consumes: `BookingRepository`, `Booking` (Tasks 1–2).
- Produces: `FirestoreBookingRepository` (verified on the emulator in Task 10).

- [ ] **Step 1: Create `firestore_booking_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/booking.dart';
import '../booking_repository.dart';

class FirestoreBookingRepository implements BookingRepository {
  final FirebaseFirestore _db;
  FirestoreBookingRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('bookings');

  @override
  Future<void> createBooking(Booking booking) => _col.add({
        ...booking.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  @override
  Stream<List<Booking>> watchMyBookings(String parentId) => _col
      .where('parentId', isEqualTo: parentId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Booking.fromMap(d.id, d.data())).toList());
}
```

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze lib/data/repositories/firebase
git add lib/data/repositories/firebase/firestore_booking_repository.dart
git commit -m "feat: add FirestoreBookingRepository"
```

---

### Task 4: Providers — `bookingRepositoryProvider`, `myPetsProvider`

**Files:**
- Modify: `lib/data/repositories/providers.dart`
- Test: `test/data/my_pets_provider_test.dart`

**Interfaces:**
- Produces:
  - `bookingRepositoryProvider` → `Provider<BookingRepository>`
  - `myPetsProvider` → `StreamProvider<List<PetProfile>>` (the signed-in user's own pets).

- [ ] **Step 1: Write the failing test**

```dart
// test/data/my_pets_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('myPetsProvider streams the signed-in user\'s own pets', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('uid_me@x.com'))),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(myPetsProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();
    final pets = container.read(myPetsProvider).value ?? [];
    expect(pets, isNotEmpty);
    expect(pets.every((p) => p.ownerId == 'uid_me@x.com'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/my_pets_provider_test.dart`
Expected: FAIL — providers not defined.

- [ ] **Step 3: Append to `lib/data/repositories/providers.dart`**

Add imports at the top: `import '../models/booking.dart';`, `import 'booking_repository.dart';`, `import 'firebase/firestore_booking_repository.dart';`. Then append:

```dart
final bookingRepositoryProvider =
    Provider<BookingRepository>((ref) => FirestoreBookingRepository());

final myPetsProvider = StreamProvider<List<PetProfile>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(petRepositoryProvider).watchMyPets(user.uid);
});
```
> `Booking` is imported so the file references it via `bookingRepositoryProvider`'s type indirectly; if analyze flags the `booking.dart` import as unused, drop it (only `booking_repository.dart` + the Firestore impl are strictly needed).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/my_pets_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
flutter analyze lib/data
git add lib/data/repositories/providers.dart test/data/my_pets_provider_test.dart
git commit -m "feat: add bookingRepositoryProvider + myPetsProvider"
```

---

### Task 5: `BookingScreen` + `/booking` route

**Files:**
- Create: `lib/features/services/booking_screen.dart`
- Modify: `lib/core/router/routes.dart` (add `booking`, `payment`, `bookingConfirmed`)
- Modify: `lib/core/router/app_router.dart` (import + protect + `/booking` route)
- Test: `test/features/booking_screen_test.dart`

**Interfaces:**
- Consumes: `myPetsProvider`, `authRepositoryProvider`, `Pro`, `Booking`, `PetProfile`, `PgAppBar`, `PgPrimaryButton`, `Routes`.
- Produces: `BookingScreen({Pro? pro})`; `Routes.booking == '/booking'`, `Routes.payment == '/payment'`, `Routes.bookingConfirmed == '/booking-confirmed'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/booking_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/services/booking_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
    serviceType: ServiceType.walker, rate: 250, experienceYears: 4);

void main() {
  testWidgets('renders total and the pet; Continue enabled with a pet', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('uid_me@x.com'))),
    ], initialLocation: Routes.booking, extra: _pro);
    await tester.pumpAndSettle();
    expect(find.text('Bruno'), findsOneWidget);          // first of the user's pets
    expect(find.textContaining('275'), findsWidgets);    // total = 250 + 25
    expect(find.text('Continue to payment'), findsOneWidget);
  });

  testWidgets('with no pets, prompts to add one', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    ], initialLocation: Routes.booking, extra: _pro);
    await tester.pumpAndSettle();
    expect(find.text('Add a pet to book'), findsOneWidget);
  });
}
```
> `pumpPgApp` needs an `extra` parameter (added in this task's Step 4).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/booking_screen_test.dart`
Expected: FAIL — `BookingScreen` / `Routes.booking` / `pumpPgApp` extra not found.

- [ ] **Step 3: Add route constants**

In `lib/core/router/routes.dart`, add inside `class Routes`:
```dart
  static const booking = '/booking';
  static const payment = '/payment';
  static const bookingConfirmed = '/booking-confirmed';
```

- [ ] **Step 4: Add an `extra` parameter to `pumpPgApp`**

In `test/support/pump.dart`, change the `pumpPgApp` signature to accept `Object? extra` and pass it to `buildRouter`'s initial navigation. Replace the `buildRouter(...)` + `pumpWidget` section with:
```dart
  final router = buildRouter(auth: auth, initialLocation: initialLocation);
  addTearDown(router.dispose);
  if (extra != null) {
    // Re-navigate with extra now that the router exists (initialLocation can't carry extra).
    router.go(initialLocation, extra: extra);
  }
```
and add `Object? extra,` to the parameter list (after `String initialLocation = Routes.splash,`).

- [ ] **Step 5: Implement `booking_screen.dart`**

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
import '../../data/models/booking.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/pro.dart';
import '../../data/repositories/providers.dart';

const _times = ['8:00 AM', '5:00 PM', '6:30 PM'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class BookingScreen extends ConsumerStatefulWidget {
  final Pro? pro;
  const BookingScreen({super.key, this.pro});
  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  int _dateIndex = 0;
  int _timeIndex = 1;
  String? _petId;

  List<DateTime> get _days => List.generate(4, (i) => DateTime.now().add(Duration(days: i)));
  String _label(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  void _continue(Pro pro, List<PetProfile> pets) {
    final me = ref.read(authRepositoryProvider).currentUser;
    final pet = pets.firstWhere((p) => p.id == _petId, orElse: () => pets.first);
    if (me == null) return;
    final fee = Booking.feeFor(pro.rate);
    context.push(Routes.payment, extra: Booking(
      parentId: me.uid, proId: pro.uid, proName: pro.name, petId: pet.id, petName: pet.name,
      serviceType: pro.serviceType, rate: pro.rate, fee: fee, total: pro.rate + fee,
      dateLabel: _label(_days[_dateIndex]), timeSlot: _times[_timeIndex]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final pro = widget.pro;
    if (pro == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No pro selected')));
    }
    final pets = ref.watch(myPetsProvider).value ?? const <PetProfile>[];
    if (pets.isNotEmpty && (_petId == null || !pets.any((p) => p.id == _petId))) {
      _petId = pets.first.id;
    }
    final fee = Booking.feeFor(pro.rate);
    final total = pro.rate + fee;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Book a ${pro.serviceType.label}', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              children: [
                Text('Select date', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                Row(children: [
                  for (var i = 0; i < _days.length; i++) ...[
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => _dateIndex = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _dateIndex == i ? c.brand : c.surface,
                          border: _dateIndex == i ? null : Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(15)),
                        child: Column(children: [
                          Text(_weekdays[_days[i].weekday - 1].toUpperCase(),
                            style: PgText.inter(11, FontWeight.w600,
                              color: _dateIndex == i ? Colors.white70 : c.faint)),
                          const SizedBox(height: 3),
                          Text('${_days[i].day}',
                            style: PgText.poppins(17, FontWeight.w800,
                              color: _dateIndex == i ? Colors.white : c.text)),
                        ]),
                      ),
                    )),
                    if (i != _days.length - 1) const SizedBox(width: 9),
                  ],
                ]),
                const SizedBox(height: 20),
                Text('Select time', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (var i = 0; i < _times.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _timeIndex = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
                        decoration: BoxDecoration(
                          color: _timeIndex == i ? c.brand : c.surface,
                          border: _timeIndex == i ? null : Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(13)),
                        child: Text(_times[i], style: PgText.inter(13.5, FontWeight.w600,
                          color: _timeIndex == i ? Colors.white : c.text)),
                      ),
                    ),
                ]),
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
                    for (final p in pets) ...[
                      GestureDetector(
                        onTap: () => setState(() => _petId = p.id),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.surface,
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
                    ],
                  ]),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    _priceRow('${pro.serviceType.label} (${pro.unit})', '₹${pro.rate}', c),
                    const SizedBox(height: 9),
                    _priceRow('Pawgo service fee', '₹$fee', c),
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
              label: 'Continue to payment',
              onPressed: pets.isEmpty ? () {} : () => _continue(pro, pets)),
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

- [ ] **Step 6: Wire the `/booking` route**

In `lib/core/router/app_router.dart`: add `import '../../features/services/booking_screen.dart';`, add `Routes.booking, Routes.payment, Routes.bookingConfirmed` to the `_protected` set, and add the route (near the other top-level routes):
```dart
      GoRoute(path: Routes.booking, builder: (_, state) => BookingScreen(pro: state.extra as Pro?)),
```

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/features/booking_screen_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
flutter analyze
git add lib/features/services/booking_screen.dart lib/core/router/routes.dart lib/core/router/app_router.dart test/support/pump.dart test/features/booking_screen_test.dart
git commit -m "feat: add Booking screen (date/time/pet + price) + /booking route; pumpPgApp extra"
```

---

### Task 6: `PaymentScreen` + `/payment` route

**Files:**
- Create: `lib/features/services/payment_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/payment` route)
- Test: `test/features/payment_screen_test.dart`

**Interfaces:**
- Consumes: `bookingRepositoryProvider`, `Booking`, `PgAppBar`, `Routes`.
- Produces: `PaymentScreen({Booking? draft})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/payment_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _draft = Booking(parentId: 'uid_me@x.com', proId: 'pro1', proName: 'Aarav Sharma',
    petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25,
    total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM');

void main() {
  testWidgets('Pay writes a real booking and shows the confirmation', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final bookings = InMemoryBookingRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      bookingRepositoryProvider.overrideWithValue(bookings),
    ], initialLocation: Routes.payment, extra: _draft);
    await tester.pumpAndSettle();

    expect(find.textContaining('275'), findsWidgets);
    await tester.tap(find.textContaining('Pay'));
    await tester.pumpAndSettle();

    final mine = await bookings.watchMyBookings('uid_me@x.com').first;
    expect(mine.single.petName, 'Bruno');
    expect(find.text('Booking confirmed! 🎉'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/payment_screen_test.dart`
Expected: FAIL — `PaymentScreen` not found.

- [ ] **Step 3: Implement `payment_screen.dart`**

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

class PaymentScreen extends ConsumerStatefulWidget {
  final Booking? draft;
  const PaymentScreen({super.key, this.draft});
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  bool _paying = false;

  Future<void> _pay(Booking draft) async {
    setState(() => _paying = true);
    await ref.read(bookingRepositoryProvider).createBooking(draft);
    if (mounted) context.go(Routes.bookingConfirmed, extra: draft);
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
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF2C241E), Color(0xFF5A3D2C)]),
                    borderRadius: BorderRadius.circular(20), boxShadow: c.shadow),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('PAWGO PAY', style: PgText.inter(12, FontWeight.w500,
                        color: Colors.white).copyWith(letterSpacing: 1)),
                      Text('VISA', style: PgText.poppins(15, FontWeight.w800, color: Colors.white)),
                    ]),
                    const SizedBox(height: 24),
                    Text('•••• •••• •••• 4421', style: PgText.poppins(19, FontWeight.w600,
                      color: Colors.white).copyWith(letterSpacing: 2)),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Card on file', style: PgText.inter(12, FontWeight.w400, color: Colors.white70)),
                      Text('09/28', style: PgText.inter(12, FontWeight.w400, color: Colors.white70)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 18),
                Text('Other options', style: PgText.sectionHeader(context)),
                const SizedBox(height: 11),
                _option('📱', 'UPI', 'GPay · PhonePe · Paytm', c),
                const SizedBox(height: 11),
                _option('💵', 'Pawgo Wallet', 'Balance ₹1,540', c),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(22, 13, 22, 18),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total', style: PgText.inter(12, FontWeight.w400, color: c.faint)),
                Text('₹${draft.total}', style: PgText.poppins(20, FontWeight.w800, color: c.text)),
              ]),
              const SizedBox(width: 14),
              Expanded(child: GestureDetector(
                onTap: _paying ? null : () => _pay(draft),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.brand, c.brand2]),
                    borderRadius: BorderRadius.circular(16)),
                  child: Text(_paying ? 'Paying…' : 'Pay ₹${draft.total}',
                    style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white))))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _option(String emoji, String title, String sub, PgColors c) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(15)),
        child: Row(children: [
          Container(width: 38, height: 38, alignment: Alignment.center,
            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(11)),
            child: Text(emoji, style: const TextStyle(fontSize: 17))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: PgText.inter(14, FontWeight.w700, color: c.text)),
            Text(sub, style: PgText.inter(12, FontWeight.w400, color: c.muted)),
          ])),
          Container(width: 20, height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.border, width: 2))),
        ]),
      );
}
```

- [ ] **Step 4: Wire the `/payment` route**

In `lib/core/router/app_router.dart`: add `import '../../features/services/payment_screen.dart';` and the route:
```dart
      GoRoute(path: Routes.payment, builder: (_, state) => PaymentScreen(draft: state.extra as Booking?)),
```
Add `import '../../data/models/booking.dart';` to `app_router.dart` for the cast.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/payment_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze
git add lib/features/services/payment_screen.dart lib/core/router/app_router.dart test/features/payment_screen_test.dart
git commit -m "feat: add Payment screen (UI-only) that writes a real booking + /payment route"
```

---

### Task 7: `BookingConfirmedScreen` + `/booking-confirmed` route

**Files:**
- Create: `lib/features/services/booking_confirmed_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/booking-confirmed` route)
- Test: `test/features/booking_confirmed_screen_test.dart`

**Interfaces:**
- Consumes: `Booking`, `showComingSoon`, `Routes`.
- Produces: `BookingConfirmedScreen({Booking? booking})` (`StatelessWidget`).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/booking_confirmed_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/features/services/booking_confirmed_screen.dart';
import '../support/pump.dart';

const _booking = Booking(id: 'b1', parentId: 'u1', proId: 'pro1', proName: 'Aarav Sharma',
    petId: 'p1', petName: 'Bruno', serviceType: ServiceType.walker, rate: 250, fee: 25,
    total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM');

void main() {
  testWidgets('shows the confirmation summary; Message hints coming soon', (tester) async {
    await pumpPg(tester, const BookingConfirmedScreen(booking: _booking));
    expect(find.text('Booking confirmed! 🎉'), findsOneWidget);
    expect(find.textContaining('Aarav'), findsWidgets);
    expect(find.textContaining('Bruno'), findsWidgets);
    await tester.tap(find.textContaining('Message'));
    await tester.pump();
    expect(find.text('Chat is coming soon 🐾'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/booking_confirmed_screen_test.dart`
Expected: FAIL — `BookingConfirmedScreen` not found.

- [ ] **Step 3: Implement `booking_confirmed_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/booking.dart';

class BookingConfirmedScreen extends StatelessWidget {
  final Booking? booking;
  const BookingConfirmedScreen({super.key, this.booking});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final b = booking;
    if (b == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No booking')));
    }
    final proFirst = b.proName.split(' ').first;
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
                  gradient: LinearGradient(colors: [Color(0xFFF8B45E), Color(0xFFF59E2E)]),
                  shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 40))),
            const SizedBox(height: 20),
            Text('Booking confirmed! 🎉', textAlign: TextAlign.center,
              style: PgText.poppins(25, FontWeight.w800, color: c.text, ls: -0.4)),
            const SizedBox(height: 10),
            Text('$proFirst will ${b.serviceType.label.toLowerCase()} ${b.petName} on '
                 '${b.dateLabel}, ${b.timeSlot}. You\'ll get a reminder.',
              textAlign: TextAlign.center,
              style: PgText.inter(14.5, FontWeight.w400, color: c.muted, height: 1.55)),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const PgImageSlot(size: 46, circle: true, emoji: '🧑'),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.proName, style: PgText.poppins(14, FontWeight.w700, color: c.text)),
                  Text('${b.serviceType.label} · ₹${b.total} paid',
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
                child: Text('Message $proFirst', style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white))))),
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

- [ ] **Step 4: Wire the `/booking-confirmed` route**

In `lib/core/router/app_router.dart`: add `import '../../features/services/booking_confirmed_screen.dart';` and the route:
```dart
      GoRoute(path: Routes.bookingConfirmed, builder: (_, state) => BookingConfirmedScreen(booking: state.extra as Booking?)),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/booking_confirmed_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze
git add lib/features/services/booking_confirmed_screen.dart lib/core/router/app_router.dart test/features/booking_confirmed_screen_test.dart
git commit -m "feat: add Booking confirmed screen + /booking-confirmed route"
```

---

### Task 8: Wire the "Book" buttons to the booking flow

**Files:**
- Modify: `lib/features/services/pro_profile_screen.dart` ("Book" → `/booking`)
- Modify: `lib/features/services/services_list_screen.dart` (card "Book" chip → `/booking`)
- Modify: `test/features/pro_profile_screen_test.dart` (Book now navigates, not a snackbar)
- Test: `test/features/services_booking_wire_test.dart`

**Interfaces:**
- Consumes: `Routes`, `Pro`.

- [ ] **Step 1: Rewire `pro_profile_screen.dart`**

Add `import '../../core/router/routes.dart';` if missing, and change the Book button's `onTap` from `() => showComingSoon(context, 'Booking')` to:
```dart
              onTap: () => context.push(Routes.booking, extra: p),
```
(The chat button keeps `showComingSoon(context, 'Chat')`.)

- [ ] **Step 2: Rewire `services_list_screen.dart`**

In `_ProCard`, change the "Book" chip `onTap` from `() => showComingSoon(context, 'Booking')` to:
```dart
              onTap: () => context.push(Routes.booking, extra: pro),
```
`showComingSoon` may now be unused in this file — remove its import if `flutter analyze` flags it.

- [ ] **Step 3: Update `pro_profile_screen_test.dart`**

Replace the Book-snackbar assertion. The render test should tap the **chat** button instead (still a snackbar). Change the body after the render expects to:
```dart
    await tester.tap(find.text('💬'));
    await tester.pump();
    expect(find.text('Chat is coming soon 🐾'), findsOneWidget);
```
(Remove the old `find.textContaining('Book')` tap + `'Booking is coming soon'` expectation.)

- [ ] **Step 4: Write the navigation wire test**

```dart
// test/features/services_booking_wire_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
    serviceType: ServiceType.walker, rate: 250, experienceYears: 4);

void main() {
  testWidgets('Book on the pro profile opens the booking screen', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('uid_me@x.com'))),
    ], initialLocation: Routes.servicePro, extra: _pro);
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Book'));
    await tester.pumpAndSettle();
    expect(find.text('Select date'), findsOneWidget); // BookingScreen
  });
}
```

- [ ] **Step 5: Run tests to verify pass**

Run: `flutter test test/features/services_booking_wire_test.dart test/features/pro_profile_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/services/pro_profile_screen.dart lib/features/services/services_list_screen.dart test/features/pro_profile_screen_test.dart test/features/services_booking_wire_test.dart
git commit -m "feat: wire Book buttons (pro profile + list card) to the booking flow"
```
Expected: whole suite green, analyze clean.

---

### Task 9: Firestore rules for `bookings`; deploy

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Add the `bookings` block to `firestore.rules`**

Inside `match /databases/{database}/documents { ... }`, after the `pros` block:
```
    match /bookings/{id} {
      allow read: if request.auth != null
                  && (resource.data.parentId == request.auth.uid
                      || resource.data.proId == request.auth.uid);
      allow create: if request.auth != null
                  && request.resource.data.parentId == request.auth.uid;
      allow update, delete: if false;
    }
```

- [ ] **Step 2: Deploy the rules**

Run: `firebase deploy --only firestore:rules --project pet-aggregator-app`
Expected: `Deploy complete!`

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "chore: add + deploy Firestore rules for bookings (owner/pro read, parent create)"
```

---

### Task 10: Emulator integration test + final verification

**Files:**
- Modify: `integration_test/firebase_repos_test.dart` (add a `bookings` round-trip test)

- [ ] **Step 1: Append a bookings test to `integration_test/firebase_repos_test.dart`**

Add `import 'package:pet_aggregator_app/data/models/booking.dart';` and `import 'package:pet_aggregator_app/data/repositories/firebase/firestore_booking_repository.dart';`, then add a `testWidgets` inside `main()`:
```dart
  testWidgets('bookings create + watchMyBookings round-trip (real Firestore emulators)',
      (tester) async {
    final auth = FirebaseAuthRepository();
    final bookings = FirestoreBookingRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'bk_$stamp@x.com', password: 'secret1');

    await bookings.createBooking(Booking(parentId: me.uid, proId: 'pro_$stamp', proName: 'Aarav',
        petId: 'pet_$stamp', petName: 'Bruno', serviceType: ServiceType.walker,
        rate: 250, fee: 25, total: 275, dateLabel: 'Tue 15 Jul', timeSlot: '5:00 PM'));
    final mine = await bookings.watchMyBookings(me.uid).firstWhere((l) => l.isNotEmpty);
    expect(mine.single.petName, 'Bruno');
    expect(mine.single.total, 275);

    await auth.signOut();
  });
```

- [ ] **Step 2: Start emulators + run the integration test**

```bash
firebase emulators:start --only auth,firestore --project pet-aggregator-app   # one terminal
flutter test integration_test/firebase_repos_test.dart -d emulator-5554        # another
```
Expected: all integration tests pass. Stop the emulators after.

- [ ] **Step 3: Full green gate**

```bash
flutter test
flutter analyze
flutter build apk --debug
```
Expected: unit/widget tests pass, analyze clean, APK builds.

- [ ] **Step 4: Manual walkthrough (real cloud)**

Run: `flutter run -d emulator-5554`. As a pet-parent account (with a pet), open Services → tap a pro → **Book** → pick date/time/pet → Continue → **Pay** → **Booking confirmed**. Confirm a `bookings/{id}` doc exists in the console (with your `parentId`).

- [ ] **Step 5: Commit**

```bash
git add integration_test/firebase_repos_test.dart
git commit -m "test: verify bookings create/watch against Firestore emulators"
```

---

## Self-Review

**Spec coverage:**
- `bookings` collection + `Booking` model → Tasks 1, 3. ✓
- `BookingRepository` + fake + Firestore + providers (`bookingRepositoryProvider`, `myPetsProvider`) → Tasks 2–4. ✓
- BookingScreen (date/time/pet + price, empty-pets state) → Task 5. ✓
- PaymentScreen (UI-only, writes the booking) → Task 6. ✓
- BookingConfirmedScreen (summary, message/back) → Task 7. ✓
- Rewire "Book" (pro profile + list card) → Task 8. ✓
- Rules + deploy → Task 9. ✓
- TDD fakes + emulator integration → each task + Task 10. ✓
- Out-of-scope (real charge, My-bookings UI, reviews, chat, scheduling) → none implemented. ✓

**Placeholder scan:** No "TBD/TODO". Every code step is complete. The payment method rows are intentionally visual (no selection logic) per the spec. `pumpPgApp`'s new `extra` param (Task 5 Step 4) is used by Tasks 5, 6, 8.

**Type consistency:**
- `Booking` fields (`id, parentId, proId, proName, petId, petName, serviceType, rate, fee, total, dateLabel, timeSlot, status`) + `feeFor` identical across Task 1 (model), Task 5 (draft build), Task 6 (Pay), Task 7 (summary), Task 10 (integration). ✓
- `BookingRepository` methods (`createBooking`, `watchMyBookings`) match between interface (Task 2), fake (Task 2), Firestore (Task 3), and callers (Tasks 4, 6, 10). ✓
- Providers (`bookingRepositoryProvider`, `myPetsProvider`) defined Task 4, consumed Tasks 5, 6. ✓
- `Routes.booking` / `Routes.payment` / `Routes.bookingConfirmed` added Task 5, used Tasks 5–8. ✓
- `Pro` (from Slice 4a) passed to BookingScreen via `extra` (Task 5) and pushed from the Book buttons (Task 8). ✓
- `ServiceType` (`label`, `unit`, `storageKey`) reused from `pro.dart` across Tasks 1, 5, 7. ✓

