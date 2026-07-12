# Pawgo Slice 5a: Homestay — Supply & Browse — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the supply/browse side of the Homestay pillar on live Firestore — a `homestayHost` user creates a real `homestays/{uid}` listing, and any signed-in user browses live hosts (off the Home 🏡 tile) and views a host's profile.

**Architecture:** Feature-first Flutter on the existing repository seam, mirroring Services 4a exactly. A new `HomestayRepository` (interface + Firestore impl + in-memory fake) backs `homestays`; providers expose the host list and the signed-in user's own listing. Screens are thin `Consumer`/`Stateless` composition. Tests use in-memory fakes via `pumpPgApp`/`pumpPg`; the emulator integration test covers the real Firestore path. "Request to book" is a `showComingSoon` snackbar this slice (Slice 5b wires the real Request→Accepted flow).

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `cloud_firestore`, `flutter_riverpod`, `go_router`, `google_fonts`. **No new packages.**

**Spec:** `docs/superpowers/specs/2026-07-12-pawgo-homestay-5a-supply-browse-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **Live Firestore, no mock data.** UI/tests depend only on repository interfaces; never import `cloud_firestore`/`firebase_auth` outside `data/repositories/firebase/`, `lib/main.dart`, and `integration_test/`.
- **Out of scope this slice:** the Request/Accepted booking flow + `homestayBookings` (Slice 5b), real date-range selection (the list's date bar is a non-interactive stub), real verification (`verified` defaults false; the ✓ badge is gated on it), review writing (rating/reviewCount stay 0 → "New"), chat, Storage/photos, real geo distance.
- Riverpod 3.x: use `AsyncValue.value` (not `valueOrNull`); in tests, `Override` comes from `package:flutter_riverpod/misc.dart`; prefer a repo stream's `.first` over `StreamProvider.future`.
- `go_router` builders use `(_, _)`; routes that read `extra` use `(_, state)`. Screen tests use the `pumpPgApp`/`pumpPg` harness. Any plain `test()` touching `GoogleFonts` uses `testWidgets`.
- Firestore writes set the server timestamp (`updatedAt`) in the repository, never in model `toMap()`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: `Homestay` + `HomeType` + `Amenity` models

**Files:**
- Create: `lib/data/models/homestay.dart`
- Test: `test/data/homestay_test.dart`

**Interfaces:**
- Produces:
  - `enum HomeType { apartment, house, villa }` with `storageKey`, `label`, `emoji` fields and `static HomeType fromStorage(String)`.
  - `enum Amenity { nearPark, fencedBalcony, residentDog, wfhHost, airConditioned, dailyWalks }` with `storageKey`, `label`, `emoji` fields, `static Amenity fromStorage(String)`, and `static List<Amenity> fromStorageList(List<dynamic>)` (unknown keys ignored).
  - `class Homestay { final String uid, homeName, hostName, area, about; final HomeType homeType; final int ratePerNight, reviewCount; final List<Amenity> amenities; final bool verified; final double rating; const Homestay({required ..., this.amenities = const [], this.verified = false, this.rating = 0, this.reviewCount = 0}); Map<String,dynamic> toMap(); factory Homestay.fromMap(String uid, Map<String,dynamic>); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/data/homestay_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';

void main() {
  test('HomeType + Amenity expose label/emoji and round-trip', () {
    expect(HomeType.apartment.label, 'Apartment');
    expect(HomeType.fromStorage('villa'), HomeType.villa);
    expect(HomeType.fromStorage('nonsense'), HomeType.apartment); // safe default
    expect(Amenity.nearPark.label, 'Near park');
    expect(Amenity.fromStorageList(['nearPark', 'residentDog', 'bogus']),
        [Amenity.nearPark, Amenity.residentDog]); // unknown keys ignored
  });

  test('Homestay toMap omits uid/updatedAt, writes ownerId; fromMap restores', () {
    const h = Homestay(uid: 'u1', homeName: "Meera's Home", hostName: 'Meera Iyer',
        area: 'Bandra West', about: 'Spacious 2BHK.', homeType: HomeType.apartment,
        ratePerNight: 900, amenities: [Amenity.nearPark, Amenity.residentDog]);
    final m = h.toMap();
    expect(m.containsKey('uid'), isFalse);
    expect(m.containsKey('updatedAt'), isFalse);
    expect(m['ownerId'], 'u1');
    expect(m['homeType'], 'apartment');
    expect(m['amenities'], ['nearPark', 'residentDog']);
    expect(m['verified'], false);
    expect(m['rating'], 0.0);
    final back = Homestay.fromMap('u1', m);
    expect(back.homeName, "Meera's Home");
    expect(back.hostName, 'Meera Iyer');
    expect(back.ratePerNight, 900);
    expect(back.homeType, HomeType.apartment);
    expect(back.amenities, [Amenity.nearPark, Amenity.residentDog]);
    expect(back.verified, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/homestay_test.dart`
Expected: FAIL — `Homestay`/`HomeType`/`Amenity` not found.

- [ ] **Step 3: Implement `lib/data/models/homestay.dart`**

```dart
enum HomeType {
  apartment('apartment', 'Apartment', '🏡'),
  house('house', 'House', '🏠'),
  villa('villa', 'Villa', '🏘️');

  final String storageKey, label, emoji;
  const HomeType(this.storageKey, this.label, this.emoji);

  static HomeType fromStorage(String key) =>
      HomeType.values.firstWhere((t) => t.storageKey == key, orElse: () => HomeType.apartment);
}

enum Amenity {
  nearPark('nearPark', 'Near park', '🌳'),
  fencedBalcony('fencedBalcony', 'Fenced balcony', '🪴'),
  residentDog('residentDog', 'Resident dog', '🐕'),
  wfhHost('wfhHost', 'WFH host', '💻'),
  airConditioned('airConditioned', 'Air-conditioned', '❄️'),
  dailyWalks('dailyWalks', 'Daily walks', '🦮');

  final String storageKey, label, emoji;
  const Amenity(this.storageKey, this.label, this.emoji);

  static Amenity fromStorage(String key) =>
      Amenity.values.firstWhere((a) => a.storageKey == key, orElse: () => Amenity.nearPark);

  /// Maps stored keys to amenities, silently dropping any unknown keys.
  static List<Amenity> fromStorageList(List<dynamic> keys) {
    final byKey = {for (final a in Amenity.values) a.storageKey: a};
    return keys.map((k) => byKey[k as String]).whereType<Amenity>().toList();
  }
}

class Homestay {
  final String uid, homeName, hostName, area, about;
  final HomeType homeType;
  final int ratePerNight, reviewCount;
  final List<Amenity> amenities;
  final bool verified;
  final double rating;

  const Homestay({
    required this.uid, required this.homeName, required this.hostName,
    required this.area, required this.about, required this.homeType,
    required this.ratePerNight, this.amenities = const [],
    this.verified = false, this.rating = 0, this.reviewCount = 0,
  });

  Map<String, dynamic> toMap() => {
        'ownerId': uid,
        'homeName': homeName,
        'hostName': hostName,
        'area': area,
        'about': about,
        'homeType': homeType.storageKey,
        'ratePerNight': ratePerNight,
        'amenities': amenities.map((a) => a.storageKey).toList(),
        'verified': verified,
        'rating': rating,
        'reviewCount': reviewCount,
      };

  factory Homestay.fromMap(String uid, Map<String, dynamic> m) => Homestay(
        uid: uid,
        homeName: (m['homeName'] ?? '') as String,
        hostName: (m['hostName'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        about: (m['about'] ?? '') as String,
        homeType: HomeType.fromStorage((m['homeType'] ?? 'apartment') as String),
        ratePerNight: (m['ratePerNight'] ?? 0) as int,
        amenities: Amenity.fromStorageList((m['amenities'] ?? const []) as List),
        verified: (m['verified'] ?? false) as bool,
        rating: ((m['rating'] ?? 0) as num).toDouble(),
        reviewCount: (m['reviewCount'] ?? 0) as int,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/homestay_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze lib/data/models/homestay.dart
git add lib/data/models/homestay.dart test/data/homestay_test.dart
git commit -m "feat: add Homestay + HomeType + Amenity models with Firestore serialization"
```

---

### Task 2: `HomestayRepository` interface + in-memory fake

**Files:**
- Create: `lib/data/repositories/homestay_repository.dart`
- Modify: `test/support/fakes.dart` (add `InMemoryHomestayRepository`)
- Test: `test/data/homestay_repository_test.dart`

**Interfaces:**
- Consumes: `Homestay` (Task 1).
- Produces:
  - `abstract interface class HomestayRepository { Future<void> upsertHomestay(Homestay homestay); Stream<Homestay?> watchHomestay(String uid); Stream<List<Homestay>> watchHomestays(); }`
  - `InMemoryHomestayRepository` fake.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/homestay_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import '../support/fakes.dart';

void main() {
  test('InMemoryHomestayRepository upserts and streams homestays', () async {
    final repo = InMemoryHomestayRepository();
    expect(await repo.watchHomestays().first, isEmpty);
    await repo.upsertHomestay(const Homestay(uid: 'u1', homeName: "Meera's Home",
        hostName: 'Meera Iyer', area: 'Bandra West', about: 'x',
        homeType: HomeType.apartment, ratePerNight: 900));
    expect((await repo.watchHomestays().first).single.homeName, "Meera's Home");
    expect((await repo.watchHomestay('u1').first)!.ratePerNight, 900);
    // upsert overwrites the same uid.
    await repo.upsertHomestay(const Homestay(uid: 'u1', homeName: "Meera's Home",
        hostName: 'Meera Iyer', area: 'Khar', about: 'x',
        homeType: HomeType.villa, ratePerNight: 1100));
    expect((await repo.watchHomestay('u1').first)!.ratePerNight, 1100);
    expect((await repo.watchHomestays().first).length, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/homestay_repository_test.dart`
Expected: FAIL — types not found.

- [ ] **Step 3: Create `lib/data/repositories/homestay_repository.dart`**

```dart
import '../models/homestay.dart';

abstract interface class HomestayRepository {
  Future<void> upsertHomestay(Homestay homestay);
  Stream<Homestay?> watchHomestay(String uid);
  Stream<List<Homestay>> watchHomestays();
}
```

- [ ] **Step 4: Add `InMemoryHomestayRepository` to `test/support/fakes.dart`**

Add imports at the top with the other imports: `import 'package:pet_aggregator_app/data/models/homestay.dart';` and `import 'package:pet_aggregator_app/data/repositories/homestay_repository.dart';`. Then append this class (mirrors `InMemoryProRepository`):

```dart
class InMemoryHomestayRepository implements HomestayRepository {
  final Map<String, Homestay> _homestays = {};
  final _controller = StreamController<List<Homestay>>.broadcast();

  InMemoryHomestayRepository([List<Homestay>? seed]) {
    if (seed != null) {
      for (final h in seed) {
        _homestays[h.uid] = h;
      }
    }
  }

  List<Homestay> _list() => _homestays.values.toList();

  @override
  Future<void> upsertHomestay(Homestay homestay) async {
    _homestays[homestay.uid] = homestay;
    _controller.add(_list());
  }

  @override
  Stream<Homestay?> watchHomestay(String uid) async* {
    yield _homestays[uid];
    yield* _controller.stream.map((_) => _homestays[uid]);
  }

  @override
  Stream<List<Homestay>> watchHomestays() async* {
    yield _list();
    yield* _controller.stream.map((_) => _list());
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/homestay_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze lib/data test/support/fakes.dart
git add lib/data/repositories/homestay_repository.dart test/support/fakes.dart test/data/homestay_repository_test.dart
git commit -m "feat: add HomestayRepository interface + in-memory fake"
```

---

### Task 3: `FirestoreHomestayRepository`

**Files:**
- Create: `lib/data/repositories/firebase/firestore_homestay_repository.dart`

**Interfaces:**
- Consumes: `HomestayRepository`, `Homestay` (Tasks 1–2).
- Produces: `FirestoreHomestayRepository` (verified on the emulator in Task 9).

- [ ] **Step 1: Create `firestore_homestay_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/homestay.dart';
import '../homestay_repository.dart';

class FirestoreHomestayRepository implements HomestayRepository {
  final FirebaseFirestore _db;
  FirestoreHomestayRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('homestays');

  @override
  Future<void> upsertHomestay(Homestay homestay) => _col.doc(homestay.uid).set({
        ...homestay.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Stream<Homestay?> watchHomestay(String uid) => _col.doc(uid).snapshots().map(
      (doc) => doc.exists ? Homestay.fromMap(uid, doc.data()!) : null);

  @override
  Stream<List<Homestay>> watchHomestays() => _col
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Homestay.fromMap(d.id, d.data())).toList());
}
```

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze lib/data/repositories/firebase
git add lib/data/repositories/firebase/firestore_homestay_repository.dart
git commit -m "feat: add FirestoreHomestayRepository"
```

---

### Task 4: Providers — `homestayRepositoryProvider`, `homestaysProvider`, `currentHomestayProvider`

**Files:**
- Modify: `lib/data/repositories/providers.dart`
- Test: `test/data/homestays_provider_test.dart`

**Interfaces:**
- Consumes: `authStateProvider`, `authRepositoryProvider` (existing), `Homestay`, `HomestayRepository`, `FirestoreHomestayRepository`.
- Produces:
  - `homestayRepositoryProvider` → `Provider<HomestayRepository>`
  - `homestaysProvider` → `StreamProvider<List<Homestay>>`
  - `currentHomestayProvider` → `StreamProvider<Homestay?>` (signed-in user's own listing).

- [ ] **Step 1: Write the failing test**

```dart
// test/data/homestays_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('currentHomestayProvider streams the signed-in host\'s listing', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository([
        const Homestay(uid: 'uid_me@x.com', homeName: 'My Home', hostName: 'Me', area: 'Khar',
            about: 'x', homeType: HomeType.apartment, ratePerNight: 800),
      ])),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(currentHomestayProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();
    expect(container.read(currentHomestayProvider).value?.ratePerNight, 800);
    expect((container.read(homestaysProvider).value ?? []).length, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/homestays_provider_test.dart`
Expected: FAIL — providers not defined.

- [ ] **Step 3: Extend `lib/data/repositories/providers.dart`**

Add these imports next to the existing ones: `import '../models/homestay.dart';`, `import 'homestay_repository.dart';`, `import 'firebase/firestore_homestay_repository.dart';`. Then append:

```dart
final homestayRepositoryProvider =
    Provider<HomestayRepository>((ref) => FirestoreHomestayRepository());

final homestaysProvider =
    StreamProvider<List<Homestay>>((ref) => ref.watch(homestayRepositoryProvider).watchHomestays());

final currentHomestayProvider = StreamProvider<Homestay?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(homestayRepositoryProvider).watchHomestay(user.uid);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/homestays_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
flutter analyze lib/data
git add lib/data/repositories/providers.dart test/data/homestays_provider_test.dart
git commit -m "feat: add homestay providers (homestayRepositoryProvider, homestaysProvider, currentHomestayProvider)"
```

---

### Task 5: `HostSetupScreen` + route constants + `/host-setup` route

**Files:**
- Create: `lib/features/homestay/host_setup_screen.dart`
- Modify: `lib/core/router/routes.dart` (add `homestay`, `host`, `hostSetup`)
- Modify: `lib/core/router/app_router.dart` (import + protect + route)
- Test: `test/features/host_setup_screen_test.dart`

**Interfaces:**
- Consumes: `homestayRepositoryProvider`, `currentHomestayProvider`, `currentUserProfileProvider`, `authRepositoryProvider`, `Homestay`, `HomeType`, `Amenity`, `PgTextField`, `PgPrimaryButton`, `PgAppBar`.
- Produces: `HostSetupScreen`; `Routes.homestay == '/homestay'`, `Routes.host == '/host'`, `Routes.hostSetup == '/host-setup'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/host_setup_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('filling the form and saving writes a homestay listing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Meera Iyer',
        email: 'me@x.com', area: 'Bandra West', role: Role.homestayHost));
    final homestays = InMemoryHomestayRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      homestayRepositoryProvider.overrideWithValue(homestays),
    ], initialLocation: Routes.hostSetup);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), "Meera's Home"); // home name
    await tester.enterText(find.byType(TextField).at(1), '900');          // rate/night
    await tester.enterText(find.byType(TextField).at(2), 'Spacious 2BHK, WFH host.'); // about
    await tester.tap(find.textContaining('Near park')); // toggle an amenity
    await tester.pump();
    await tester.tap(find.text('List my home'));
    await tester.pumpAndSettle();

    final mine = await homestays.watchHomestay(auth.currentUser!.uid).first;
    expect(mine!.homeName, "Meera's Home");
    expect(mine.ratePerNight, 900);
    expect(mine.hostName, 'Meera Iyer');
    expect(mine.area, 'Bandra West');
    expect(mine.amenities, contains(Amenity.nearPark));
    expect(mine.verified, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/host_setup_screen_test.dart`
Expected: FAIL — `HostSetupScreen` / routes not found.

- [ ] **Step 3: Add the route constants**

In `lib/core/router/routes.dart`, add inside `class Routes` (after `bookingConfirmed`):
```dart
  static const homestay = '/homestay';
  static const host = '/host';
  static const hostSetup = '/host-setup';
```

- [ ] **Step 4: Implement `lib/features/homestay/host_setup_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/homestay.dart';
import '../../data/repositories/providers.dart';

class HostSetupScreen extends ConsumerStatefulWidget {
  const HostSetupScreen({super.key});
  @override
  ConsumerState<HostSetupScreen> createState() => _HostSetupScreenState();
}

class _HostSetupScreenState extends ConsumerState<HostSetupScreen> {
  final _homeName = TextEditingController();
  final _rate = TextEditingController();
  final _about = TextEditingController();
  HomeType _homeType = HomeType.apartment;
  final Set<Amenity> _amenities = {};
  bool _verified = false;
  double _rating = 0;
  int _reviewCount = 0;
  bool _seeded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _homeName.dispose();
    _rate.dispose();
    _about.dispose();
    super.dispose();
  }

  void _seed(Homestay h) {
    _homeName.text = h.homeName;
    _homeType = h.homeType;
    _rate.text = h.ratePerNight.toString();
    _about.text = h.about;
    _amenities
      ..clear()
      ..addAll(h.amenities);
    _verified = h.verified;
    _rating = h.rating;
    _reviewCount = h.reviewCount;
  }

  Future<void> _save() async {
    final name = _homeName.text.trim();
    final rate = int.tryParse(_rate.text.trim()) ?? 0;
    if (name.isEmpty) {
      setState(() => _error = 'Enter a home name.');
      return;
    }
    if (rate <= 0) {
      setState(() => _error = 'Enter a rate greater than 0.');
      return;
    }
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    final profile = ref.read(currentUserProfileProvider).value;
    setState(() { _saving = true; _error = null; });
    await ref.read(homestayRepositoryProvider).upsertHomestay(Homestay(
          uid: uid, homeName: name, hostName: profile?.name ?? '',
          area: profile?.area ?? '', about: _about.text.trim(), homeType: _homeType,
          ratePerNight: rate, amenities: _amenities.toList(),
          verified: _verified, rating: _rating, reviewCount: _reviewCount));
    if (mounted) context.go(Routes.homestay);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    ref.listen(currentHomestayProvider, (prev, next) {
      if (!_seeded && next.hasValue && next.value != null) {
        setState(() => _seed(next.value!));
        _seeded = true;
      }
    });

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(
            title: 'List your home',
            onBack: () => context.canPop() ? context.pop() : context.go(Routes.homestay),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
              children: [
                Text('Set up your home so pet parents can book boarding.',
                    style: PgText.inter(14, FontWeight.w400, color: c.muted, height: 1.5)),
                const SizedBox(height: 16),
                PgTextField(label: 'Home name', controller: _homeName, hint: "Meera's Home"),
                const SizedBox(height: 16),
                Text('Home type', style: PgText.label(context)),
                const SizedBox(height: 8),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (final t in HomeType.values)
                    _SelectChip(
                      label: '${t.emoji} ${t.label}',
                      selected: _homeType == t,
                      onTap: () => setState(() => _homeType = t),
                    ),
                ]),
                const SizedBox(height: 16),
                PgTextField(label: 'Rate (₹ per night)', controller: _rate,
                    keyboardType: TextInputType.number, hint: '900'),
                const SizedBox(height: 16),
                PgTextField(label: 'About this home', controller: _about,
                    hint: 'Tell parents about your home'),
                const SizedBox(height: 16),
                Text('Amenities', style: PgText.label(context)),
                const SizedBox(height: 8),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (final a in Amenity.values)
                    _SelectChip(
                      label: '${a.emoji} ${a.label}',
                      selected: _amenities.contains(a),
                      onTap: () => setState(() =>
                          _amenities.contains(a) ? _amenities.remove(a) : _amenities.add(a)),
                    ),
                ]),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart))),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: PgPrimaryButton(label: _saving ? 'Saving…' : 'List my home',
              onPressed: _saving ? () {} : _save),
          ),
        ]),
      ),
    );
  }
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.brandSoft : c.surface,
          border: Border.all(color: selected ? c.brand : c.border, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(13)),
        child: Text(label,
          style: PgText.inter(13, FontWeight.w600, color: selected ? c.brand : c.text)),
      ),
    );
  }
}
```

- [ ] **Step 5: Wire the route in `app_router.dart`**

In `lib/core/router/app_router.dart`: add `import '../../features/homestay/host_setup_screen.dart';`, add `Routes.homestay, Routes.host, Routes.hostSetup` to the `_protected` set, and add this route in the top-level list (after the `Routes.bookingConfirmed` route):
```dart
      GoRoute(path: Routes.hostSetup, builder: (_, _) => const HostSetupScreen()),
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/host_setup_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add lib/features/homestay/host_setup_screen.dart lib/core/router/routes.dart lib/core/router/app_router.dart test/features/host_setup_screen_test.dart
git commit -m "feat: add Host-setup screen (homestayHost creates a listing) + homestay routes"
```

---

### Task 6: `HomestayListScreen` + `/homestay` route + repoint the Home 🏡 tile

**Files:**
- Create: `lib/features/homestay/homestay_list_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/homestay` route)
- Modify: `lib/features/home/home_screen.dart` (repoint the Homestay quick-action)
- Test: `test/features/homestay_list_screen_test.dart`

**Interfaces:**
- Consumes: `homestaysProvider`, `currentHomestayProvider`, `currentUserProfileProvider`, `Homestay`, `Role`, `Routes`, theme.
- Produces: `HomestayListScreen`; the `/homestay` route; the Home 🏡 tile now pushes `Routes.homestay`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/homestay_list_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _meera = Homestay(uid: 'h1', homeName: "Meera's Home", hostName: 'Meera Iyer',
    area: 'Bandra West', about: 'Spacious 2BHK.', homeType: HomeType.apartment,
    ratePerNight: 900, amenities: [Amenity.nearPark]);

void main() {
  testWidgets('lists live hosts (unverified shows New, no badge)', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository([_meera])),
    ], initialLocation: Routes.homestay);
    await tester.pumpAndSettle();
    expect(find.text('Homestay boarding'), findsOneWidget);
    expect(find.text("Meera's Home"), findsOneWidget);
    expect(find.text('New'), findsWidgets);          // no reviews yet
    expect(find.text('Verified host'), findsNothing); // unverified => no badge
  });

  testWidgets('a verified host shows the Verified badge', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    const verified = Homestay(uid: 'h2', homeName: 'Anjali Stays', hostName: 'Anjali Rao',
        area: 'Pali Hill', about: 'x', homeType: HomeType.villa, ratePerNight: 1100,
        verified: true);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository([verified])),
    ], initialLocation: Routes.homestay);
    await tester.pumpAndSettle();
    expect(find.text('Verified host'), findsOneWidget);
  });

  testWidgets('shows a set-up banner for a homestayHost without a listing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com',
        area: 'Khar', role: Role.homestayHost));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
    ], initialLocation: Routes.homestay);
    await tester.pumpAndSettle();
    expect(find.text('Set up your homestay'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/homestay_list_screen_test.dart`
