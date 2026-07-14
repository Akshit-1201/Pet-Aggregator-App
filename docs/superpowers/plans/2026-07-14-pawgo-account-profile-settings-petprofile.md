# Pawgo Slice 7a: Account — Profile + Settings + Pet-profile — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the account cluster — the Profile tab (real user data, own pet, real Pets/Bookings/Woofs stats, menu, sign-out), a Settings screen with a real persisted dark-mode toggle, and the read-only Pet-profile detail — on the existing Firebase backend.

**Architecture:** Feature-first Flutter on the existing repository seam. Dark mode gets a new `PreferencesRepository` seam (shared_preferences impl + fake) behind a `themeModeProvider` that `app.dart` watches. Three screens are thin `Consumer` composition reusing `users`/`pets`/`bookings`/`swipes` (plus small provider/repo additions for the real stats + owner lookup). No new Firestore collections or rules.

**Tech Stack:** Flutter 3.44+/Dart ^3.12.2, `cloud_firestore`, `flutter_riverpod`, `go_router`, `google_fonts`, **`shared_preferences` (new)**.

**Spec:** `docs/superpowers/specs/2026-07-14-pawgo-account-profile-settings-petprofile-design.md`.

## Global Constraints

- Flutter stable 3.44+, Dart SDK `^3.12.2`. Keep `android/gradle.properties` → `kotlin.incremental=false` (covers the new `shared_preferences_android` Kotlin plugin; `flutter clean` if a stale build errors).
- **Live Firestore, no mock data.** UI/tests depend only on repository interfaces; never import `cloud_firestore`/`firebase_auth`/`shared_preferences` outside `data/repositories/firebase/`, `data/repositories/local/`, `lib/main.dart`, and `integration_test/`.
- **Dark mode** persisted via `shared_preferences` behind a `PreferencesRepository`; `app.dart` reads `themeMode` from `themeModeProvider`. Only Dark mode is interactive in Settings; notification/privacy rows are `showComingSoon`.
- **All three Profile stats are real:** Pets = `myPetsProvider.length`, Bookings = `myBookingsProvider.length`, Woofs = `myWoofCountProvider`.
- **Pet-profile displays existing `PetProfile` fields only** (no model/create-pet change). Own pet → no woof button; another user's pet → "Send a Woof 👋" records a real woof.
- Riverpod 3.x: `AsyncValue.value` (not `valueOrNull`); `Override` from `package:flutter_riverpod/misc.dart` in tests; `Notifier`/`NotifierProvider` for `themeModeProvider`.
- `go_router` builders use `(_, _)`; routes reading `extra` use `(_, state)`. Screen tests use `pumpPgApp` (Consumer screens need the ProviderScope it sets up). Any plain `test()` touching `GoogleFonts` uses `testWidgets`.
- Every task ends green: `flutter analyze` clean + its tests pass, then commit.

---

### Task 1: `shared_preferences` + `PreferencesRepository` seam

**Files:**
- Modify: `pubspec.yaml` (add `shared_preferences`)
- Create: `lib/data/repositories/preferences_repository.dart`
- Create: `lib/data/repositories/local/shared_preferences_repository.dart`
- Modify: `test/support/fakes.dart` (add `InMemoryPreferencesRepository`)
- Test: `test/data/preferences_repository_test.dart`

**Interfaces:**
- Produces: `abstract interface class PreferencesRepository { ThemeMode get themeMode; Future<void> setThemeMode(ThemeMode mode); }`; `SharedPreferencesRepository(SharedPreferences)`; `InMemoryPreferencesRepository([ThemeMode])`.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add shared_preferences`
Expected: `pubspec.yaml` gains `shared_preferences: ^2.x` and `flutter pub get` succeeds.

- [ ] **Step 2: Write the failing test**

```dart
// test/data/preferences_repository_test.dart
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet_aggregator_app/data/repositories/local/shared_preferences_repository.dart';
import '../support/fakes.dart';

