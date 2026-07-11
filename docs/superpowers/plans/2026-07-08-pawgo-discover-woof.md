# Pawgo Slice 3: Discovery / "Woof" — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Discover pillar on live Firestore — a drag-to-swipe deck of real nearby pets, real Woof/Pass persisted to a `swipes` collection, reciprocal-woof match celebration, and a faux-map Nearby screen.

**Architecture:** Feature-first Flutter on the Slice 2 repository seam. A new `SwipeRepository` (interface + Firestore impl + in-memory fake) records swipes; `discoverDeckProvider` derives the deck from `nearbyPetsProvider` minus the user's swiped pet ids. Screens are thin `Consumer` composition; `PgSwipeCard` owns the drag/fling gesture. Tests use in-memory fakes via `pumpPgApp`; the emulator integration test covers the real Firestore path.

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `cloud_firestore`, `flutter_riverpod`, `go_router`, `google_fonts`. **No new packages.**

**Spec:** `docs/superpowers/specs/2026-07-08-pawgo-discover-woof-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false`.
- **Live Firestore, no mock data.** UI/tests depend only on repository interfaces; never import `cloud_firestore`/`firebase_auth` outside `data/repositories/firebase/`, `lib/main.dart`, and `integration_test/`.
- **No new integrations:** no Storage/photos, no google_maps/geolocation (Nearby is a faux map; cards show `area`, not km), no Cloud Functions, no chat/pet-profile (those links call `showComingSoon`).
- Riverpod 3.x: use `AsyncValue.value` (not `valueOrNull`); in tests, `Override` comes from `package:flutter_riverpod/misc.dart`; prefer a repo stream's `.first` over `StreamProvider.future`.
- `go_router` builders use `(_, _)`. Screen tests use the `pumpPgApp` harness (phone viewport + `ProviderScope` overrides). Any plain `test()` touching `GoogleFonts` uses `testWidgets`.
- Firestore writes set `createdAt` via `FieldValue.serverTimestamp()` in the repository, never in model `toMap()`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: Swipe model + `SwipeRepository` interface + in-memory fake

**Files:**
- Create: `lib/data/models/swipe.dart`
- Create: `lib/data/repositories/swipe_repository.dart`
- Modify: `test/support/fakes.dart` (add `InMemorySwipeRepository`)
- Test: `test/data/swipe_test.dart`

**Interfaces:**
- Produces:
  - `enum SwipeDirection { woof, pass }` with `String get storageKey` and `static SwipeDirection fromStorage(String)`.
  - `class Swipe { final String fromUid, petId, ownerId; final SwipeDirection direction; const Swipe({...}); String get id; Map<String,dynamic> toMap(); }` where `id == '${fromUid}_$petId'`.
  - `abstract interface class SwipeRepository { Future<void> recordSwipe(Swipe swipe); Stream<Set<String>> watchSwipedPetIds(String uid); Future<bool> hasReciprocalWoof({required String otherUid, required String myUid}); }`
  - `InMemorySwipeRepository` fake.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/swipe_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import '../support/fakes.dart';

