# Pawgo Slice 4a: Services — Supply & Browse — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the supply/browse side of the Services pillar on live Firestore — a `servicePro` user creates a real `pros/{uid}` listing, and any signed-in user browses live pros by category and views a pro's profile.

**Architecture:** Feature-first Flutter on the existing repository seam. A new `ProRepository` (interface + Firestore impl + in-memory fake) backs `pros`; providers expose the pro list and the signed-in user's own listing. Screens are thin `Consumer` composition. Tests use in-memory fakes via `pumpPgApp`; the emulator integration test covers the real Firestore path. "Book" is a `showComingSoon` snackbar this slice (Slice 4b wires the real flow).

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `cloud_firestore`, `flutter_riverpod`, `go_router`, `google_fonts`. **No new packages.**

**Spec:** `docs/superpowers/specs/2026-07-11-pawgo-services-4a-supply-browse-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **Live Firestore, no mock data.** UI/tests depend only on repository interfaces; never import `cloud_firestore`/`firebase_auth` outside `data/repositories/firebase/`, `lib/main.dart`, and `integration_test/`.
- **Out of scope this slice:** booking/payment/`bookings` (Slice 4b), review writing (rating/reviewCount stay 0 → "New"), chat, Storage/photos, real geo distance.
- Riverpod 3.x: use `AsyncValue.value` (not `valueOrNull`); in tests, `Override` comes from `package:flutter_riverpod/misc.dart`; prefer a repo stream's `.first` over `StreamProvider.future`.
- `go_router` builders use `(_, _)`; routes that read `extra` use `(_, state)`. Screen tests use the `pumpPgApp` harness. Any plain `test()` touching `GoogleFonts` uses `testWidgets`.
- Firestore writes set the server timestamp (`updatedAt`) in the repository, never in model `toMap()`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: `Pro` + `ServiceType` models

**Files:**
- Create: `lib/data/models/pro.dart`
- Test: `test/data/pro_test.dart`

**Interfaces:**
- Produces:
  - `enum ServiceType { walker, sitter, groomer, trainer }` with `storageKey`, `label`, `emoji`, `unit` fields and `static ServiceType fromStorage(String)`.
  - `class Pro { final String uid, name, area, bio; final ServiceType serviceType; final int rate, experienceYears, reviewCount; final double rating; const Pro({required ..., this.rating = 0, this.reviewCount = 0}); String get unit; Map<String,dynamic> toMap(); factory Pro.fromMap(String uid, Map<String,dynamic>); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/data/pro_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';

void main() {
  test('ServiceType exposes label/emoji/unit and round-trips', () {
    expect(ServiceType.walker.label, 'Dog Walker');
    expect(ServiceType.walker.unit, 'walk');
    expect(ServiceType.fromStorage('groomer'), ServiceType.groomer);
    expect(ServiceType.fromStorage('nonsense'), ServiceType.walker); // safe default
  });

  test('Pro toMap omits uid/updatedAt; fromMap restores', () {
    const p = Pro(uid: 'u1', name: 'Aarav', area: 'Bandra West', bio: 'Friendly walker',
        serviceType: ServiceType.walker, rate: 250, experienceYears: 4);
    final m = p.toMap();
    expect(m.containsKey('uid'), isFalse);
    expect(m.containsKey('updatedAt'), isFalse);
    expect(m['serviceType'], 'walker');
    expect(m['rating'], 0.0);
    final back = Pro.fromMap('u1', m);
    expect(back.name, 'Aarav');
    expect(back.rate, 250);
    expect(back.serviceType, ServiceType.walker);
    expect(back.unit, 'walk');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/pro_test.dart`
Expected: FAIL — `Pro`/`ServiceType` not found.

- [ ] **Step 3: Implement `lib/data/models/pro.dart`**

```dart
enum ServiceType {
  walker('walker', 'Dog Walker', '🦮', 'walk'),
  sitter('sitter', 'Pet Sitter', '🏠', 'visit'),
  groomer('groomer', 'Groomer', '✂️', 'session'),
  trainer('trainer', 'Trainer', '🎾', 'session');

  final String storageKey, label, emoji, unit;
  const ServiceType(this.storageKey, this.label, this.emoji, this.unit);

  static ServiceType fromStorage(String key) =>
      ServiceType.values.firstWhere((s) => s.storageKey == key, orElse: () => ServiceType.walker);
}

class Pro {
  final String uid, name, area, bio;
  final ServiceType serviceType;
  final int rate, experienceYears, reviewCount;
  final double rating;

  const Pro({
    required this.uid, required this.name, required this.area, required this.bio,
    required this.serviceType, required this.rate, required this.experienceYears,
    this.rating = 0, this.reviewCount = 0,
  });

  String get unit => serviceType.unit;

  Map<String, dynamic> toMap() => {
        'ownerId': uid,
        'name': name,
        'area': area,
        'bio': bio,
        'serviceType': serviceType.storageKey,
        'rate': rate,
        'experienceYears': experienceYears,
        'rating': rating,
        'reviewCount': reviewCount,
      };

  factory Pro.fromMap(String uid, Map<String, dynamic> m) => Pro(
        uid: uid,
        name: (m['name'] ?? '') as String,
        area: (m['area'] ?? '') as String,
        bio: (m['bio'] ?? '') as String,
        serviceType: ServiceType.fromStorage((m['serviceType'] ?? 'walker') as String),
        rate: (m['rate'] ?? 0) as int,
        experienceYears: (m['experienceYears'] ?? 0) as int,
        rating: ((m['rating'] ?? 0) as num).toDouble(),
        reviewCount: (m['reviewCount'] ?? 0) as int,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/pro_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze lib/data/models/pro.dart
git add lib/data/models/pro.dart test/data/pro_test.dart
git commit -m "feat: add Pro + ServiceType models with Firestore serialization"
```

---

### Task 2: `ProRepository` interface + in-memory fake

**Files:**
- Create: `lib/data/repositories/pro_repository.dart`
- Modify: `test/support/fakes.dart` (add `InMemoryProRepository`)
- Test: `test/data/pro_repository_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class ProRepository { Future<void> upsertPro(Pro pro); Stream<Pro?> watchPro(String uid); Stream<List<Pro>> watchPros(); }`
  - `InMemoryProRepository` fake.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/pro_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import '../support/fakes.dart';

void main() {
  test('InMemoryProRepository upserts and streams pros', () async {
    final repo = InMemoryProRepository();
    expect(await repo.watchPros().first, isEmpty);
    await repo.upsertPro(const Pro(uid: 'u1', name: 'Aarav', area: 'Bandra West',
        bio: 'Walker', serviceType: ServiceType.walker, rate: 250, experienceYears: 4));
    expect((await repo.watchPros().first).single.name, 'Aarav');
    expect((await repo.watchPro('u1').first)!.rate, 250);
    // upsert overwrites the same uid.
    await repo.upsertPro(const Pro(uid: 'u1', name: 'Aarav', area: 'Khar',
        bio: 'Walker', serviceType: ServiceType.walker, rate: 300, experienceYears: 5));
    expect((await repo.watchPro('u1').first)!.rate, 300);
    expect((await repo.watchPros().first).length, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/pro_repository_test.dart`
Expected: FAIL — types not found.

- [ ] **Step 3: Create `lib/data/repositories/pro_repository.dart`**

```dart
import '../models/pro.dart';

abstract interface class ProRepository {
  Future<void> upsertPro(Pro pro);
  Stream<Pro?> watchPro(String uid);
  Stream<List<Pro>> watchPros();
}
```

- [ ] **Step 4: Add `InMemoryProRepository` to `test/support/fakes.dart`**

Add imports at the top: `import 'package:pet_aggregator_app/data/models/pro.dart';` and `import 'package:pet_aggregator_app/data/repositories/pro_repository.dart';`. Then append:

```dart
class InMemoryProRepository implements ProRepository {
  final Map<String, Pro> _pros = {};
  final _controller = StreamController<List<Pro>>.broadcast();

  InMemoryProRepository([List<Pro>? seed]) {
    if (seed != null) {
      for (final p in seed) _pros[p.uid] = p;
    }
  }

  List<Pro> _list() => _pros.values.toList();

  @override
  Future<void> upsertPro(Pro pro) async {
    _pros[pro.uid] = pro;
    _controller.add(_list());
  }

  @override
  Stream<Pro?> watchPro(String uid) async* {
    yield _pros[uid];
    yield* _controller.stream.map((_) => _pros[uid]);
  }

  @override
  Stream<List<Pro>> watchPros() async* {
    yield _list();
    yield* _controller.stream.map((_) => _list());
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/pro_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze lib/data
git add lib/data/repositories/pro_repository.dart test/support/fakes.dart test/data/pro_repository_test.dart
git commit -m "feat: add ProRepository interface + in-memory fake"
```

---

### Task 3: `FirestoreProRepository`

**Files:**
- Create: `lib/data/repositories/firebase/firestore_pro_repository.dart`

**Interfaces:**
- Consumes: `ProRepository`, `Pro` (Tasks 1–2).
- Produces: `FirestoreProRepository` (verified on the emulator in Task 9).

- [ ] **Step 1: Create `firestore_pro_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/pro.dart';
import '../pro_repository.dart';

class FirestoreProRepository implements ProRepository {
  final FirebaseFirestore _db;
  FirestoreProRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('pros');

  @override
  Future<void> upsertPro(Pro pro) => _col.doc(pro.uid).set({
        ...pro.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Stream<Pro?> watchPro(String uid) => _col.doc(uid).snapshots().map(
      (doc) => doc.exists ? Pro.fromMap(uid, doc.data()!) : null);

  @override
  Stream<List<Pro>> watchPros() => _col
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Pro.fromMap(d.id, d.data())).toList());
}
```

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze lib/data/repositories/firebase
git add lib/data/repositories/firebase/firestore_pro_repository.dart
git commit -m "feat: add FirestoreProRepository"
```

---

### Task 4: Providers — `proRepositoryProvider`, `prosProvider`, `currentProProvider`

**Files:**
- Modify: `lib/data/repositories/providers.dart`
- Test: `test/data/pros_provider_test.dart`

**Interfaces:**
- Produces:
  - `proRepositoryProvider` → `Provider<ProRepository>`
  - `prosProvider` → `StreamProvider<List<Pro>>`
  - `currentProProvider` → `StreamProvider<Pro?>` (signed-in user's own listing).

- [ ] **Step 1: Write the failing test**

```dart
// test/data/pros_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('currentProProvider streams the signed-in user\'s listing', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository([
        const Pro(uid: 'uid_me@x.com', name: 'Me', area: 'Khar', bio: 'x',
            serviceType: ServiceType.sitter, rate: 400, experienceYears: 2),
      ])),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(currentProProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();
    expect(container.read(currentProProvider).value?.rate, 400);
    expect((container.read(prosProvider).value ?? []).length, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/pros_provider_test.dart`
Expected: FAIL — providers not defined.

- [ ] **Step 3: Append to `lib/data/repositories/providers.dart`**

Add imports at the top: `import '../models/pro.dart';`, `import 'pro_repository.dart';`, `import 'firebase/firestore_pro_repository.dart';`. Then append:

```dart
final proRepositoryProvider = Provider<ProRepository>((ref) => FirestoreProRepository());

final prosProvider = StreamProvider<List<Pro>>((ref) => ref.watch(proRepositoryProvider).watchPros());

final currentProProvider = StreamProvider<Pro?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(proRepositoryProvider).watchPro(user.uid);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/pros_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
flutter analyze lib/data
git add lib/data/repositories/providers.dart test/data/pros_provider_test.dart
git commit -m "feat: add pro providers (proRepositoryProvider, prosProvider, currentProProvider)"
```

---

### Task 5: `ProSetupScreen` + `/pro-setup` route

**Files:**
- Create: `lib/features/services/pro_setup_screen.dart`
- Modify: `lib/core/router/routes.dart` (add `proSetup`, `servicePro`)
- Modify: `lib/core/router/app_router.dart` (import + protect + route)
- Test: `test/features/pro_setup_screen_test.dart`

**Interfaces:**
- Consumes: `proRepositoryProvider`, `currentProProvider`, `currentUserProfileProvider`, `authRepositoryProvider`, `Pro`, `ServiceType`, `PgTextField`, `PgPrimaryButton`, `PgAppBar`.
- Produces: `ProSetupScreen`; `Routes.proSetup == '/pro-setup'`, `Routes.servicePro == '/service-pro'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/pro_setup_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('filling the form and saving writes a pro listing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Aarav Sharma',
        email: 'me@x.com', area: 'Bandra West', role: Role.servicePro));
    final pros = InMemoryProRepository();

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      proRepositoryProvider.overrideWithValue(pros),
    ], initialLocation: Routes.proSetup);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '250'); // rate
    await tester.enterText(find.byType(TextField).at(1), '4');   // experience
    await tester.enterText(find.byType(TextField).at(2), 'Friendly walker'); // bio
    await tester.tap(find.text('Save listing'));
    await tester.pumpAndSettle();

    final mine = await pros.watchPro(auth.currentUser!.uid).first;
    expect(mine!.name, 'Aarav Sharma');
    expect(mine.rate, 250);
    expect(mine.area, 'Bandra West');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/pro_setup_screen_test.dart`
Expected: FAIL — `ProSetupScreen` / routes not found.

- [ ] **Step 3: Add the route constants**

In `lib/core/router/routes.dart`, add inside `class Routes`:
```dart
  static const proSetup = '/pro-setup';
  static const servicePro = '/service-pro';
```

- [ ] **Step 4: Implement `pro_setup_screen.dart`**

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
import '../../data/models/pro.dart';
import '../../data/repositories/providers.dart';

class ProSetupScreen extends ConsumerStatefulWidget {
  const ProSetupScreen({super.key});
  @override
  ConsumerState<ProSetupScreen> createState() => _ProSetupScreenState();
}

class _ProSetupScreenState extends ConsumerState<ProSetupScreen> {
  final _rate = TextEditingController();
  final _exp = TextEditingController();
  final _bio = TextEditingController();
  ServiceType _type = ServiceType.walker;
  double _rating = 0;
  int _reviewCount = 0;
  bool _seeded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _rate.dispose();
    _exp.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _seed(Pro p) {
    _type = p.serviceType;
    _rate.text = p.rate.toString();
    _exp.text = p.experienceYears.toString();
    _bio.text = p.bio;
    _rating = p.rating;
    _reviewCount = p.reviewCount;
  }

  Future<void> _save() async {
    final rate = int.tryParse(_rate.text.trim()) ?? 0;
    if (rate <= 0) {
      setState(() => _error = 'Enter a rate greater than 0.');
      return;
    }
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    final profile = ref.read(currentUserProfileProvider).value;
    setState(() { _saving = true; _error = null; });
    await ref.read(proRepositoryProvider).upsertPro(Pro(
          uid: uid, name: profile?.name ?? '', area: profile?.area ?? '',
          bio: _bio.text.trim(), serviceType: _type, rate: rate,
          experienceYears: int.tryParse(_exp.text.trim()) ?? 0,
          rating: _rating, reviewCount: _reviewCount));
    if (mounted) context.go(Routes.services);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    ref.listen(currentProProvider, (prev, next) {
      if (!_seeded && next.hasValue && next.value != null) {
        setState(() => _seed(next.value!));
        _seeded = true;
      }
    });

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Offer your services', onBack: () => context.go(Routes.services)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
              children: [
                Text('Set up your listing so pet parents can find and book you.',
                    style: PgText.inter(14, FontWeight.w400, color: c.muted, height: 1.5)),
                const SizedBox(height: 16),
                Text('Service type', style: PgText.label(context)),
                const SizedBox(height: 8),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (final t in ServiceType.values)
                    GestureDetector(
                      onTap: () => setState(() => _type = t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _type == t ? c.brandSoft : c.surface,
                          border: Border.all(color: _type == t ? c.brand : c.border, width: _type == t ? 2 : 1),
                          borderRadius: BorderRadius.circular(13)),
                        child: Text('${t.emoji} ${t.label}',
                          style: PgText.inter(13, FontWeight.w600, color: _type == t ? c.brand : c.text)),
                      ),
                    ),
                ]),
                const SizedBox(height: 16),
                PgTextField(label: 'Rate (₹ per ${_type.unit})', controller: _rate,
                    keyboardType: TextInputType.number, hint: '250'),
                const SizedBox(height: 14),
                PgTextField(label: 'Experience (years)', controller: _exp,
                    keyboardType: TextInputType.number, hint: '4'),
                const SizedBox(height: 14),
                PgTextField(label: 'About you', controller: _bio, hint: 'Tell parents about yourself'),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart))),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: PgPrimaryButton(label: _saving ? 'Saving…' : 'Save listing',
              onPressed: _saving ? () {} : _save),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 5: Wire the route in `app_router.dart`**

Add `import '../../features/services/pro_setup_screen.dart';`, add `Routes.proSetup, Routes.servicePro` to the `_protected` set, and add the route (near the other top-level routes, before the `StatefulShellRoute`):
```dart
      GoRoute(path: Routes.proSetup, builder: (_, _) => const ProSetupScreen()),
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/pro_setup_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
flutter analyze
git add lib/features/services/pro_setup_screen.dart lib/core/router/routes.dart lib/core/router/app_router.dart test/features/pro_setup_screen_test.dart
git commit -m "feat: add Pro-setup screen (servicePro creates a listing) + /pro-setup route"
```

---

### Task 6: `ServicesListScreen` + Services tab

**Files:**
- Create: `lib/features/services/services_list_screen.dart`
- Modify: `lib/core/router/app_router.dart` (Services branch → `ServicesListScreen`)
- Test: `test/features/services_list_screen_test.dart`

**Interfaces:**
- Consumes: `prosProvider`, `currentProProvider`, `currentUserProfileProvider`, `Pro`, `ServiceType`, `Role`, `showComingSoon`, `PgImageSlot`, `Routes`.
- Produces: `ServicesListScreen` (replaces `PlaceholderTab(title:'Services')`).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/services_list_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _aarav = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West', bio: 'Walker',
    serviceType: ServiceType.walker, rate: 250, experienceYears: 4);

void main() {
  testWidgets('lists live pros', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository([_aarav])),
    ], initialLocation: Routes.services);
    await tester.pumpAndSettle();
    expect(find.text('Services near you'), findsOneWidget);
    expect(find.text('Aarav Sharma'), findsOneWidget);
  });

  testWidgets('shows a set-up banner for a servicePro without a listing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com',
        area: 'Khar', role: Role.servicePro));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    ], initialLocation: Routes.services);
    await tester.pumpAndSettle();
    expect(find.text('Set up your services'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/services_list_screen_test.dart`
Expected: FAIL — `ServicesListScreen` not found.

- [ ] **Step 3: Implement `services_list_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/pro.dart';
import '../../data/models/role.dart';
import '../../data/repositories/providers.dart';

class ServicesListScreen extends ConsumerStatefulWidget {
  const ServicesListScreen({super.key});
  @override
  ConsumerState<ServicesListScreen> createState() => _ServicesListScreenState();
}

class _ServicesListScreenState extends ConsumerState<ServicesListScreen> {
  ServiceType? _filter;

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final prosAsync = ref.watch(prosProvider);
    final currentPro = ref.watch(currentProProvider);
    final profile = ref.watch(currentUserProfileProvider).value;
    final isProWithoutListing =
        profile?.role == Role.servicePro && currentPro.hasValue && currentPro.value == null;

    return Container(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
            decoration: BoxDecoration(color: c.peach,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Services near you', style: PgText.poppins(24, FontWeight.w800, color: c.text, ls: -0.4)),
              const SizedBox(height: 3),
              Text('Verified walkers, sitters & groomers',
                style: PgText.inter(13, FontWeight.w500, color: c.text)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              children: [
                if (isProWithoutListing)
                  GestureDetector(
                    onTap: () => context.go(Routes.proSetup),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 18),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        const Text('🎒', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Set up your services', style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
                          Text('Create a listing so parents can book you',
                            style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                        ])),
                        Icon(Icons.chevron_right, color: c.brand),
                      ]),
                    ),
                  ),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  for (final t in ServiceType.values)
                    GestureDetector(
                      onTap: () => setState(() => _filter = _filter == t ? null : t),
                      child: Column(children: [
                        Container(
                          width: 60, height: 60, alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _filter == t ? c.brand : c.surface,
                            borderRadius: BorderRadius.circular(19), boxShadow: c.shadowSm),
                          child: Text(t.emoji, style: const TextStyle(fontSize: 25))),
                        const SizedBox(height: 7),
                        Text(t.label.split(' ').last,
                          style: PgText.inter(11.5, FontWeight.w600, color: c.text)),
                      ]),
                    ),
                ]),
                const SizedBox(height: 22),
                Text('Recommended', style: PgText.sectionHeader(context)),
                const SizedBox(height: 13),
                prosAsync.when(
                  loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text('Could not load services.',
                    style: PgText.inter(13.5, FontWeight.w500, color: c.muted)),
                  data: (pros) {
                    final list = _filter == null
                        ? pros
                        : pros.where((p) => p.serviceType == _filter).toList();
                    if (list.isEmpty) {
                      return Padding(padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('No pros nearby yet — check back soon.',
                          style: PgText.inter(13.5, FontWeight.w400, color: c.muted)));
                    }
                    return Column(children: [
                      for (final p in list) ...[_ProCard(pro: p), const SizedBox(height: 13)],
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

class _ProCard extends StatelessWidget {
  final Pro pro;
  const _ProCard({required this.pro});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final rating = pro.reviewCount == 0
        ? 'New'
        : '★ ${pro.rating.toStringAsFixed(1)} (${pro.reviewCount})';
    return GestureDetector(
      onTap: () => context.push(Routes.servicePro, extra: pro),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(18), boxShadow: c.shadowSm),
        child: Row(children: [
          const PgImageSlot(size: 66, radius: 16, emoji: '🧑'),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(pro.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: PgText.poppins(14.5, FontWeight.w700, color: c.text))),
              const SizedBox(width: 4),
              Icon(Icons.verified, size: 14, color: c.brand),
            ]),
            const SizedBox(height: 2),
            Text('${pro.serviceType.label} · ${pro.experienceYears} yrs',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
            const SizedBox(height: 6),
            Text(rating, style: PgText.inter(12.5, FontWeight.w700, color: c.brandDeep)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${pro.rate}', style: PgText.poppins(16, FontWeight.w800, color: c.brand)),
            Text('/${pro.unit}', style: PgText.inter(11, FontWeight.w400, color: c.faint)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => showComingSoon(context, 'Booking'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
                child: Text('Book', style: PgText.poppins(12.5, FontWeight.w700, color: c.brand)))),
          ]),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Point the Services branch at `ServicesListScreen`**

In `lib/core/router/app_router.dart`: add `import '../../features/services/services_list_screen.dart';` and change the Services branch route from `const PlaceholderTab(title: 'Services')` to `const ServicesListScreen()`.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/services_list_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze
git add lib/features/services/services_list_screen.dart lib/core/router/app_router.dart test/features/services_list_screen_test.dart
git commit -m "feat: add Services list screen (live pros, category filter, pro-setup banner)"
```

---

### Task 7: `ProProfileScreen` + `/service-pro` route

**Files:**
- Create: `lib/features/services/pro_profile_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/service-pro` route)
- Test: `test/features/pro_profile_screen_test.dart`