Expected: FAIL — `HomestayListScreen` not found.

- [ ] **Step 3: Implement `lib/features/homestay/homestay_list_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/homestay.dart';
import '../../data/models/role.dart';
import '../../data/repositories/providers.dart';

class HomestayListScreen extends ConsumerWidget {
  const HomestayListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final hostsAsync = ref.watch(homestaysProvider);
    final currentHomestay = ref.watch(currentHomestayProvider);
    final profile = ref.watch(currentUserProfileProvider).value;
    final area = (profile?.area.isNotEmpty ?? false) ? profile!.area : 'Mumbai';
    final isHostWithoutListing = profile?.role == Role.homestayHost &&
        currentHomestay.hasValue && currentHomestay.value == null;

    return Container(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(color: c.peach,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                  child: Container(
                    width: 40, height: 40, alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                    child: const Icon(Icons.chevron_left, color: Colors.white)),
                ),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Homestay boarding',
                    style: PgText.poppins(22, FontWeight.w800, color: c.text, ls: -0.3)),
                  Text('Verified hosts in $area',
                    style: PgText.inter(12.5, FontWeight.w500, color: c.text)),
                ])),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Text('🗓️', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Add dates · 1 pet',
                    style: PgText.inter(13, FontWeight.w500, color: c.muted))),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              children: [
                if (isHostWithoutListing)
                  GestureDetector(
                    onTap: () => context.push(Routes.hostSetup),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        const Text('🏡', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Set up your homestay',
                            style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
                          Text('List your home so parents can book boarding',
                            style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                        ])),
                        Icon(Icons.chevron_right, color: c.brand),
                      ]),
                    ),
                  ),
                hostsAsync.when(
                  loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text('Could not load hosts.',
                    style: PgText.inter(13.5, FontWeight.w500, color: c.muted)),
                  data: (hosts) {
                    if (hosts.isEmpty) {
                      return Padding(padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('No hosts nearby yet — check back soon.',
                          style: PgText.inter(13.5, FontWeight.w400, color: c.muted)));
                    }
                    return Column(children: [
                      for (final h in hosts) ...[_HostCard(homestay: h), const SizedBox(height: 14)],
                    ]);
                  },
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  final Homestay homestay;
  const _HostCard({required this.homestay});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final h = homestay;
    final rating = h.reviewCount == 0 ? 'New' : '★ ${h.rating.toStringAsFixed(1)}';
    return GestureDetector(
      onTap: () => context.push(Routes.host, extra: h),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(20), boxShadow: c.shadowSm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            Container(height: 150, width: double.infinity, color: c.surface2,
              alignment: Alignment.center,
              child: Text(h.homeType.emoji, style: const TextStyle(fontSize: 40))),
            if (h.verified)
              Positioned(top: 12, left: 12, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20),
                  boxShadow: c.shadowSm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified, size: 13, color: c.brand),
                  const SizedBox(width: 4),
                  Text('Verified host', style: PgText.inter(11.5, FontWeight.w700, color: c.brand)),
                ]))),
          ]),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.homeName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: PgText.poppins(15.5, FontWeight.w700, color: c.text)),
                const SizedBox(height: 2),
                Text('${h.hostName} · ${h.area}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                const SizedBox(height: 10),
                Row(children: [
                  Text('₹${h.ratePerNight}', style: PgText.poppins(17, FontWeight.w800, color: c.brand)),
                  Text(' / night', style: PgText.inter(12.5, FontWeight.w400, color: c.faint)),
                ]),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(20)),
                child: Text(rating, style: PgText.inter(12, FontWeight.w700, color: c.brandDeep))),
            ]),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Add the `/homestay` route**

In `lib/core/router/app_router.dart`: add `import '../../features/homestay/homestay_list_screen.dart';` and this route (next to the `Routes.hostSetup` route):
```dart
      GoRoute(path: Routes.homestay, builder: (_, _) => const HomestayListScreen()),