void main() {
  test('Swipe id is deterministic and toMap carries direction key', () {
    const s = Swipe(fromUid: 'A', petId: 'p1', ownerId: 'B', direction: SwipeDirection.woof);
    expect(s.id, 'A_p1');
    expect(s.toMap()['direction'], 'woof');
    expect(SwipeDirection.fromStorage('pass'), SwipeDirection.pass);
  });

  test('InMemorySwipeRepository records, streams ids, detects reciprocity', () async {
    final repo = InMemorySwipeRepository();
    await repo.recordSwipe(const Swipe(fromUid: 'me', petId: 'p1', ownerId: 'B', direction: SwipeDirection.woof));
    final ids = await repo.watchSwipedPetIds('me').first;
    expect(ids, {'p1'});

    // No reciprocity yet: B has not woofed one of my pets.
    expect(await repo.hasReciprocalWoof(otherUid: 'B', myUid: 'me'), isFalse);
    // B woofs my pet -> reciprocity from my perspective.
    await repo.recordSwipe(const Swipe(fromUid: 'B', petId: 'myPet', ownerId: 'me', direction: SwipeDirection.woof));
    expect(await repo.hasReciprocalWoof(otherUid: 'B', myUid: 'me'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/swipe_test.dart`
Expected: FAIL — `Swipe`/`SwipeRepository`/`InMemorySwipeRepository` not found.

- [ ] **Step 3: Create `lib/data/models/swipe.dart`**

```dart
enum SwipeDirection {
  woof('woof'),
  pass('pass');

  final String storageKey;
  const SwipeDirection(this.storageKey);

  static SwipeDirection fromStorage(String key) =>
      SwipeDirection.values.firstWhere((d) => d.storageKey == key, orElse: () => SwipeDirection.pass);
}

class Swipe {
  final String fromUid, petId, ownerId;
  final SwipeDirection direction;
  const Swipe({
    required this.fromUid, required this.petId, required this.ownerId, required this.direction,
  });

  String get id => '${fromUid}_$petId';

  Map<String, dynamic> toMap() => {
        'fromUid': fromUid,
        'petId': petId,
        'ownerId': ownerId,
        'direction': direction.storageKey,
      };
}
```

- [ ] **Step 4: Create `lib/data/repositories/swipe_repository.dart`**

```dart
import '../models/swipe.dart';

abstract interface class SwipeRepository {
  Future<void> recordSwipe(Swipe swipe);
  Stream<Set<String>> watchSwipedPetIds(String uid);
  Future<bool> hasReciprocalWoof({required String otherUid, required String myUid});
}
```

- [ ] **Step 5: Add `InMemorySwipeRepository` to `test/support/fakes.dart`**

Add these imports at the top if missing: `import 'package:pet_aggregator_app/data/models/swipe.dart';` and `import 'package:pet_aggregator_app/data/repositories/swipe_repository.dart';`. Then append:

```dart
class InMemorySwipeRepository implements SwipeRepository {
  final List<Swipe> _swipes = [];
  final _controller = StreamController<List<Swipe>>.broadcast();

  InMemorySwipeRepository([List<Swipe>? seed]) {
    if (seed != null) _swipes.addAll(seed);
  }

  @override
  Future<void> recordSwipe(Swipe swipe) async {
    _swipes.removeWhere((s) => s.id == swipe.id);
    _swipes.add(swipe);
    _controller.add(List.of(_swipes));
  }

  @override
  Stream<Set<String>> watchSwipedPetIds(String uid) async* {
    Set<String> ids() => _swipes.where((s) => s.fromUid == uid).map((s) => s.petId).toSet();
    yield ids();
    yield* _controller.stream.map((_) => ids());
  }

  @override
  Future<bool> hasReciprocalWoof({required String otherUid, required String myUid}) async =>
      _swipes.any((s) =>
          s.fromUid == otherUid && s.ownerId == myUid && s.direction == SwipeDirection.woof);
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/data/swipe_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add lib/data/models/swipe.dart lib/data/repositories/swipe_repository.dart test/support/fakes.dart test/data/swipe_test.dart
git commit -m "feat: add Swipe model + SwipeRepository interface + in-memory fake"
```

---

### Task 2: `FirestoreSwipeRepository`

**Files:**
- Create: `lib/data/repositories/firebase/firestore_swipe_repository.dart`

**Interfaces:**
- Consumes: `SwipeRepository`, `Swipe` (Task 1).
- Produces: `FirestoreSwipeRepository` (concrete; verified on the emulator in Task 10).

- [ ] **Step 1: Create `firestore_swipe_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/swipe.dart';
import '../swipe_repository.dart';

class FirestoreSwipeRepository implements SwipeRepository {
  final FirebaseFirestore _db;
  FirestoreSwipeRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('swipes');

  @override
  Future<void> recordSwipe(Swipe swipe) => _col.doc(swipe.id).set({
        ...swipe.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  @override
  Stream<Set<String>> watchSwipedPetIds(String uid) => _col
      .where('fromUid', isEqualTo: uid)
      .snapshots()
      .map((snap) => snap.docs.map((d) => d.data()['petId'] as String).toSet());

  @override
  Future<bool> hasReciprocalWoof({required String otherUid, required String myUid}) async {
    final q = await _col
        .where('fromUid', isEqualTo: otherUid)
        .where('ownerId', isEqualTo: myUid)
        .where('direction', isEqualTo: 'woof')
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }
}
```

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze lib/data/repositories/firebase
git add lib/data/repositories/firebase/firestore_swipe_repository.dart
git commit -m "feat: add FirestoreSwipeRepository"
```

---

### Task 3: Providers — `swipeRepositoryProvider`, `swipedPetIdsProvider`, `discoverDeckProvider`

**Files:**
- Modify: `lib/data/repositories/providers.dart`
- Test: `test/data/discover_deck_test.dart`

**Interfaces:**
- Produces:
  - `swipeRepositoryProvider` → `Provider<SwipeRepository>`
  - `swipedPetIdsProvider` → `StreamProvider<Set<String>>`
  - `discoverDeckProvider` → `Provider<AsyncValue<List<PetProfile>>>` (nearby pets minus swiped ids).

- [ ] **Step 1: Write the failing test**

```dart
// test/data/discover_deck_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('discoverDeckProvider excludes own pets and already-swiped pets', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('someone-else'))),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository([
        const Swipe(fromUid: 'uid_me@x.com', petId: 'p1', ownerId: 'someone-else', direction: SwipeDirection.pass),
      ])),
    ]);
    addTearDown(container.dispose);

    container.listen(swipedPetIdsProvider, (_, _) {}, fireImmediately: true);
    container.listen(discoverDeckProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();

    final deck = container.read(discoverDeckProvider).value!;
    expect(deck.any((p) => p.id == 'p1'), isFalse); // already swiped
    expect(deck, isNotEmpty); // p2, p3 remain
    expect(deck.every((p) => p.ownerId != 'uid_me@x.com'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/discover_deck_test.dart`
Expected: FAIL — providers not defined.

- [ ] **Step 3: Append to `lib/data/repositories/providers.dart`**

Add the import at the top: `import 'swipe_repository.dart';` and `import 'firebase/firestore_swipe_repository.dart';`. Then append:

```dart
final swipeRepositoryProvider = Provider<SwipeRepository>((ref) => FirestoreSwipeRepository());

final swipedPetIdsProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(<String>{});
  return ref.watch(swipeRepositoryProvider).watchSwipedPetIds(user.uid);
});

final discoverDeckProvider = Provider<AsyncValue<List<PetProfile>>>((ref) {
  final swiped = ref.watch(swipedPetIdsProvider).value ?? const <String>{};
  return ref.watch(nearbyPetsProvider).whenData(
      (pets) => pets.where((p) => !swiped.contains(p.id)).toList());
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/discover_deck_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
flutter analyze lib/data
git add lib/data/repositories/providers.dart test/data/discover_deck_test.dart
git commit -m "feat: add swipe providers + discoverDeckProvider (nearby minus swiped)"
```

---

### Task 4: `showComingSoon` snackbar helper

**Files:**
- Create: `lib/core/widgets/pg_snackbar.dart`
- Test: `test/core/widgets/pg_snackbar_test.dart`

**Interfaces:**
- Produces: `void showComingSoon(BuildContext context, String label)` — floating SnackBar "{label} is coming soon 🐾".

- [ ] **Step 1: Write the failing test**

```dart
// test/core/widgets/pg_snackbar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_snackbar.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('showComingSoon shows a labelled snackbar', (tester) async {
    await pumpPg(tester, Builder(builder: (context) {
      return TextButton(onPressed: () => showComingSoon(context, 'Chat'), child: const Text('go'));
    }));
    await tester.tap(find.text('go'));
    await tester.pump(); // let the snackbar appear
    expect(find.text('Chat is coming soon 🐾'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/pg_snackbar_test.dart`
Expected: FAIL — `showComingSoon` not found.

- [ ] **Step 3: Implement `pg_snackbar.dart`**

```dart
import 'package:flutter/material.dart';

void showComingSoon(BuildContext context, String label) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('$label is coming soon 🐾'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/pg_snackbar_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/pg_snackbar.dart test/core/widgets/pg_snackbar_test.dart
git commit -m "feat: add showComingSoon snackbar helper"
```

---

### Task 5: `PgSwipeCard` — drag/fling gesture card

**Files:**
- Create: `lib/core/widgets/pg_swipe_card.dart`
- Test: `test/core/widgets/pg_swipe_card_test.dart`

**Interfaces:**
- Consumes: `PetProfile`, `PgImageSlot`, `PgChip`, theme.
- Produces: `PgSwipeCard({required PetProfile pet, required VoidCallback onWoof, required VoidCallback onPass})` — drag horizontally; past a ±110px threshold the card flings off and fires `onWoof` (right) / `onPass` (left); under threshold it springs back. `PASS`/`WOOF!` overlays fade with drag.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/widgets/pg_swipe_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_swipe_card.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import '../../support/pump.dart';

PetProfile _pet() => PetProfile(
    id: 'p1', ownerId: 'B', name: 'Bruno', breed: 'Labrador', ageLabel: '2 yrs',
    sex: 'male', area: 'Bandra West', species: Species.dog, vaccinated: true,
    accentColor: PetProfile.accentFor('Bruno'));

void main() {
  testWidgets('drag right past threshold fires onWoof', (tester) async {
    var woofed = false, passed = false;
    await pumpPg(tester, PgSwipeCard(pet: _pet(), onWoof: () => woofed = true, onPass: () => passed = true));
    await tester.drag(find.byType(PgSwipeCard), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(woofed, isTrue);
    expect(passed, isFalse);
  });

  testWidgets('drag left past threshold fires onPass', (tester) async {
    var woofed = false, passed = false;
    await pumpPg(tester, PgSwipeCard(pet: _pet(), onWoof: () => woofed = true, onPass: () => passed = true));
    await tester.drag(find.byType(PgSwipeCard), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(passed, isTrue);
    expect(woofed, isFalse);
  });

  testWidgets('small drag springs back, fires nothing', (tester) async {
    var woofed = false, passed = false;
    await pumpPg(tester, PgSwipeCard(pet: _pet(), onWoof: () => woofed = true, onPass: () => passed = true));
    await tester.drag(find.byType(PgSwipeCard), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(woofed, isFalse);
    expect(passed, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/pg_swipe_card_test.dart`
Expected: FAIL — `PgSwipeCard` not found.

- [ ] **Step 3: Implement `pg_swipe_card.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../../data/models/pet_profile.dart';
import 'pg_image_slot.dart';

class PgSwipeCard extends StatefulWidget {
  final PetProfile pet;
  final VoidCallback onWoof;
  final VoidCallback onPass;
  const PgSwipeCard(
      {super.key, required this.pet, required this.onWoof, required this.onPass});

  @override
  State<PgSwipeCard> createState() => _PgSwipeCardState();
}

class _PgSwipeCardState extends State<PgSwipeCard> with SingleTickerProviderStateMixin {
  static const _threshold = 110.0;
  late final AnimationController _controller;
  Animation<Offset>? _anim;
  Offset _drag = Offset.zero;
  VoidCallback? _pending;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
      ..addListener(() {
        if (_anim != null) setState(() => _drag = _anim!.value);
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          final cb = _pending;
          _pending = null;
          if (cb != null) cb();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(Offset target, {VoidCallback? then}) {
    _anim = Tween(begin: _drag, end: target)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _pending = then;
    _controller.forward(from: 0);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_controller.isAnimating) return;
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    final w = MediaQuery.of(context).size.width;
    if (_drag.dx > _threshold) {
      _animateTo(Offset(w * 1.5, _drag.dy), then: widget.onWoof);
    } else if (_drag.dx < -_threshold) {
      _animateTo(Offset(-w * 1.5, _drag.dy), then: widget.onPass);
    } else {
      _animateTo(Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final woofOpacity = (_drag.dx / _threshold).clamp(0.0, 1.0);
    final passOpacity = (-_drag.dx / _threshold).clamp(0.0, 1.0);
    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: _drag,
        child: Transform.rotate(
          angle: _drag.dx / 1400,
          child: Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: c.border),
              boxShadow: c.shadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Expanded(
                child: Stack(children: [
                  const Positioned.fill(child: PgImageSlot(radius: 0, emoji: '🐶')),
                  Positioned(
                    top: 22, left: 20,
                    child: Opacity(opacity: passOpacity, child: _stamp('PASS', const Color(0xFFF2547B))),
                  ),
                  Positioned(
                    top: 22, right: 20,
                    child: Opacity(opacity: woofOpacity, child: _stamp('WOOF!', c.brand)),
                  ),
                  Positioned(
                    left: 16, bottom: 16,
                    child: Row(children: [
                      if (widget.pet.vaccinated) _pill('✓ Vaccinated', c.brand),
                      const SizedBox(width: 8),
                      _pill('📍 ${widget.pet.area}', c.blue),
                    ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic, children: [
                    Text(widget.pet.name, style: PgText.poppins(24, FontWeight.w800, color: c.text, ls: -0.4)),
                    const SizedBox(width: 8),
                    Text(widget.pet.ageLabel, style: PgText.inter(16, FontWeight.w600, color: c.muted)),
                  ]),
                  const SizedBox(height: 5),
                  Text('${widget.pet.breed} · ${widget.pet.sex} · ${widget.pet.area}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: PgText.inter(14, FontWeight.w400, color: c.muted)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stamp(String text, Color color) => Transform.rotate(
        angle: text == 'PASS' ? -0.24 : 0.24,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: color, width: 4),
            borderRadius: BorderRadius.circular(12)),
          child: Text(text, style: PgText.poppins(26, FontWeight.w800, color: color)),
        ),
      );

  Widget _pill(String text, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE6FFFFFF), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: PgText.inter(12, FontWeight.w700, color: fg)),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/pg_swipe_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
flutter analyze lib/core
git add lib/core/widgets/pg_swipe_card.dart test/core/widgets/pg_swipe_card_test.dart
git commit -m "feat: add PgSwipeCard drag/fling gesture card with PASS/WOOF stamps"
```

---

### Task 6: `WoofMatchScreen` + `/woof-match` route

**Files:**
- Create: `lib/features/discovery/woof_match_screen.dart`
- Modify: `lib/core/router/routes.dart` (add `woofMatch`)
- Modify: `lib/core/router/app_router.dart` (add route + protect it)
- Test: `test/features/woof_match_screen_test.dart`

**Interfaces:**
- Consumes: `PetProfile`, `showComingSoon`, `PgImageSlot`, `PgPrimaryButton`.
- Produces: `WoofMatchScreen({PetProfile? pet})`; `Routes.woofMatch == '/woof-match'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/woof_match_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/features/discovery/woof_match_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('shows the match heading and both actions; Send a message hints coming soon',
      (tester) async {
    final pet = PetProfile(
        id: 'p1', ownerId: 'B', name: 'Bruno', breed: 'Labrador', ageLabel: '2 yrs',
        sex: 'male', area: 'Bandra West', species: Species.dog, vaccinated: true,
        accentColor: PetProfile.accentFor('Bruno'));
    await pumpPg(tester, WoofMatchScreen(pet: pet));
    expect(find.text("It's a Woof match! 🎉"), findsOneWidget);
    expect(find.text('Keep swiping'), findsOneWidget);
    await tester.tap(find.text('Send a message 💬'));
    await tester.pump();
    expect(find.text('Chat is coming soon 🐾'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/woof_match_screen_test.dart`
Expected: FAIL — `WoofMatchScreen` not found.

- [ ] **Step 3: Implement `woof_match_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/pet_profile.dart';

class WoofMatchScreen extends StatelessWidget {
  final PetProfile? pet;
  const WoofMatchScreen({super.key, this.pet});

  @override
  Widget build(BuildContext context) {
    final name = pet?.name ?? 'your match';
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFF8B45E), Color(0xFFF0871E)]),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Spacer(),
              Text("It's a Woof match! 🎉",
                textAlign: TextAlign.center,
                style: PgText.poppins(30, FontWeight.w800, color: Colors.white, ls: -0.5)),
              const SizedBox(height: 10),
              Text("You and $name's parent both said Woof. Say hi and plan a playdate!",
                textAlign: TextAlign.center,
                style: PgText.inter(15, FontWeight.w500, color: const Color(0xFFFFF5E8), height: 1.5)),
              const SizedBox(height: 38),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _circleAvatar(const PgImageSlot(size: 108, circle: true, emoji: '🙂')),
                Container(
                  width: 52, height: 52, alignment: Alignment.center,
                  margin: const EdgeInsets.symmetric(horizontal: -14),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Text('🐾', style: TextStyle(fontSize: 24))),
                _circleAvatar(const PgImageSlot(size: 108, circle: true, emoji: '🐶')),
              ]),
              const Spacer(),
              SizedBox(width: double.infinity, child: _darkButton(
                'Send a message 💬', () => showComingSoon(context, 'Chat'))),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: _outlineButton(
                'Keep swiping', () => context.pop())),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _circleAvatar(Widget child) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
        child: ClipOval(child: child),
      );

  Widget _darkButton(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFF211B17), borderRadius: BorderRadius.circular(16)),
          child: Text(label, style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white)),
        ),
      );

  Widget _outlineButton(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16), alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x88FFFFFF), width: 1.5),
            borderRadius: BorderRadius.circular(16)),
          child: Text(label, style: PgText.poppins(15, FontWeight.w700, color: Colors.white)),
        ),
      );
}
```

- [ ] **Step 4: Add the route constant + route**

In `lib/core/router/routes.dart`, add inside `class Routes`:
```dart
  static const nearby = '/nearby';
  static const woofMatch = '/woof-match';
```
In `lib/core/router/app_router.dart`: add `import '../../features/discovery/woof_match_screen.dart';`, add `Routes.woofMatch` and `Routes.nearby` to the `_protected` set, and add the top-level route (alongside the other `GoRoute`s, before the `StatefulShellRoute`):
```dart
      GoRoute(path: Routes.woofMatch, builder: (_, state) => WoofMatchScreen(pet: state.extra as PetProfile?)),
```
Add `import '../../data/models/pet_profile.dart';` to `app_router.dart` for the cast.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/woof_match_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze
git add lib/features/discovery/woof_match_screen.dart lib/core/router/routes.dart lib/core/router/app_router.dart test/features/woof_match_screen_test.dart
git commit -m "feat: add Woof match celebration screen + /woof-match route"
```

---

### Task 7: `DiscoverScreen` + Discover tab

**Files:**
- Create: `lib/features/discovery/discover_screen.dart`
- Modify: `lib/core/router/app_router.dart` (Discover branch → `DiscoverScreen`)
- Test: `test/features/discover_screen_test.dart`

**Interfaces:**
- Consumes: `discoverDeckProvider`, `swipeRepositoryProvider`, `authRepositoryProvider`, `currentUserProfileProvider`, `PgSwipeCard`, `Swipe`, `Routes`.
- Produces: `DiscoverScreen` (replaces `PlaceholderTab(title:'Discover')`).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/discover_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _pump(WidgetTester tester, {InMemorySwipeRepository? swipes}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1'); // uid_me@x.com
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('owner-b'))),
    swipeRepositoryProvider.overrideWithValue(swipes ?? InMemorySwipeRepository()),
  ], initialLocation: Routes.discover);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the first nearby pet', (tester) async {
    await _pump(tester);
    expect(find.text('Bruno'), findsOneWidget);
  });

  testWidgets('Woof (no reciprocity) advances to the next pet', (tester) async {
    final swipes = InMemorySwipeRepository();
    await _pump(tester, swipes: swipes);
    await tester.tap(find.byKey(const Key('discover-woof')));
    await tester.pumpAndSettle();
    expect(find.text('Bruno'), findsNothing);
    expect(find.text('Mochi'), findsOneWidget);
    final ids = await swipes.watchSwipedPetIds('uid_me@x.com').first;
    expect(ids.contains('p1'), isTrue); // Bruno recorded
  });

  testWidgets('Woof with a reciprocal woof shows the match screen', (tester) async {
    // owner-b already Woofed one of my pets.
    final swipes = InMemorySwipeRepository([
      const Swipe(fromUid: 'owner-b', petId: 'my-pet', ownerId: 'uid_me@x.com', direction: SwipeDirection.woof),
    ]);
    await _pump(tester, swipes: swipes);
    await tester.tap(find.byKey(const Key('discover-woof')));
    await tester.pumpAndSettle();
    expect(find.text("It's a Woof match! 🎉"), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/discover_screen_test.dart`
Expected: FAIL — `DiscoverScreen` not found.

- [ ] **Step 3: Implement `discover_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_swipe_card.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/swipe.dart';
import '../../data/repositories/providers.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  List<PetProfile>? _deck;
  int _index = 0;

  Future<void> _onWoof(PetProfile pet) async {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    final swipes = ref.read(swipeRepositoryProvider);
    await swipes.recordSwipe(Swipe(
        fromUid: me.uid, petId: pet.id, ownerId: pet.ownerId, direction: SwipeDirection.woof));
    final matched = await swipes.hasReciprocalWoof(otherUid: pet.ownerId, myUid: me.uid);
    if (!mounted) return;
    setState(() => _index++);
    if (matched) context.push(Routes.woofMatch, extra: pet);
  }

  void _onPass(PetProfile pet) {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    ref.read(swipeRepositoryProvider).recordSwipe(Swipe(
        fromUid: me.uid, petId: pet.id, ownerId: pet.ownerId, direction: SwipeDirection.pass));
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final profile = ref.watch(currentUserProfileProvider).value;
    final deckAsync = ref.watch(discoverDeckProvider);
    ref.listen(discoverDeckProvider, (prev, next) {
      if (_deck == null && next.hasValue) setState(() => _deck = next.value);
    });

    return Container(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Discover', style: PgText.poppins(23, FontWeight.w800, color: c.text, ls: -0.4)),
                Text('Pets near ${profile?.area.isNotEmpty == true ? profile!.area : 'you'}',
                    style: PgText.inter(12.5, FontWeight.w500, color: c.muted)),
              ])),
              GestureDetector(
                onTap: () => context.go(Routes.nearby),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(13)),
                  child: Text('⚙ Filters', style: PgText.inter(13, FontWeight.w600, color: c.text))),
              ),
            ]),
          ),
          Expanded(child: _body(c, deckAsync)),
        ]),
      ),
    );
  }

  Widget _body(PgColors c, AsyncValue<List<PetProfile>> deckAsync) {
    if (_deck == null) {
      if (deckAsync.hasError) {
        return Center(child: Text('Could not load pets.', style: PgText.body(context)));
      }
      return const Center(child: CircularProgressIndicator());
    }
    final deck = _deck!;
    if (_index >= deck.length) return _empty(c);
    final pet = deck[_index];
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Container(decoration: BoxDecoration(
                  color: c.surface, borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: c.border), boxShadow: c.shadowSm)))),
            Positioned.fill(
              child: PgSwipeCard(key: ValueKey(pet.id), pet: pet,
                onWoof: () => _onWoof(pet), onPass: () => _onPass(pet))),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _circleBtn(key: const Key('discover-pass'), c: c, size: 60,
            child: Icon(Icons.close, color: c.faint, size: 26), onTap: () => _onPass(pet)),
          const SizedBox(width: 22),
          _circleBtn(key: const Key('discover-woof'), c: c, size: 78, gradient: true,
            child: const Icon(Icons.pets, color: Colors.white, size: 32), onTap: () => _onWoof(pet)),
          const SizedBox(width: 22),
          _circleBtn(c: c, size: 60, child: const Text('⭐', style: TextStyle(fontSize: 24)),
            onTap: () => _onWoof(pet)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text('Swipe right to Woof · left to pass',
          style: PgText.inter(12.5, FontWeight.w500, color: c.faint))),
    ]);
  }

  Widget _circleBtn({Key? key, required PgColors c, required Widget child, required double size,
      required VoidCallback onTap, bool gradient = false}) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        width: size, height: size, alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: gradient ? null : c.surface,
          gradient: gradient
              ? const LinearGradient(colors: [Color(0xFFF8B45E), Color(0xFFF59E2E)])
              : null,
          border: gradient ? null : Border.all(color: c.border),
          boxShadow: c.shadowSm),
        child: child),
    );
  }

  Widget _empty(PgColors c) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🐾', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text("You're all caught up", style: PgText.poppins(18, FontWeight.w700, color: c.text)),
          const SizedBox(height: 4),
          Text('Check back soon for new pets nearby.',
            style: PgText.inter(13, FontWeight.w400, color: c.muted)),
        ]),
      );
}
```

- [ ] **Step 4: Point the Discover branch at `DiscoverScreen`**

In `lib/core/router/app_router.dart`: add `import '../../features/discovery/discover_screen.dart';` and change the Discover branch route from `const PlaceholderTab(title: 'Discover')` to `const DiscoverScreen()`.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/discover_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
flutter analyze
git add lib/features/discovery/discover_screen.dart lib/core/router/app_router.dart test/features/discover_screen_test.dart
git commit -m "feat: add Discover swipe deck (live pets, real Woof/Pass, reciprocal match)"
```