void main() {
  testWidgets('SharedPreferencesRepository persists theme mode across instances', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = SharedPreferencesRepository(await SharedPreferences.getInstance());
    expect(repo.themeMode, ThemeMode.system); // default when unset
    await repo.setThemeMode(ThemeMode.dark);
    expect(repo.themeMode, ThemeMode.dark);
    final repo2 = SharedPreferencesRepository(await SharedPreferences.getInstance());
    expect(repo2.themeMode, ThemeMode.dark); // read back from the store
  });

  test('InMemoryPreferencesRepository round-trips the mode', () async {
    final repo = InMemoryPreferencesRepository();
    expect(repo.themeMode, ThemeMode.system);
    await repo.setThemeMode(ThemeMode.light);
    expect(repo.themeMode, ThemeMode.light);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/data/preferences_repository_test.dart`
Expected: FAIL — `SharedPreferencesRepository`/`InMemoryPreferencesRepository` not found.

- [ ] **Step 4: Create `lib/data/repositories/preferences_repository.dart`**

```dart
import 'package:flutter/material.dart' show ThemeMode;

abstract interface class PreferencesRepository {
  ThemeMode get themeMode;
  Future<void> setThemeMode(ThemeMode mode);
}
```

- [ ] **Step 5: Create `lib/data/repositories/local/shared_preferences_repository.dart`**

```dart
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../preferences_repository.dart';

class SharedPreferencesRepository implements PreferencesRepository {
  final SharedPreferences _prefs;
  SharedPreferencesRepository(this._prefs);

  static const _key = 'themeMode';

  @override
  ThemeMode get themeMode {
    switch (_prefs.getString(_key)) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) => _prefs.setString(_key, mode.name);
}
```

- [ ] **Step 6: Add `InMemoryPreferencesRepository` to `test/support/fakes.dart`**

Add the import `import 'package:flutter/material.dart' show ThemeMode;` (if not present) and `import 'package:pet_aggregator_app/data/repositories/preferences_repository.dart';`, then append:

```dart
class InMemoryPreferencesRepository implements PreferencesRepository {
  ThemeMode _mode;
  InMemoryPreferencesRepository([this._mode = ThemeMode.system]);

  @override
  ThemeMode get themeMode => _mode;

  @override
  Future<void> setThemeMode(ThemeMode mode) async => _mode = mode;
}
```

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/data/preferences_repository_test.dart`
Expected: PASS.

- [ ] **Step 8: Analyze + commit**

```bash
flutter analyze lib/data test/support/fakes.dart test/data/preferences_repository_test.dart
git add pubspec.yaml pubspec.lock lib/data/repositories/preferences_repository.dart lib/data/repositories/local/shared_preferences_repository.dart test/support/fakes.dart test/data/preferences_repository_test.dart
git commit -m "feat: add shared_preferences + PreferencesRepository seam (theme mode)"
```

---

### Task 2: `themeModeProvider` + `app.dart`/`main.dart` wiring

**Files:**
- Modify: `lib/data/repositories/providers.dart` (add `preferencesRepositoryProvider`, `themeModeProvider`)
- Modify: `lib/app.dart` (watch `themeModeProvider`)
- Modify: `lib/main.dart` (init prefs + override the provider)
- Test: `test/data/theme_mode_provider_test.dart`

**Interfaces:**
- Consumes: `PreferencesRepository` (Task 1).
- Produces: `preferencesRepositoryProvider` → `Provider<PreferencesRepository>` (throws unless overridden); `themeModeProvider` → `NotifierProvider<ThemeModeNotifier, ThemeMode>` with `setThemeMode(ThemeMode)` + `toggleDark(bool)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/theme_mode_provider_test.dart
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('themeModeProvider loads the saved mode and persists changes', () async {
    final prefs = InMemoryPreferencesRepository(ThemeMode.dark);
    final container = ProviderContainer(overrides: [
      preferencesRepositoryProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.dark); // loaded from prefs
    await container.read(themeModeProvider.notifier).toggleDark(false);
    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(prefs.themeMode, ThemeMode.light); // persisted through the repo
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/theme_mode_provider_test.dart`
Expected: FAIL — providers not defined.

- [ ] **Step 3: Append to `lib/data/repositories/providers.dart`**

Add imports: `import 'package:flutter/material.dart' show ThemeMode;`, `import 'preferences_repository.dart';`. Then append:

```dart
final preferencesRepositoryProvider = Provider<PreferencesRepository>(
    (ref) => throw UnimplementedError('preferencesRepositoryProvider must be overridden in main()'));

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(preferencesRepositoryProvider).themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await ref.read(preferencesRepositoryProvider).setThemeMode(mode);
  }

  Future<void> toggleDark(bool on) => setThemeMode(on ? ThemeMode.dark : ThemeMode.light);
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/theme_mode_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire `lib/app.dart`**

Change `themeMode: ThemeMode.light,` to:
```dart
      themeMode: ref.watch(themeModeProvider),
```

- [ ] **Step 6: Wire `lib/main.dart`**

Replace the body of `main()` so it initializes prefs and overrides the provider:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'app.dart';
import 'data/repositories/providers.dart';
import 'data/repositories/local/shared_preferences_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [preferencesRepositoryProvider.overrideWithValue(SharedPreferencesRepository(prefs))],
    child: const PawgoApp(),
  ));
}
```

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add lib/data/repositories/providers.dart lib/app.dart lib/main.dart test/data/theme_mode_provider_test.dart
git commit -m "feat: add themeModeProvider; wire app.dart + main.dart for persisted dark mode"
```

---

### Task 3: `SwipeRepository.watchMyWoofCount`

**Files:**
- Modify: `lib/data/repositories/swipe_repository.dart`
- Modify: `lib/data/repositories/firebase/firestore_swipe_repository.dart`
- Modify: `test/support/fakes.dart` (`InMemorySwipeRepository`)
- Test: `test/data/swipe_woof_count_test.dart`

**Interfaces:**
- Produces: `SwipeRepository.watchMyWoofCount(String uid) → Stream<int>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/swipe_woof_count_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import '../support/fakes.dart';

void main() {
  test('watchMyWoofCount counts only my woof swipes', () async {
    final repo = InMemorySwipeRepository();
    expect(await repo.watchMyWoofCount('me').first, 0);
    await repo.recordSwipe(const Swipe(fromUid: 'me', petId: 'p1', ownerId: 'o1', direction: SwipeDirection.woof));
    await repo.recordSwipe(const Swipe(fromUid: 'me', petId: 'p2', ownerId: 'o2', direction: SwipeDirection.pass));
    await repo.recordSwipe(const Swipe(fromUid: 'other', petId: 'p3', ownerId: 'o3', direction: SwipeDirection.woof));
    expect(await repo.watchMyWoofCount('me').first, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/swipe_woof_count_test.dart`
Expected: FAIL — `watchMyWoofCount` not defined.

- [ ] **Step 3: Add the method to the interface**

In `lib/data/repositories/swipe_repository.dart`, add inside `abstract interface class SwipeRepository`:
```dart
  Stream<int> watchMyWoofCount(String uid);
```

- [ ] **Step 4: Implement in `firestore_swipe_repository.dart`**

Add this method (single-field `where` → no new composite index; count `woof` client-side):
```dart
  @override
  Stream<int> watchMyWoofCount(String uid) => _col
      .where('fromUid', isEqualTo: uid)
      .snapshots()
      .map((snap) => snap.docs.where((d) => d.data()['direction'] == 'woof').length);
```

- [ ] **Step 5: Implement in `InMemorySwipeRepository` (`test/support/fakes.dart`)**

Add this method (uses the existing `_swipes` list + `_controller`):
```dart
  @override
  Stream<int> watchMyWoofCount(String uid) async* {
    int count() => _swipes.where((s) => s.fromUid == uid && s.direction == SwipeDirection.woof).length;
    yield count();
    yield* _controller.stream.map((_) => count());
  }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/data/swipe_woof_count_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze lib/data test/support/fakes.dart
git add lib/data/repositories/swipe_repository.dart lib/data/repositories/firebase/firestore_swipe_repository.dart test/support/fakes.dart test/data/swipe_woof_count_test.dart
git commit -m "feat: add SwipeRepository.watchMyWoofCount"
```

---

### Task 4: Providers — `myWoofCountProvider`, `myBookingsProvider`, `userByIdProvider`

**Files:**
- Modify: `lib/data/repositories/providers.dart`
- Test: `test/data/account_providers_test.dart`

**Interfaces:**
- Produces: `myWoofCountProvider` → `StreamProvider<int>`; `myBookingsProvider` → `StreamProvider<List<Booking>>`; `userByIdProvider` → `StreamProvider.family<UserProfile?, String>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/account_providers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';

void main() {
  test('myWoofCountProvider streams my woofs; userByIdProvider streams a user', () async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final uid = auth.currentUser!.uid;
    final swipes = InMemorySwipeRepository();
    await swipes.recordSwipe(Swipe(fromUid: uid, petId: 'p1', ownerId: 'o1', direction: SwipeDirection.woof));
    final users = InMemoryUserRepository();
    await users.createUser(const UserProfile(uid: 'o1', name: 'Owner One', email: 'o@x.com', area: 'Khar', role: Role.petParent));

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      swipeRepositoryProvider.overrideWithValue(swipes),
      userRepositoryProvider.overrideWithValue(users),
    ]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    container.listen(myWoofCountProvider, (_, _) {}, fireImmediately: true);
    container.listen(userByIdProvider('o1'), (_, _) {}, fireImmediately: true);
    await pumpEventQueue();
    expect(container.read(myWoofCountProvider).value, 1);
    expect(container.read(userByIdProvider('o1')).value?.name, 'Owner One');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/account_providers_test.dart`
Expected: FAIL — providers not defined.

- [ ] **Step 3: Append to `lib/data/repositories/providers.dart`**

Add `import '../models/booking.dart';` (if not present), then append:
```dart
final myWoofCountProvider = StreamProvider<int>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(0);
  return ref.watch(swipeRepositoryProvider).watchMyWoofCount(user.uid);
});

final myBookingsProvider = StreamProvider<List<Booking>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(bookingRepositoryProvider).watchMyBookings(user.uid);
});

final userByIdProvider = StreamProvider.family<UserProfile?, String>(
    (ref, uid) => ref.watch(userRepositoryProvider).watchUser(uid));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/account_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
flutter analyze lib/data
git add lib/data/repositories/providers.dart test/data/account_providers_test.dart
git commit -m "feat: add myWoofCountProvider, myBookingsProvider, userByIdProvider"
```

---

### Task 5: `PetProfileDetailScreen` + route constants + `/pet-profile` route

**Files:**
- Create: `lib/features/pets/pet_profile_detail_screen.dart`
- Modify: `lib/core/router/routes.dart` (add `settings`, `petProfile`)
- Modify: `lib/core/router/app_router.dart` (import + protect both + add `/pet-profile` route)
- Test: `test/features/pet_profile_detail_screen_test.dart`

**Interfaces:**
- Consumes: `PetProfile`, `Species`, `Swipe`/`SwipeDirection`, `authStateProvider`, `authRepositoryProvider`, `swipeRepositoryProvider`, `userByIdProvider`, `PgImageSlot`, `Routes`.
- Produces: `PetProfileDetailScreen({PetProfile? pet})`; `Routes.settings == '/settings'`, `Routes.petProfile == '/pet-profile'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/pet_profile_detail_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('another user\'s pet renders fields + Send a Woof records a woof', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final users = InMemoryUserRepository();
    await users.createUser(const UserProfile(uid: 'owner1', name: 'Karan Mehta',
        email: 'k@x.com', area: 'Bandra West', role: Role.petParent));
    final swipes = InMemorySwipeRepository();
    const pet = PetProfile(id: 'pet1', ownerId: 'owner1', name: 'Bruno', breed: 'Labrador',
        ageLabel: '2 yrs', sex: 'male', area: 'Bandra West', species: Species.dog,
        vaccinated: true, accentColor: Color(0xFFF0871E));

    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users),
      swipeRepositoryProvider.overrideWithValue(swipes),
    ], initialLocation: Routes.petProfile, extra: pet);
    await tester.pumpAndSettle();

    expect(find.text('Bruno'), findsWidgets);
    expect(find.textContaining('Labrador'), findsOneWidget);
    expect(find.textContaining('Vaccinated'), findsWidgets);
    expect(find.textContaining('Karan Mehta'), findsOneWidget); // owner card

    await tester.tap(find.text('Send a Woof 👋'));
    await tester.pumpAndSettle();
    expect(await swipes.watchSwipedPetIds(auth.currentUser!.uid).first, contains('pet1'));
  });

  testWidgets('own pet hides the woof button', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pet = PetProfile(id: 'pet1', ownerId: auth.currentUser!.uid, name: 'Bruno',
        breed: 'Labrador', ageLabel: '2 yrs', sex: 'male', area: 'Bandra West',
        species: Species.dog, vaccinated: true, accentColor: const Color(0xFFF0871E));
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
    ], initialLocation: Routes.petProfile, extra: pet);
    await tester.pumpAndSettle();
    expect(find.text('Send a Woof 👋'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/pet_profile_detail_screen_test.dart`
Expected: FAIL — `PetProfileDetailScreen` / routes not found.

- [ ] **Step 3: Add the route constants**

In `lib/core/router/routes.dart`, add inside `class Routes` (after `postLive`):
```dart
  static const settings = '/settings';
  static const petProfile = '/pet-profile';
```

- [ ] **Step 4: Implement `lib/features/pets/pet_profile_detail_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/swipe.dart';
import '../../data/repositories/providers.dart';

class PetProfileDetailScreen extends ConsumerWidget {
  final PetProfile? pet;
  const PetProfileDetailScreen({super.key, this.pet});

  static String _speciesEmoji(Species s) => s == Species.cat ? '🐈' : (s == Species.dog ? '🐕' : '🐾');
  static String _speciesLabel(Species s) => s == Species.cat ? 'Cat' : (s == Species.dog ? 'Dog' : 'Other');
  static String _cap(String s) => s.isEmpty ? '—' : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final p = pet;
    if (p == null) {
      return Scaffold(backgroundColor: c.bg, appBar: AppBar(backgroundColor: c.bg, elevation: 0),
        body: Center(child: Text('Pet not found', style: PgText.body(context))));
    }
    final me = ref.watch(authStateProvider).value;
    final isMine = me != null && me.uid == p.ownerId;
    final owner = ref.watch(userByIdProvider(p.ownerId)).value;
    final sexSymbol = p.sex.toLowerCase() == 'female' ? '♀' : '♂';

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        Expanded(child: ListView(padding: EdgeInsets.zero, children: [
          Stack(children: [
            Container(height: 280, width: double.infinity, color: c.surface2, alignment: Alignment.center,
              child: Text(_speciesEmoji(p.species), style: const TextStyle(fontSize: 64))),
            Positioned(top: 0, left: 0, child: SafeArea(child: Padding(
              padding: const EdgeInsets.all(14),
              child: GestureDetector(
                onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                child: Container(width: 40, height: 40, alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), boxShadow: c.shadowSm),
                  child: Icon(Icons.chevron_left, color: c.text)))))),
          ]),
          Transform.translate(offset: const Offset(0, -26), child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.shadow),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: PgText.poppins(22, FontWeight.w800, color: c.text))),
                        const SizedBox(width: 7),
                        Text(sexSymbol, style: PgText.poppins(18, FontWeight.w700, color: c.muted)),
                      ]),
                      const SizedBox(height: 3),
                      Text('${p.breed} · ${p.ageLabel} · ${p.area}',
                        style: PgText.inter(13, FontWeight.w400, color: c.muted)),
                    ])),
                    if (p.vaccinated)
                      Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(20)),
                        child: Text('✓ Vaccinated', style: PgText.inter(12, FontWeight.w700, color: c.brand))),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _trait(c, _speciesEmoji(p.species), _speciesLabel(p.species))),
                    const SizedBox(width: 9),
                    Expanded(child: _trait(c, sexSymbol, _cap(p.sex))),
                    const SizedBox(width: 9),
                    Expanded(child: _trait(c, p.vaccinated ? '💉' : '❔', p.vaccinated ? 'Vaccinated' : 'Not recorded')),
                  ]),
                ]),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const PgImageSlot(size: 46, circle: true, emoji: '🙂'),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Pet parent', style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
                    Text(owner?.name ?? '—', style: PgText.poppins(14, FontWeight.w700, color: c.text)),
                  ])),
                ]),
              ),
            ]))),
        ])),
        if (!isMine)
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: EdgeInsets.fromLTRB(22, 13, 22, 18 + MediaQuery.of(context).padding.bottom),
            child: GestureDetector(
              onTap: () async {
                final meUid = ref.read(authRepositoryProvider).currentUser?.uid;
                if (meUid == null) return;
                await ref.read(swipeRepositoryProvider).recordSwipe(Swipe(
                    fromUid: meUid, petId: p.id, ownerId: p.ownerId, direction: SwipeDirection.woof));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                      content: Text('You woofed ${p.name}! 🐾'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2)));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [c.brand, c.brand2]),
                  borderRadius: BorderRadius.circular(16)),
                child: Text('Send a Woof 👋', style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white)))),
          ),
      ]),
    );
  }

  Widget _trait(PgColors c, String emoji, String label) => Container(
        padding: const EdgeInsets.all(11), alignment: Alignment.center,
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(13)),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: PgText.inter(12, FontWeight.w700, color: c.text)),
        ]),
      );
}
```

- [ ] **Step 5: Wire the route + protect both constants in `app_router.dart`**

Add `import '../../features/pets/pet_profile_detail_screen.dart';` (near the other `features/pets` import); add `Routes.settings, Routes.petProfile` to the `_protected` set; add this route (after the `Routes.postLive` route):
```dart
      GoRoute(path: Routes.petProfile, builder: (_, state) => PetProfileDetailScreen(pet: state.extra as PetProfile?)),