**Interfaces:**
- Consumes: `Pro`, `showComingSoon`, `PgImageSlot`, theme.
- Produces: `ProProfileScreen({Pro? pro})` — a `StatelessWidget` (renders the passed `Pro`; needs no providers).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/pro_profile_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/features/services/pro_profile_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the pro and shows New rating; Book hints coming soon', (tester) async {
    const pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West',
        bio: 'Friendly reliable walker.', serviceType: ServiceType.walker,
        rate: 250, experienceYears: 4);
    await pumpPg(tester, const ProProfileScreen(pro: pro));
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Friendly reliable walker.'), findsOneWidget);
    expect(find.textContaining('New'), findsWidgets); // no reviews yet
    await tester.tap(find.textContaining('Book'));
    await tester.pump();
    expect(find.text('Booking is coming soon 🐾'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/pro_profile_screen_test.dart`
Expected: FAIL — `ProProfileScreen` not found.

- [ ] **Step 3: Implement `pro_profile_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/pro.dart';

class ProProfileScreen extends StatelessWidget {
  final Pro? pro;
  const ProProfileScreen({super.key, this.pro});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final p = pro;
    if (p == null) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(backgroundColor: c.bg, elevation: 0),
        body: Center(child: Text('Pro not found', style: PgText.body(context))),
      );
    }
    final ratingBadge = p.reviewCount == 0
        ? 'New'
        : '★ ${p.rating.toStringAsFixed(1)} · ${p.reviewCount} reviews';

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                height: 120,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFF59E2E), Color(0xFFF0871E)])),
                child: SafeArea(
                  child: Align(alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          width: 40, height: 40, alignment: Alignment.center,
                          decoration: BoxDecoration(color: const Color(0x33FFFFFF),
                            borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.chevron_left, color: Colors.white))),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -40),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22),
                        boxShadow: c.shadow),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const PgImageSlot(size: 78, radius: 18, emoji: '🧑'),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: PgText.poppins(19, FontWeight.w800, color: c.text))),
                              const SizedBox(width: 5),
                              Icon(Icons.verified, size: 16, color: c.brand),
                            ]),
                            const SizedBox(height: 2),
                            Text('${p.serviceType.label} · ${p.area}',
                              style: PgText.inter(13, FontWeight.w400, color: c.muted)),
                            const SizedBox(height: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(20)),
                              child: Text(ratingBadge, style: PgText.inter(12.5, FontWeight.w700, color: c.brandDeep))),
                          ])),
                        ]),
                        const SizedBox(height: 16),
                        Container(height: 1, color: c.border),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: _stat('${p.experienceYears} yrs', 'Experience', c)),
                          Container(width: 1, height: 34, color: c.border),
                          Expanded(child: _stat('₹${p.rate}', 'per ${p.unit}', c, brand: true)),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Text('About', style: PgText.sectionHeader(context)),
                    const SizedBox(height: 7),
                    Text(p.bio.isEmpty ? 'No description yet.' : p.bio,
                      style: PgText.inter(13.5, FontWeight.w400, color: c.muted, height: 1.6)),
                    const SizedBox(height: 20),
                    Text('Reviews', style: PgText.sectionHeader(context)),
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
            GestureDetector(
              onTap: () => showComingSoon(context, 'Chat'),
              child: Container(
                width: 54, height: 54, alignment: Alignment.center,
                decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                child: const Text('💬', style: TextStyle(fontSize: 21)))),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () => showComingSoon(context, 'Booking'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(16)),
                child: Text('Book · ₹${p.rate}', style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white))))),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(String value, String label, PgColors c, {bool brand = false}) => Column(children: [
        Text(value, style: PgText.poppins(17, FontWeight.w800, color: brand ? c.brand : c.text)),
        Text(label, style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
      ]);
}
```

- [ ] **Step 4: Add the `/service-pro` route**

In `lib/core/router/app_router.dart`: add `import '../../features/services/pro_profile_screen.dart';` and the route (near `/pro-setup`):
```dart
      GoRoute(path: Routes.servicePro, builder: (_, state) => ProProfileScreen(pro: state.extra as Pro?)),