---

### Task 8: `NearbyMapScreen` + `/nearby` route + Home wiring

**Files:**
- Create: `lib/features/discovery/nearby_map_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/nearby` route)
- Modify: `lib/features/home/home_screen.dart` ("See map →" → `Routes.nearby`)
- Test: `test/features/nearby_map_screen_test.dart`

**Interfaces:**
- Consumes: `nearbyPetsProvider`, `swipeRepositoryProvider`, `authRepositoryProvider`, `showComingSoon`, `Routes`.
- Produces: `NearbyMapScreen`. `Routes.nearby` already added in Task 6.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/nearby_map_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Nearby shows a count and lists real nearby pets', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(InMemoryPetRepository(fixturePets('owner-b'))),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
    ], initialLocation: Routes.nearby);
    await tester.pumpAndSettle();
    expect(find.textContaining('pets nearby'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/nearby_map_screen_test.dart`
Expected: FAIL — `NearbyMapScreen` not found.

- [ ] **Step 3: Implement `nearby_map_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/swipe.dart';
import '../../data/repositories/providers.dart';

class NearbyMapScreen extends ConsumerWidget {
  const NearbyMapScreen({super.key});

  static const _filters = ['All pets', '🐶 Dogs', '🐱 Cats', '≤ 2 km', '✓ Vaccinated'];

  void _woof(WidgetRef ref, PetProfile pet) {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    ref.read(swipeRepositoryProvider).recordSwipe(Swipe(
        fromUid: me.uid, petId: pet.id, ownerId: pet.ownerId, direction: SwipeDirection.woof));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final pets = ref.watch(nearbyPetsProvider).value ?? const <PetProfile>[];
    return Scaffold(
      body: Stack(children: [
        // Faux map backdrop.
        Positioned.fill(child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFDFEEE6), Color(0xFFCFE6DA)])))),
        const Positioned(top: 150, left: 60, child: _Pin(emoji: '🐶', color: Color(0xFFF97316))),
        const Positioned(top: 120, right: 70, child: _Pin(emoji: '🐱', color: Color(0xFFEC4899))),
        const Positioned(top: 320, left: 80, child: _Pin(emoji: '🐕', color: Color(0xFFF0871E))),
        const Positioned(top: 360, right: 96, child: _Pin(emoji: '🐩', color: Color(0xFF6B8DE0))),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => context.go(Routes.discover),
                  child: Container(
                    width: 42, height: 42, alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(13)),
                    child: Icon(Icons.chevron_left, color: c.text))),
                const SizedBox(width: 12),
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(16), boxShadow: c.shadow),
                  child: Text('🔍  Search pets near you',
                    style: PgText.inter(14, FontWeight.w500, color: c.muted)))),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 9),
                itemBuilder: (_, i) => Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: i == 0 ? c.brand : c.surface,
                    border: i == 0 ? null : Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(20)),
                  child: Text(_filters[i],
                    style: PgText.inter(12.5, FontWeight.w600, color: i == 0 ? Colors.white : c.text))),
              ),
            ),
            const Spacer(),
            Container(
              decoration: BoxDecoration(
                color: c.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 30, offset: Offset(0, -10))]),
              padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(3)))),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${pets.length} pets nearby', style: PgText.poppins(16, FontWeight.w700, color: c.text)),
                  GestureDetector(onTap: () => context.go(Routes.discover),
                    child: Text('Swipe view →', style: PgText.inter(12.5, FontWeight.w700, color: c.brand))),
                ]),
                const SizedBox(height: 12),
                for (final p in pets.take(4)) ...[
                  GestureDetector(
                    onTap: () => showComingSoon(context, 'Pet profile'),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        const PgImageSlot(size: 50, circle: true),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, style: PgText.poppins(14.5, FontWeight.w700, color: c.text)),
                          Text('${p.breed} · ${p.area}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                        ])),
                        GestureDetector(
                          onTap: () => _woof(ref, p),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [c.brand, c.brand2]),
                              borderRadius: BorderRadius.circular(12)),
                            child: Text('Woof!', style: PgText.poppins(12.5, FontWeight.w700, color: Colors.white)))),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Pin extends StatelessWidget {
  final String emoji;
  final Color color;
  const _Pin({required this.emoji, required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785,
      child: Container(
        width: 44, height: 44, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(22), topRight: Radius.circular(22),
            bottomRight: Radius.circular(22), bottomLeft: Radius.circular(4))),
        child: Transform.rotate(angle: -0.785, child: Text(emoji, style: const TextStyle(fontSize: 18)))),
    );
  }
}
```

- [ ] **Step 4: Add the `/nearby` route + repoint Home's "See map →"**

In `lib/core/router/app_router.dart`: add `import '../../features/discovery/nearby_map_screen.dart';` and the route (near `/woof-match`):
```dart
      GoRoute(path: Routes.nearby, builder: (_, _) => const NearbyMapScreen()),