```
(`PetProfile` is already imported in `app_router.dart`.)

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/pet_profile_detail_screen_test.dart`
Expected: PASS (both tests).

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add lib/features/pets/pet_profile_detail_screen.dart lib/core/router/routes.dart lib/core/router/app_router.dart test/features/pet_profile_detail_screen_test.dart
git commit -m "feat: add Pet-profile detail screen + /pet-profile route"
```

---

### Task 6: `SettingsScreen` + `/settings` route

**Files:**
- Create: `lib/features/profile/settings_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/settings` route)
- Test: `test/features/settings_screen_test.dart`

**Interfaces:**
- Consumes: `themeModeProvider`, `preferencesRepositoryProvider`, `PgAppBar`, `PgToggle`, `showComingSoon`.
- Produces: `SettingsScreen`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/settings_screen_test.dart
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/core/widgets/pg_toggle.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('dark-mode toggle flips theme mode and persists', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final prefs = InMemoryPreferencesRepository(); // system
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      preferencesRepositoryProvider.overrideWithValue(prefs),
    ], initialLocation: Routes.settings);
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsOneWidget);
    await tester.tap(find.byType(PgToggle));
    await tester.pumpAndSettle();
    expect(prefs.themeMode, ThemeMode.dark); // persisted via the notifier
  });

  testWidgets('a coming-soon settings row shows the snackbar', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      preferencesRepositoryProvider.overrideWithValue(InMemoryPreferencesRepository()),
    ], initialLocation: Routes.settings);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Booking updates'));
    await tester.pump();
    expect(find.textContaining('coming soon'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings_screen_test.dart`