```

- [ ] **Step 5: Repoint the Home 🏡 Homestay tile**

In `lib/features/home/home_screen.dart`, the Homestay `_QuickAction` currently has `onTap: () => context.go(Routes.services)`. Change it to push the new route:
```dart
                    _QuickAction(emoji: '🏡', title: 'Homestay', subtitle: 'Verified boarding hosts',
                      bg: c.lav, fg: c.text, onTap: () => context.push(Routes.homestay)),
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/homestay_list_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Add a Home-tile navigation test**

Append to `test/features/homestay_list_screen_test.dart`:
```dart
  testWidgets('Home Homestay tile opens the Homestay list', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository([_meera])),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Homestay'));
    await tester.pumpAndSettle();
    expect(find.text('Homestay boarding'), findsOneWidget);
  });
```
Add the import it needs at the top of the file: `import 'package:pet_aggregator_app/data/repositories/providers.dart';` is already present; no new import required (`InMemoryPetRepository` comes from `../support/fakes.dart`, already imported).

- [ ] **Step 8: Run the file again**

Run: `flutter test test/features/homestay_list_screen_test.dart`
Expected: PASS (all four tests).

- [ ] **Step 9: Analyze + commit**

```bash
flutter analyze
git add lib/features/homestay/homestay_list_screen.dart lib/core/router/app_router.dart lib/features/home/home_screen.dart test/features/homestay_list_screen_test.dart
git commit -m "feat: add Homestay list screen (live hosts, setup banner) + /homestay route; wire Home tile"
```