```
In `lib/features/home/home_screen.dart`, change **both** "See map →" `GestureDetector` `onTap`s from `context.go(Routes.discover)` to `context.go(Routes.nearby)` (there is one in the "Pets near you" row).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/nearby_map_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/discovery/nearby_map_screen.dart lib/core/router/app_router.dart lib/features/home/home_screen.dart test/features/nearby_map_screen_test.dart
git commit -m "feat: add Nearby faux-map screen with live pet list + wire Home See-map"
```
Expected: whole suite green, analyze clean.

---

### Task 9: Firestore rules + index for `swipes`; deploy

**Files:**
- Modify: `firestore.rules`
- Modify: `firestore.indexes.json`

**Interfaces:** none (infra).

- [ ] **Step 1: Add the `swipes` block to `firestore.rules`**

Inside `match /databases/{database}/documents { ... }`, after the `pets` block:
```
    match /swipes/{swipeId} {
      allow read: if request.auth != null
                  && (resource.data.fromUid == request.auth.uid
                      || resource.data.ownerId == request.auth.uid);
      allow create: if request.auth != null
                  && request.resource.data.fromUid == request.auth.uid;
      allow update, delete: if false;
    }
```

- [ ] **Step 2: Add the composite index to `firestore.indexes.json`**

Replace the `"indexes": []` array with:
```json
  "indexes": [
    {
      "collectionGroup": "swipes",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "fromUid", "order": "ASCENDING" },
        { "fieldPath": "ownerId", "order": "ASCENDING" },
        { "fieldPath": "direction", "order": "ASCENDING" }
      ]
    }
  ],
```
(Keep `"fieldOverrides": []`.)