Expected: FAIL — `SettingsScreen` not found.

- [ ] **Step 3: Implement `lib/features/profile/settings_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../core/widgets/pg_toggle.dart';
import '../../data/repositories/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        PgAppBar(title: 'Settings', onBack: () => context.pop()),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(22, 8, 22, 30), children: [
          _label(context, 'APPEARANCE'),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Text('🌙', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dark mode', style: PgText.inter(14, FontWeight.w600, color: c.text)),
                Text('Easier on the eyes at night', style: PgText.inter(12, FontWeight.w400, color: c.muted)),
              ])),
              PgToggle(value: isDark, onChanged: (v) => ref.read(themeModeProvider.notifier).toggleDark(v)),
            ]),
          ),
          const SizedBox(height: 18),
          _label(context, 'NOTIFICATIONS'),
          _comingRow(context, c, 'New Woofs & matches'),
          _comingRow(context, c, 'Booking updates'),
          _comingRow(context, c, 'Nearby pet alerts'),
          const SizedBox(height: 18),
          _label(context, 'PRIVACY & ACCOUNT'),
          _comingRow(context, c, 'Location sharing'),
          _comingRow(context, c, 'Chat safety'),
          _staticRow(c, 'About Pawgo', 'v1.0.0'),
        ])),
      ])),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 9, top: 2),
        child: Text(text, style: PgText.inter(12, FontWeight.w700, color: context.pg.faint)),
      );

  Widget _comingRow(BuildContext context, PgColors c, String title) => GestureDetector(
        onTap: () => showComingSoon(context, title),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(child: Text(title, style: PgText.inter(14, FontWeight.w600, color: c.text))),
            Icon(Icons.chevron_right, color: c.faint, size: 20),
          ]),
        ),
      );

  Widget _staticRow(PgColors c, String title, String trailing) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(child: Text(title, style: PgText.inter(14, FontWeight.w600, color: c.text))),
          Text(trailing, style: PgText.inter(12, FontWeight.w400, color: c.faint)),
        ]),
      );
}
```