```
Add `import '../../data/models/pro.dart';` to `app_router.dart` for the cast.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/pro_profile_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/services/pro_profile_screen.dart lib/core/router/app_router.dart test/features/pro_profile_screen_test.dart
git commit -m "feat: add Pro profile screen + /service-pro route"
```
Expected: whole suite green, analyze clean.

---

### Task 8: Firestore rules for `pros`; deploy

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Add the `pros` block to `firestore.rules`**

Inside `match /databases/{database}/documents { ... }`, after the `swipes` block:
```
    match /pros/{uid} {
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
git commit -m "chore: add + deploy Firestore rules for pros (owner-write, authed-read)"
```

---

### Task 9: Emulator integration test + final verification

**Files:**
- Modify: `integration_test/firebase_repos_test.dart` (add a `pros` round-trip test)

- [ ] **Step 1: Append a pros test to `integration_test/firebase_repos_test.dart`**

Add `import 'package:pet_aggregator_app/data/models/pro.dart';` and `import 'package:pet_aggregator_app/data/repositories/firebase/firestore_pro_repository.dart';`, then add a `testWidgets` inside `main()`:
```dart
  testWidgets('pros upsert + watch round-trip (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final prosRepo = FirestoreProRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'pro_$stamp@x.com', password: 'secret1');

    await prosRepo.upsertPro(Pro(uid: me.uid, name: 'Aarav', area: 'Bandra West',
        bio: 'Walker', serviceType: ServiceType.walker, rate: 250, experienceYears: 4));
    final mine = await prosRepo.watchPro(me.uid).firstWhere((p) => p != null);
    expect(mine!.rate, 250);
    final all = await prosRepo.watchPros().firstWhere((l) => l.any((p) => p.uid == me.uid));
    expect(all.any((p) => p.name == 'Aarav'), isTrue);

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

Run: `flutter run -d emulator-5554`. Sign in as a **Service Professional** account → Services tab shows the "Set up your services" banner → create a listing. Sign in as a pet-parent account → Services tab lists that pro; tap it → Pro profile renders; "Book" shows the coming-soon snackbar. Confirm a `pros/{uid}` doc exists in the console.

- [ ] **Step 5: Commit**

```bash
git add integration_test/firebase_repos_test.dart
git commit -m "test: verify pros upsert/watch against Firestore emulators"
```

---

## Self-Review

**Spec coverage:**
- `pros` collection + `Pro`/`ServiceType` models → Tasks 1–3. ✓
- `ProRepository` + fake + Firestore + providers (`prosProvider`, `currentProProvider`) → Tasks 2–4. ✓
- Pro-setup screen (create/edit listing, pre-fill) → Task 5. ✓
- Services list (live pros, category filter, setup banner, "Book" → coming-soon) → Task 6. ✓
- Pro profile (stats, About, Reviews-empty, "New" rating, chat/Book → coming-soon) → Task 7. ✓
- Rules + deploy → Task 8. ✓
- TDD fakes + emulator integration → each task + Task 9. ✓
- Out-of-scope (booking/payment/bookings, reviews, chat, Storage, geo) → none implemented. ✓

**Placeholder scan:** No "TBD/TODO". Every code step is complete. "Book"/chat intentionally call `showComingSoon` (Slice 4b rewires Book).

**Type consistency:**
- `Pro` fields (`uid, name, area, bio, serviceType, rate, experienceYears, rating, reviewCount`) + `unit` getter identical across Task 1 (model), Task 5 (setup write), Task 6 (card), Task 7 (profile), Task 9 (integration). ✓
- `ProRepository` methods (`upsertPro`, `watchPro`, `watchPros`) match between interface (Task 2), fake (Task 2), Firestore (Task 3), and callers (Tasks 4–9). ✓
- Providers (`proRepositoryProvider`, `prosProvider`, `currentProProvider`) defined Task 4, consumed Tasks 5–7. ✓
- `Routes.proSetup` / `Routes.servicePro` added Task 5, used Tasks 5 (route), 6 (`push servicePro`, `go proSetup`), 7 (route). ✓
- `ServiceType` (`label`, `emoji`, `unit`, `storageKey`) consistent across Tasks 1, 5, 6, 7. ✓
- `showComingSoon(context, label)` (from Slice 3) reused in Tasks 6, 7. ✓