- [ ] **Step 3: Deploy rules + indexes**

Run: `firebase deploy --only firestore:rules,firestore:indexes --project pet-aggregator-app`
Expected: `Deploy complete!` (index build may take a minute to finish in the console).

- [ ] **Step 4: Commit**

```bash
git add firestore.rules firestore.indexes.json
git commit -m "chore: add + deploy Firestore rules + index for swipes"
```

---

### Task 10: Emulator integration test + final verification

**Files:**
- Modify: `integration_test/firebase_repos_test.dart` (add a swipe/reciprocity test)

- [ ] **Step 1: Append a swipe test to `integration_test/firebase_repos_test.dart`**

Add `import 'package:pet_aggregator_app/data/models/swipe.dart';` and `import 'package:pet_aggregator_app/data/repositories/firebase/firestore_swipe_repository.dart';`, then add a second `testWidgets` inside `main()`:
```dart
  testWidgets('swipes persist + reciprocal woof detected (real Firestore emulators)',
      (tester) async {
    final auth = FirebaseAuthRepository();
    final swipes = FirestoreSwipeRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final me = await auth.signUp(email: 'sw_$stamp@x.com', password: 'secret1');
    await swipes.recordSwipe(Swipe(
        fromUid: me.uid, petId: 'pet_$stamp', ownerId: 'ownerX', direction: SwipeDirection.woof));
    final ids = await swipes.watchSwipedPetIds(me.uid).firstWhere((s) => s.contains('pet_$stamp'));
    expect(ids, contains('pet_$stamp'));

    // No reciprocity yet.
    expect(await swipes.hasReciprocalWoof(otherUid: 'ownerX', myUid: me.uid), isFalse);

    // ownerX (a second account) woofs one of my pets -> reciprocity.
    final other = await auth.signUp(email: 'ox_$stamp@x.com', password: 'secret1');
    await swipes.recordSwipe(Swipe(
        fromUid: other.uid, petId: 'mine_$stamp', ownerId: me.uid, direction: SwipeDirection.woof));
    expect(await swipes.hasReciprocalWoof(otherUid: other.uid, myUid: me.uid), isTrue);

    await auth.signOut();
  });
```
> Note: this reuses the emulator `setUpAll` already in the file (Auth + Firestore emulators, rules loaded). The reciprocity query needs the composite index; the Firestore emulator does not require indexes to be built, so it runs without the deploy.