- [ ] **Step 4: Add the `/settings` route**

In `lib/core/router/app_router.dart`: add `import '../../features/profile/settings_screen.dart';` and this route (next to `Routes.petProfile`):
```dart
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/settings_screen_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze
git add lib/features/profile/settings_screen.dart lib/core/router/app_router.dart test/features/settings_screen_test.dart
git commit -m "feat: add Settings screen (real dark-mode toggle) + /settings route"
```

---

### Task 7: `ProfileScreen` + Profile tab

**Files:**
- Create: `lib/features/profile/profile_screen.dart`
- Modify: `lib/core/router/app_router.dart` (Profile branch → `ProfileScreen`)
- Test: `test/features/profile_screen_test.dart`

**Interfaces:**
- Consumes: `currentUserProfileProvider`, `myPetsProvider`, `myBookingsProvider`, `myWoofCountProvider`, `authRepositoryProvider`, `PgImageSlot`, `showComingSoon`, `Routes`.
- Produces: `ProfileScreen` (replaces `PlaceholderTab('Profile')`).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/profile_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _pumpProfile(WidgetTester tester, FakeAuthRepository auth) async {
  final uid = auth.currentUser!.uid;
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(uid: uid, name: 'Radhika Nair', email: 'me@x.com',
      area: 'Bandra West', role: Role.petParent));
  final pets = InMemoryPetRepository([PetProfile(id: 'p1', ownerId: uid, name: 'Bruno',
      breed: 'Labrador', ageLabel: '2 yrs', sex: 'male', area: 'Bandra West',
      species: Species.dog, vaccinated: true, accentColor: PetProfile.accentFor('Bruno'))]);
  final swipes = InMemorySwipeRepository();
  await swipes.recordSwipe(Swipe(fromUid: uid, petId: 'x', ownerId: 'o', direction: SwipeDirection.woof));
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    petRepositoryProvider.overrideWithValue(pets),
    swipeRepositoryProvider.overrideWithValue(swipes),
    bookingRepositoryProvider.overrideWithValue(InMemoryBookingRepository()),
  ], initialLocation: Routes.profile);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders name/role/area, own pet + real stats; Sign out signs out', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await _pumpProfile(tester, auth);
    expect(find.text('Radhika Nair'), findsOneWidget);
    expect(find.textContaining('Pet Parent · Bandra West'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Woofs'), findsOneWidget); // stat label
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.currentUser, isNull);
  });

  testWidgets('tapping the own-pet card opens Pet-profile', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await _pumpProfile(tester, auth);
    await tester.tap(find.text('Bruno'));
    await tester.pumpAndSettle();
    expect(find.text('Pet parent'), findsOneWidget); // owner card is unique to Pet-profile
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/profile_screen_test.dart`
Expected: FAIL — `ProfileScreen` not found.

- [ ] **Step 3: Implement `lib/features/profile/profile_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/booking.dart';
import '../../data/models/pet_profile.dart';
import '../../data/repositories/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pg;
    final profile = ref.watch(currentUserProfileProvider).value;
    final pets = ref.watch(myPetsProvider).value ?? const <PetProfile>[];
    final bookings = ref.watch(myBookingsProvider).value ?? const <Booking>[];
    final woofs = ref.watch(myWoofCountProvider).value ?? 0;
    final name = profile?.name ?? '';
    final roleArea = profile == null ? '' : '${profile.role.label} · ${profile.area}';

    return Container(color: c.bg, child: SafeArea(bottom: false, child: ListView(padding: EdgeInsets.zero, children: [
      Container(height: 130, decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFF59E2E), Color(0xFFF0871E)]))),
      Transform.translate(offset: const Offset(0, -40), child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.shadow),
            child: Column(children: [
              Row(children: [
                const PgImageSlot(size: 72, circle: true, emoji: '🙂'),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.isEmpty ? 'Your profile' : name, style: PgText.poppins(19, FontWeight.w800, color: c.text)),
                  const SizedBox(height: 2),
                  Text(roleArea, style: PgText.inter(13, FontWeight.w400, color: c.muted)),
                ])),
              ]),
              const SizedBox(height: 16),
              Container(height: 1, color: c.border),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _stat(c, '${pets.length}', 'Pets')),
                Container(width: 1, height: 34, color: c.border),
                Expanded(child: _stat(c, '${bookings.length}', 'Bookings')),
                Container(width: 1, height: 34, color: c.border),
                Expanded(child: _stat(c, '$woofs', 'Woofs')),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          if (pets.isNotEmpty)
            GestureDetector(
              onTap: () => context.push(Routes.petProfile, extra: pets.first),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.brandSoft, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  const PgImageSlot(size: 52, circle: true, emoji: '🐾'),
                  const SizedBox(width: 13),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(pets.first.name, style: PgText.poppins(15, FontWeight.w700, color: c.text)),
                    Text('${pets.first.breed} · View profile →', style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                  ])),
                ]),
              ),
            )
          else
            GestureDetector(
              onTap: () => context.push(Routes.createPet),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  const Text('➕', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 13),
                  Expanded(child: Text('Add a pet', style: PgText.poppins(14.5, FontWeight.w700, color: c.text))),
                  Icon(Icons.chevron_right, color: c.faint),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          _menuGroup(context, c, const [
            ('🗓️', 'My bookings'), ('🏡', 'My homestays'),
            ('💳', 'Payments & wallet'), ('🎒', 'Become a pro or host'),
          ]),
          const SizedBox(height: 14),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              _row(c, '⚙️', 'Settings', () => context.push(Routes.settings), border: true),
              _row(c, '↩️', 'Sign out', () => ref.read(authRepositoryProvider).signOut(), danger: true),
            ]),
          ),
          const SizedBox(height: 30),
        ]),
      )),
    ])));
  }

  Widget _stat(PgColors c, String value, String label) => Column(children: [
        Text(value, style: PgText.poppins(18, FontWeight.w800, color: c.text)),
        Text(label, style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
      ]);

  Widget _menuGroup(BuildContext context, PgColors c, List<(String, String)> items) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          for (var i = 0; i < items.length; i++)
            _row(c, items[i].$1, items[i].$2, () => showComingSoon(context, items[i].$2), border: i != items.length - 1),
        ]),
      );

  Widget _row(PgColors c, String emoji, String title, VoidCallback onTap, {bool border = false, bool danger = false}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(border: border ? Border(bottom: BorderSide(color: c.border)) : null),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 13),
            Expanded(child: Text(title, style: PgText.inter(14, FontWeight.w600, color: danger ? c.heart : c.text))),
            if (!danger) Icon(Icons.chevron_right, color: c.faint, size: 20),
          ]),
        ),
      );
}
```

- [ ] **Step 4: Point the Profile branch at `ProfileScreen`**

In `lib/core/router/app_router.dart`: add `import '../../features/profile/profile_screen.dart';` and change the Profile branch route from `const PlaceholderTab(title: 'Profile')` to `const ProfileScreen()`.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/profile_screen_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Full suite + analyze + commit**

```bash
flutter test
flutter analyze
git add lib/features/profile/profile_screen.dart lib/core/router/app_router.dart test/features/profile_screen_test.dart
git commit -m "feat: add Profile tab (real user data, own pet, stats, sign-out)"
```
Expected: whole suite green, analyze clean.

---

### Task 8: Home pet rows → Pet-profile

**Files:**
- Modify: `lib/features/home/widgets/pet_row.dart` (add `onTap`)
- Modify: `lib/features/home/home_screen.dart` (pass `onTap`)
- Test: `test/features/home_pet_row_nav_test.dart`

**Interfaces:**
- Consumes: `PetRow` (existing), `Routes.petProfile`.
- Produces: `PetRow({..., VoidCallback? onTap})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/home_pet_row_nav_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