---

### Task 7: `HostProfileScreen` + `/host` route

**Files:**
- Create: `lib/features/homestay/host_profile_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/host` route)
- Test: `test/features/host_profile_screen_test.dart`

**Interfaces:**
- Consumes: `Homestay`, `HomeType`, `Amenity`, `showComingSoon`, theme.
- Produces: `HostProfileScreen({Homestay? homestay})` — a `StatelessWidget` (renders the passed `Homestay`; needs no providers).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/host_profile_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/features/homestay/host_profile_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the host + New host (unverified); Request to book hints coming soon',
      (tester) async {
    const h = Homestay(uid: 'h1', homeName: "Meera's Home", hostName: 'Meera Iyer',
        area: 'Bandra West', about: 'Spacious 2BHK with a fenced balcony.',
        homeType: HomeType.apartment, ratePerNight: 900,
        amenities: [Amenity.nearPark, Amenity.residentDog]);
    await pumpPg(tester, const HostProfileScreen(homestay: h));
    expect(find.text("Meera's Home"), findsOneWidget);
    expect(find.textContaining('Meera Iyer'), findsOneWidget);
    expect(find.text('Spacious 2BHK with a fenced balcony.'), findsOneWidget);
    expect(find.textContaining('New host'), findsOneWidget); // unverified
    await tester.tap(find.textContaining('Request to book'));
    await tester.pump();
    expect(find.text('Booking is coming soon 🐾'), findsOneWidget);
  });

  testWidgets('a verified host shows the Verified host badge', (tester) async {
    const h = Homestay(uid: 'h2', homeName: 'Anjali Stays', hostName: 'Anjali Rao',
        area: 'Pali Hill', about: 'x', homeType: HomeType.villa, ratePerNight: 1100,
        verified: true);
    await pumpPg(tester, const HostProfileScreen(homestay: h));
    expect(find.text('Pawgo Verified host'), findsOneWidget);
    expect(find.textContaining('New host'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/host_profile_screen_test.dart`
Expected: FAIL — `HostProfileScreen` not found.

- [ ] **Step 3: Implement `lib/features/homestay/host_profile_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/homestay.dart';

class HostProfileScreen extends StatelessWidget {
  final Homestay? homestay;
  const HostProfileScreen({super.key, this.homestay});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final h = homestay;
    if (h == null) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(backgroundColor: c.bg, elevation: 0),
        body: Center(child: Text('Home not found', style: PgText.body(context))),
      );
    }
    final chips = <String>['${h.homeType.emoji} ${h.homeType.label}',
      for (final a in h.amenities) '${a.emoji} ${a.label}'];

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Home photo header + back button.
              Stack(children: [
                Container(height: 220, width: double.infinity, color: c.surface2,
                  alignment: Alignment.center,
                  child: Text(h.homeType.emoji, style: const TextStyle(fontSize: 56))),
                Positioned(top: 0, left: 0, child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: GestureDetector(
                      onTap: () => context.canPop() ? context.pop() : null,
                      child: Container(
                        width: 40, height: 40, alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12),
                          boxShadow: c.shadowSm),
                        child: Icon(Icons.chevron_left, color: c.text))),
                  ),
                )),
              ]),
              Transform.translate(
                offset: const Offset(0, -26),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22),
                        boxShadow: c.shadow),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(h.homeName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: PgText.poppins(19, FontWeight.w800, color: c.text))),
                              if (h.verified) ...[
                                const SizedBox(width: 5),
                                Icon(Icons.verified, size: 16, color: c.brand),
                              ],
                            ]),
                            const SizedBox(height: 3),
                            Text('Hosted by ${h.hostName} · ${h.area}',
                              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('₹${h.ratePerNight}', style: PgText.poppins(17, FontWeight.w800, color: c.brand)),
                            Text('/ night', style: PgText.inter(11, FontWeight.w400, color: c.faint)),
                          ]),
                        ]),
                        const SizedBox(height: 14),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final label in chips)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(11)),
                              child: Text(label, style: PgText.inter(12, FontWeight.w600, color: c.text))),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Text('About this home', style: PgText.sectionHeader(context)),
                    const SizedBox(height: 7),
                    Text(h.about.isEmpty ? 'No description yet.' : h.about,
                      style: PgText.inter(13.5, FontWeight.w400, color: c.muted, height: 1.6)),
                    const SizedBox(height: 18),
                    if (h.verified)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          const Text('🛡️', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Pawgo Verified host',
                              style: PgText.inter(13, FontWeight.w700, color: c.text)),
                            Text('ID & address confirmed',
                              style: PgText.inter(12, FontWeight.w400, color: c.muted)),
                          ])),
                        ]),
                      )
                    else
                      Text('New host · not yet Pawgo-verified',
                        style: PgText.inter(12.5, FontWeight.w600, color: c.faint)),
                    const SizedBox(height: 20),
                    Text('Recent reviews', style: PgText.sectionHeader(context)),
                    const SizedBox(height: 10),
                    Text('No reviews yet.', style: PgText.inter(13.5, FontWeight.w400, color: c.muted)),
                  ]),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
          padding: EdgeInsets.fromLTRB(22, 13, 22, 18 + MediaQuery.of(context).padding.bottom),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('₹${h.ratePerNight}', style: PgText.poppins(18, FontWeight.w800, color: c.text)),
              Text('/ night', style: PgText.inter(11, FontWeight.w400, color: c.faint)),
            ]),
            const SizedBox(width: 16),
            Expanded(child: GestureDetector(
              onTap: () => showComingSoon(context, 'Booking'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(16)),
                child: Text('Request to book',
                  style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white))))),
          ]),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 4: Add the `/host` route**