- [ ] **Step 2: Start emulators + run the integration test**

```bash
firebase emulators:start --only auth,firestore --project pet-aggregator-app   # in one terminal
flutter test integration_test/firebase_repos_test.dart -d emulator-5554        # in another
```
Expected: both integration tests pass. Stop the emulators after.

- [ ] **Step 3: Full green gate**

```bash
flutter test
flutter analyze
flutter build apk --debug
```
Expected: all unit/widget tests pass, analyze clean, APK builds.

- [ ] **Step 4: Manual walkthrough on the emulator (real cloud)**

Run: `flutter run -d emulator-5554`. With two accounts (create a second that adds a pet), open **Discover**: the deck shows the other account's pet; drag right (Woof) or use the Woof button — the pet is recorded and doesn't reappear. When both accounts have Woofed each other, the **Woof match** screen appears. Open **Filters / See map** → Nearby shows the faux map + the live pet list. Confirm in the Firebase console that `swipes` docs are being written.

- [ ] **Step 5: Commit**

```bash
git add integration_test/firebase_repos_test.dart
git commit -m "test: verify swipes + reciprocal woof against Firestore emulators"
```

---

## Self-Review

**Spec coverage:**
- Swipe deck of live pets minus own/swiped → Tasks 1 (model), 3 (`discoverDeckProvider`), 7 (`DiscoverScreen`). ✓
- `PgSwipeCard` drag/rotate/overlays/threshold fling + spring-back → Task 5. ✓
- Real Woof/Pass persisted → `swipes` collection → Tasks 1–2 (model/repo), 7 (record on action). ✓
- Reciprocal-woof match + celebration → Tasks 1/2 (`hasReciprocalWoof`), 6 (`WoofMatchScreen`), 7 (navigate on match). ✓
- Nearby faux map + live list → Task 8. ✓
- `showComingSoon` for chat/pet-profile links → Task 4, used in 6 and 8. ✓
- Routing (`/nearby`, `/woof-match`, Discover branch, Home See-map) → Tasks 6, 7, 8. ✓
- Rules + composite index deployed → Task 9. ✓
- TDD fakes + emulator integration → every task's tests; Task 10. ✓
- Out-of-scope (photos, real maps/geo, chat, pet-profile, filters, matches collection) → none implemented. ✓

**Placeholder scan:** No "TBD/TODO". Every code step shows complete code. The ⭐ button intentionally calls `_onWoof` (documented in the spec as "= Woof for now").

**Type consistency:**
- `Swipe` fields (`fromUid, petId, ownerId, direction`) + `id` getter identical across Tasks 1 (model), 2 (Firestore), 7 (call sites), 10 (integration). ✓
- `SwipeRepository` methods (`recordSwipe`, `watchSwipedPetIds`, `hasReciprocalWoof({otherUid, myUid})`) match between interface (Task 1), fake (Task 1), Firestore impl (Task 2), and callers (Tasks 3, 7, 8, 10). ✓
- Providers (`swipeRepositoryProvider`, `swipedPetIdsProvider`, `discoverDeckProvider`) defined in Task 3, consumed in Tasks 7, 8. ✓
- `Routes.nearby` / `Routes.woofMatch` added in Task 6, used in Tasks 7 (push `woofMatch`, go `nearby`), 8 (route), and Home (Task 8). ✓
- `PgSwipeCard({pet, onWoof, onPass})` signature matches between Task 5 (def) and Task 7 (use). ✓
- `showComingSoon(context, label)` matches between Task 4 (def) and Tasks 6, 8 (use). ✓