void main() {
  testWidgets('tapping a Home pet row opens Pet-profile', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pets = InMemoryPetRepository([PetProfile(id: 'p9', ownerId: 'other', name: 'Mochi',
        breed: 'Persian cat', ageLabel: '1 yr', sex: 'female', area: 'Khar', species: Species.cat,
        vaccinated: true, accentColor: PetProfile.accentFor('Mochi'))]);
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
      petRepositoryProvider.overrideWithValue(pets),
      swipeRepositoryProvider.overrideWithValue(InMemorySwipeRepository()),
    ], initialLocation: Routes.home);
    await tester.pumpAndSettle();
    expect(find.text('Mochi'), findsOneWidget);
    await tester.tap(find.text('Mochi'));
    await tester.pumpAndSettle();
    expect(find.text('Pet parent'), findsOneWidget); // Pet-profile owner card
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/home_pet_row_nav_test.dart`
Expected: FAIL — tapping does nothing (no navigation) / `onTap` not a param.

- [ ] **Step 3: Add `onTap` to `PetRow`**

In `lib/features/home/widgets/pet_row.dart`: add `final VoidCallback? onTap;` and the constructor param `this.onTap,`. Wrap the outer `Container(...)` in a `GestureDetector`:
```dart
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        // ... existing decoration + child unchanged ...
      ),
    );