In `lib/core/router/app_router.dart`: add `import '../../features/homestay/host_profile_screen.dart';`, `import '../../data/models/homestay.dart';`, and this route (next to `Routes.homestay`):
```dart
      GoRoute(path: Routes.host, builder: (_, state) => HostProfileScreen(homestay: state.extra as Homestay?)),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/host_profile_screen_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/homestay/host_profile_screen.dart lib/core/router/app_router.dart test/features/host_profile_screen_test.dart
git commit -m "feat: add Host profile screen + /host route"
```
Expected: whole suite green, analyze clean.

---

### Task 8: Firestore rules for `homestays`; deploy

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Add the `homestays` block to `firestore.rules`**

Inside `match /databases/{database}/documents { ... }`, after the `bookings` block:
```
    match /homestays/{uid} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == uid;
    }
```

- [ ] **Step 2: Deploy the rules**

Run: `firebase deploy --only firestore:rules --project pet-aggregator-app`
Expected: `Deploy complete!`

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "chore: add + deploy Firestore rules for homestays (owner-write, authed-read)"
```

---

### Task 9: Emulator integration test + final verification

**Files:**
- Modify: `integration_test/firebase_repos_test.dart` (add a `homestays` round-trip test)

- [ ] **Step 1: Append a homestays test to `integration_test/firebase_repos_test.dart`**

Add `import 'package:pet_aggregator_app/data/models/homestay.dart';` and `import 'package:pet_aggregator_app/data/repositories/firebase/firestore_homestay_repository.dart';` with the other imports, then add this `testWidgets` inside `main()`:
```dart
  testWidgets('homestays upsert + watch round-trip (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final homestaysRepo = FirestoreHomestayRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'host_$stamp@x.com', password: 'secret1');

    await homestaysRepo.upsertHomestay(Homestay(uid: me.uid, homeName: "Meera's Home",
        hostName: 'Meera Iyer', area: 'Bandra West', about: 'Spacious 2BHK.',
        homeType: HomeType.apartment, ratePerNight: 900, amenities: [Amenity.nearPark]));
    final mine = await homestaysRepo.watchHomestay(me.uid).firstWhere((h) => h != null);
    expect(mine!.ratePerNight, 900);
    expect(mine.verified, isFalse);
    expect(mine.amenities, contains(Amenity.nearPark));
    final all = await homestaysRepo.watchHomestays().firstWhere((l) => l.any((h) => h.uid == me.uid));
    expect(all.any((h) => h.homeName == "Meera's Home"), isTrue);

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

Run: `flutter run -d emulator-5554`. Sign in as a **Homestay Host** account → Home → tap the 🏡 Homestay tile → the list shows the "Set up your homestay" banner → create a listing. Sign in as a pet-parent account → Home → 🏡 Homestay → the list shows that host (no ✓ badge, "New"); tap it → Host profile renders with amenities + "New host"; "Request to book" shows the coming-soon snackbar. Confirm a `homestays/{uid}` doc exists in the console.

- [ ] **Step 5: Commit**

```bash
git add integration_test/firebase_repos_test.dart
git commit -m "test: verify homestays upsert/watch against Firestore emulators"
```

---

## Self-Review

**Spec coverage:**
- `homestays` collection + `Homestay`/`HomeType`/`Amenity` models → Tasks 1–3. ✓
- `HomestayRepository` + fake + Firestore + providers (`homestaysProvider`, `currentHomestayProvider`) → Tasks 2–4. ✓
- Host-setup screen (create/edit listing, pre-fill, validation) → Task 5. ✓
- Homestay list (live hosts, verified-badge gating, setup banner, empty state, date stub bar) + Home 🏡 tile repoint → Task 6. ✓
- Host profile (amenities, About, verified badge vs "New host", Reviews-empty, "Request to book" → coming-soon) → Task 7. ✓
- Rules + deploy → Task 8. ✓
- TDD fakes + emulator integration → each task + Task 9. ✓
- Out-of-scope (Request/Accepted flow + homestayBookings, real date range, real verification, reviews, chat, Storage, geo) → none implemented. ✓

**Placeholder scan:** No "TBD/TODO". Every code step is complete. "Request to book" intentionally calls `showComingSoon` (Slice 5b rewires it).

**Type consistency:**
- `Homestay` fields (`uid, homeName, hostName, area, about, homeType, ratePerNight, amenities, verified, rating, reviewCount`) identical across Task 1 (model), Task 5 (setup write), Task 6 (card), Task 7 (profile), Task 9 (integration). ✓
- `HomestayRepository` methods (`upsertHomestay`, `watchHomestay`, `watchHomestays`) match between interface (Task 2), fake (Task 2), Firestore (Task 3), and callers (Tasks 4–9). ✓
- Providers (`homestayRepositoryProvider`, `homestaysProvider`, `currentHomestayProvider`) defined Task 4, consumed Tasks 5–6. ✓
- `Routes.homestay` / `Routes.host` / `Routes.hostSetup` added Task 5, used Tasks 5 (route + setup save/back), 6 (route + Home tile push + banner push + card push `host`), 7 (route). ✓
- `HomeType` / `Amenity` (`label`, `emoji`, `storageKey`, `fromStorage`, `fromStorageList`) consistent across Tasks 1, 5, 6, 7, 9. ✓
- `HostProfileScreen` constructor param `homestay` matches the router cast `state.extra as Homestay?` (Task 7). ✓
- `showComingSoon(context, label)` (from Slice 3) reused in Task 7. ✓
- Back-navigation uses `context.canPop() ? context.pop() : context.go(...)` in the list header and setup app bar (robust whether reached via push from Home or `go` after save). ✓