```
(The inner "Woof!" `GestureDetector` still handles taps on the button; the row `onTap` handles the rest.)

- [ ] **Step 4: Pass `onTap` from `home_screen.dart`**

In `lib/features/home/home_screen.dart`, change `PetRow(pet: p, onWoof: () {})` to:
```dart
                            PetRow(pet: p, onWoof: () {},
                              onTap: () => context.push(Routes.petProfile, extra: p)),
```
(`Routes` and `context.push` are already available in `home_screen.dart`.)

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/home_pet_row_nav_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze
git add lib/features/home/widgets/pet_row.dart lib/features/home/home_screen.dart test/features/home_pet_row_nav_test.dart
git commit -m "feat: open Pet-profile from Home pet rows"
```

---

### Task 9: Emulator integration test + final verification

**Files:**
- Modify: `integration_test/firebase_repos_test.dart` (add a `watchMyWoofCount` check)

- [ ] **Step 1: Append a woof-count test to `integration_test/firebase_repos_test.dart`**

Inside `main()` (the `swipe`/`Swipe` imports already exist), add:
```dart
  testWidgets('watchMyWoofCount reflects a recorded woof (real Firestore emulators)', (tester) async {
    final auth = FirebaseAuthRepository();
    final swipes = FirestoreSwipeRepository();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final me = await auth.signUp(email: 'woofc_$stamp@x.com', password: 'secret1');
    expect(await swipes.watchMyWoofCount(me.uid).first, 0);
    await swipes.recordSwipe(Swipe(fromUid: me.uid, petId: 'pet_$stamp', ownerId: 'owner_$stamp',
        direction: SwipeDirection.woof));
    final count = await swipes.watchMyWoofCount(me.uid).firstWhere((n) => n >= 1);
    expect(count, 1);
    await auth.signOut();
  });
```

- [ ] **Step 2: Start emulators + run the integration test**

```bash
firebase emulators:start --only auth,firestore --project pet-aggregator-app   # one terminal
flutter test integration_test/firebase_repos_test.dart -d emulator-5554        # another
```
Expected: all integration tests pass. (Reuse a running emulator if one is up on 8080/9099.) Stop the emulators after if you started them.

- [ ] **Step 3: Full green gate**

```bash
flutter test
flutter analyze
flutter build apk --debug
```
Expected: unit/widget tests pass, analyze clean, APK builds (picks up the new `shared_preferences` native plugin; run `flutter clean` first if a stale Kotlin build errors).

- [ ] **Step 4: Manual walkthrough (real device)**

Run: `flutter run -d emulator-5554`. Open the **Profile** tab → real name/role/area + own pet + Pets/Bookings/Woofs counts. Open **Settings** → toggle **Dark mode** (whole app switches) → fully close and relaunch the app → it comes back in dark mode (persistence). Tap your pet → **Pet-profile** renders; from **Home**, tap a nearby pet → its Pet-profile → "Send a Woof 👋" shows the confirmation. **Sign out** → returns to Welcome.

- [ ] **Step 5: Commit**

```bash
git add integration_test/firebase_repos_test.dart
git commit -m "test: verify watchMyWoofCount against Firestore emulators"
```

---

## Self-Review

**Spec coverage:**
- `shared_preferences` + `PreferencesRepository` seam + fake → Task 1. ✓
- `themeModeProvider` + `app.dart`/`main.dart` wiring → Task 2. ✓
- `SwipeRepository.watchMyWoofCount` → Task 3; `myWoofCountProvider`/`myBookingsProvider`/`userByIdProvider` → Task 4. ✓
- Pet-profile detail (existing fields, trait tiles, owner card, own-pet-no-button, other-pet real woof) + route → Task 5. ✓
- Settings (real dark-mode toggle, coming-soon rows) + route → Task 6. ✓
- Profile tab (real data, own pet / add-a-pet, real stats, menu coming-soon, Settings, real sign-out) → Task 7. ✓
- Rewire pet-profile entry points (Profile own-pet card in Task 7; Home pet rows in Task 8). ✓
- No Firestore rules/collections change (reuses existing) → confirmed; emulator integration for `watchMyWoofCount` → Task 9. ✓
- Out-of-scope (photos/avatar, FCM toggles, list screens, become-pro flow, reviews rating, profile edit) → none implemented. ✓

**Placeholder scan:** No "TBD/TODO". Every code step is complete. Notification/privacy rows and the menu group intentionally call `showComingSoon`. `preferencesRepositoryProvider` intentionally throws unless overridden (main provides it; tests override it).

**Type consistency:**
- `PreferencesRepository` (`themeMode` getter, `setThemeMode`) identical across Task 1 (interface/impl/fake), Task 2 (notifier). ✓
- `themeModeProvider` (`NotifierProvider<ThemeModeNotifier, ThemeMode>`, `.notifier.toggleDark/setThemeMode`) defined Task 2, consumed Task 6 + `app.dart`. ✓
- `SwipeRepository.watchMyWoofCount(String)→Stream<int>` matches interface (Task 3), Firestore impl (Task 3), fake (Task 3), `myWoofCountProvider` (Task 4), integration (Task 9). ✓
- `myWoofCountProvider`/`myBookingsProvider`/`userByIdProvider` defined Task 4, consumed Tasks 5 (`userByIdProvider`), 7 (`myWoofCountProvider`, `myBookingsProvider`). ✓
- `Routes.settings`/`Routes.petProfile` added Task 5, used Tasks 5 (route + `_protected`), 6 (`/settings` route), 7 (`push petProfile`, `push settings`), 8 (`push petProfile`). ✓
- `PetProfileDetailScreen({PetProfile? pet})` matches the router cast `state.extra as PetProfile?` (Task 5). ✓
- `PetRow({pet, onWoof, onTap})` — `onTap` added Task 8, passed from `home_screen.dart` (Task 8); existing `onWoof` untouched. ✓
- `showComingSoon(context, label)` reused Tasks 6, 7. ✓
