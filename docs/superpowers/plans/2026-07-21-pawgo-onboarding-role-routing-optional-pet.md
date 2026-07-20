# Pawgo Slice 12: Onboarding role-routing + optional pet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route the last onboarding step by the role chosen at signup (pet parent → Create Pet, pro → Pro setup, host → Host setup), make the pet + listing steps skippable, require a real pet name before writing one, and give the two booking flows an "add a pet" step instead of a silent dead button.

**Architecture:** Pure UI/flow — no new collections, models, Firestore rules, or packages. A tiny `OnboardingArg` value type rides go_router `extra` so the three destination screens know they're in signup (show a skip, exit to Home). `LocationScreen` reads the profile's role and routes. Two setup screens gain a context-aware exit; Create Pet gains name validation + skip; two booking screens gain an empty-state CTA.

**Tech Stack:** Flutter/Dart ^3.12.2, `flutter_riverpod` 3.x, `go_router`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-07-21-pawgo-onboarding-role-routing-optional-pet-design.md`.

## Global Constraints

- Keep `android/gradle.properties` → `kotlin.incremental=false`.
- No new Firestore collections, model fields, rules, or packages; no change to listing/pet/booking backend or form fields.
- **`OnboardingArg`** carried via go_router `extra`; screens reached by other routes get `extra == null` → treated as `fromOnboarding: false`.
- **Onboarding always terminates at `Routes.home`.** Every terminal action in the signup chain (Create Pet Finish/Skip, Pro setup Save/Set-up-later, Host setup Save/Set-up-later) lands on Home when `fromOnboarding`.
- **Post-onboarding entries unchanged**: Pro setup Save/back → `Routes.services`; Host setup Save → `Routes.homestay`, back → `canPop() ? pop() : go(Routes.homestay)`.
- Exact copy: Create Pet skip `Skip for now`; setup skip `Set up later`; empty name error `Please enter your pet's name.`; booking empty-CTA button `Add a pet`.
- Riverpod 3.x `.value` idiom; async handlers guard `context.mounted` after `await`; widget tests use `pumpPgApp` + in-memory fakes.
- Every task ends green: `flutter analyze` clean + `flutter test` passes, then commit. Do NOT push.

---

### Task 1: `OnboardingArg` + role routing + router wiring

**Files:**
- Create: `lib/features/auth/onboarding_arg.dart`
- Modify: `lib/features/auth/location_screen.dart` (`_continue`)
- Modify: `lib/features/pets/create_pet_screen.dart` (constructor only — add inert `fromOnboarding` param)
- Modify: `lib/features/services/pro_setup_screen.dart` (constructor only)
- Modify: `lib/features/homestay/host_setup_screen.dart` (constructor only)
- Modify: `lib/core/router/app_router.dart` (3 route builders)
- Modify: `test/features/location_screen_test.dart`
- Test: `test/features/onboarding_routing_test.dart` (create)

**Interfaces:**
- Produces: `class OnboardingArg { final bool fromOnboarding; const OnboardingArg({this.fromOnboarding = false}); }`; each of `CreatePetScreen`/`ProSetupScreen`/`HostSetupScreen` gains `final bool fromOnboarding;` + `const …({super.key, this.fromOnboarding = false})`. The router reads `state.extra as OnboardingArg?` for `Routes.createPet`/`proSetup`/`hostSetup`. `LocationScreen` routes by `currentUserProfileProvider.value?.role`.

- [ ] **Step 1: Write the failing routing test**

```dart
// test/features/onboarding_routing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<void> _pumpLocationAs(WidgetTester tester, Role role) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(
      uid: auth.currentUser!.uid, name: 'Me', email: 'me@x.com', area: '', role: role));
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    petRepositoryProvider.overrideWithValue(InMemoryPetRepository()),
    proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
    homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
  ], initialLocation: Routes.location);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pet parent routes to Create Pet', (tester) async {
    await _pumpLocationAs(tester, Role.petParent);
    expect(find.text('Add your pet'), findsOneWidget);
  });
  testWidgets('service pro routes to Pro setup', (tester) async {
    await _pumpLocationAs(tester, Role.servicePro);
    expect(find.text('Offer your services'), findsOneWidget);
  });
  testWidgets('homestay host routes to Host setup', (tester) async {
    await _pumpLocationAs(tester, Role.homestayHost);
    expect(find.text('List your home'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (pro/host cases land on Create Pet today)

Run: `flutter test test/features/onboarding_routing_test.dart`

- [ ] **Step 3: Create `OnboardingArg`**

```dart
// lib/features/auth/onboarding_arg.dart
//
// Carried via go_router `extra` from LocationScreen to the three onboarding
// destination screens so they know they're in the signup funnel (show a skip,
// exit to Home). Screens reached by other routes get extra == null.
class OnboardingArg {
  final bool fromOnboarding;
  const OnboardingArg({this.fromOnboarding = false});
}
```

- [ ] **Step 4: Route by role in `LocationScreen._continue`**

In `lib/features/auth/location_screen.dart`, add imports:
```dart
import '../../data/models/role.dart';
import 'onboarding_arg.dart';
```
Replace the success line `if (mounted) context.go(Routes.createPet);` with:
```dart
    if (!mounted) return;
    final role = ref.read(currentUserProfileProvider).value?.role ?? Role.petParent;
    final target = switch (role) {
      Role.petParent => Routes.createPet,
      Role.servicePro => Routes.proSetup,
      Role.homestayHost => Routes.hostSetup,
    };
    context.go(target, extra: const OnboardingArg(fromOnboarding: true));
```

- [ ] **Step 5: Add the inert `fromOnboarding` param to the three screens**

- `lib/features/pets/create_pet_screen.dart`: change to
  ```dart
  class CreatePetScreen extends ConsumerStatefulWidget {
    final bool fromOnboarding;
    const CreatePetScreen({super.key, this.fromOnboarding = false});
  ```
- `lib/features/services/pro_setup_screen.dart`: change to
  ```dart
  class ProSetupScreen extends ConsumerStatefulWidget {
    final bool fromOnboarding;
    const ProSetupScreen({super.key, this.fromOnboarding = false});
  ```
- `lib/features/homestay/host_setup_screen.dart`: change to
  ```dart
  class HostSetupScreen extends ConsumerStatefulWidget {
    final bool fromOnboarding;
    const HostSetupScreen({super.key, this.fromOnboarding = false});
  ```
(State classes reference `widget.fromOnboarding` in later tasks; nothing uses it yet.)

- [ ] **Step 6: Wire the three router builders** (`lib/core/router/app_router.dart`)

Add import: `import '../../features/auth/onboarding_arg.dart';`
Replace the three route lines:
```dart
      GoRoute(path: Routes.createPet, builder: (_, state) =>
          CreatePetScreen(fromOnboarding: (state.extra as OnboardingArg?)?.fromOnboarding ?? false)),
```
```dart
      GoRoute(path: Routes.proSetup, builder: (_, state) =>
          ProSetupScreen(fromOnboarding: (state.extra as OnboardingArg?)?.fromOnboarding ?? false)),
```
```dart
      GoRoute(path: Routes.hostSetup, builder: (_, state) =>
          HostSetupScreen(fromOnboarding: (state.extra as OnboardingArg?)?.fromOnboarding ?? false)),
```

- [ ] **Step 7: Update the existing location test** (`test/features/location_screen_test.dart`)

Its user is already `Role.petParent`, so it still lands on Create Pet — add the pro/host repo overrides so the router can build any destination without hitting real Firestore, and keep the final assertion. Add to its `overrides:` list:
```dart
      proRepositoryProvider.overrideWithValue(InMemoryProRepository()),
      homestayRepositoryProvider.overrideWithValue(InMemoryHomestayRepository()),
```

- [ ] **Step 8: Run the routing + location tests + full suite — expect PASS**

Run: `flutter test test/features/onboarding_routing_test.dart test/features/location_screen_test.dart && flutter test`

- [ ] **Step 9: `flutter analyze` clean, then commit**

```bash
git add lib/features/auth/onboarding_arg.dart lib/features/auth/location_screen.dart lib/features/pets/create_pet_screen.dart lib/features/services/pro_setup_screen.dart lib/features/homestay/host_setup_screen.dart lib/core/router/app_router.dart test/features/onboarding_routing_test.dart test/features/location_screen_test.dart
git commit -m "feat: route onboarding by role after Location (OnboardingArg seam)"
```

---

### Task 2: Create Pet — name required + Skip for now + nav fixes

**Files:**
- Modify: `lib/features/pets/create_pet_screen.dart`
- Modify: `test/features/create_pet_screen_test.dart`
- Test: `test/features/create_pet_optional_test.dart` (create)

**Interfaces:**
- Consumes: `widget.fromOnboarding` (Task 1).
- Produces: name-required guard on Finish; a "Skip for now" action (onboarding only) → Home writing nothing; corrected back nav.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/create_pet_optional_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/pets/create_pet_screen.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<InMemoryPetRepository> _pump(WidgetTester tester, {required bool onboarding}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final pets = InMemoryPetRepository();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    petRepositoryProvider.overrideWithValue(pets),
    storageRepositoryProvider.overrideWithValue(InMemoryStorageRepository()),
  ], initialLocation: Routes.createPet,
     extra: onboarding ? const CreatePetScreen(fromOnboarding: true) : null);
  // NOTE: extra can't pass a widget; use the router. Instead pump the screen directly:
  return pets;
}

void main() {
  testWidgets('Finish with a blank name shows an error and writes nothing', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pets = InMemoryPetRepository();
    await pumpPg(tester, ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        petRepositoryProvider.overrideWithValue(pets),
        storageRepositoryProvider.overrideWithValue(InMemoryStorageRepository()),
      ],
      child: const CreatePetScreen(fromOnboarding: true),
    ));
    await tester.tap(find.text('Finish & explore Pawgo'));
    await tester.pumpAndSettle();
    expect(find.text("Please enter your pet's name."), findsOneWidget);
    expect(await pets.watchMyPets('uid_me@x.com').first, isEmpty);
  });

  testWidgets('onboarding shows Skip for now; non-onboarding does not', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    await pumpPg(tester, ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: const CreatePetScreen(fromOnboarding: true),
    ));
    expect(find.text('Skip for now'), findsOneWidget);

    await pumpPg(tester, ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: const CreatePetScreen(fromOnboarding: false),
    ));
    expect(find.text('Skip for now'), findsNothing);
  });
}
```

**Note for the implementer:** `pumpPg` (in `test/support/pump.dart`) wraps a widget in a themed Scaffold but does NOT provide a `ProviderScope` or router. Wrap the screen in a `ProviderScope(overrides: …, child: …)` as shown. The `_pump` helper stub above is illustrative only — delete it and use the direct `pumpPg`+`ProviderScope` form in each test. The Skip navigation (which needs a router) is covered by the full-app test in Step 5 below, not here.

- [ ] **Step 2: Run it — expect FAIL** (no validation, no Skip)

Run: `flutter test test/features/create_pet_optional_test.dart`

- [ ] **Step 3: Add name validation + Skip to `create_pet_screen.dart`**

Add a field to the state class (near `_saving`):
```dart
  String? _nameError;
```
In `_finish`, at the very top (before the existing `setState(() => _saving = true);`), guard the name; then fold the error-clear into that existing setState. The current start of `_finish` is:
```dart
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    final area = ref.read(currentUserProfileProvider).value?.area ?? '';
    final name = _name.text.trim();
```
Change it to:
```dart
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = "Please enter your pet's name.");
      return;
    }
    setState(() { _saving = true; _nameError = null; });
    final area = ref.read(currentUserProfileProvider).value?.area ?? '';
```
(The name is now computed once, up top; delete the old `final name = _name.text.trim();` that sat after the area line.) `PgTextField` has **no** `onChanged` param, so the error clears on the next Finish attempt (via the `_nameError = null` above), matching how `pro_setup_screen.dart` clears its `_error` — not on keystroke. Show the error directly under the name field: keep the existing `PgTextField(label: 'Pet name', controller: _name, hint: 'Bruno'),` line unchanged and insert immediately after it:
```dart
                if (_nameError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(_nameError!, style: PgText.inter(13, FontWeight.w600, color: c.heart))),
```
(`c.heart` is the theme's form-error red used by `pro_setup_screen.dart:114`.)

Fix the back button: replace `onBack: () => context.go(Routes.signup)` with:
```dart
            onBack: () => widget.fromOnboarding
                ? context.go(Routes.location)
                : (context.canPop() ? context.pop() : context.go(Routes.home)),
```

Add the Skip action in the bottom bar, below the Finish button. Replace the bottom `Container(...child: PgPrimaryButton(...))` with a Column holding the button then (conditionally) the Skip:
```dart
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              PgPrimaryButton(
                label: _saving ? 'Saving…' : 'Finish & explore Pawgo',
                onPressed: _saving ? () {} : _finish),
              if (widget.fromOnboarding) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _saving ? null : () => context.go(Routes.home),
                  child: Text('Skip for now',
                    style: PgText.inter(13.5, FontWeight.w600, color: c.muted))),
              ],
            ]),
          ),
```

- [ ] **Step 4: Run the new tests — expect PASS**

Run: `flutter test test/features/create_pet_optional_test.dart`

- [ ] **Step 5: Add a full-app Skip-navigation test + keep the existing test green**

Append to `test/features/create_pet_optional_test.dart`:
```dart
  testWidgets('Skip for now (onboarding) reaches Home writing no pet', (tester) async {
    final auth = FakeAuthRepository();
    await auth.signUp(email: 'me@x.com', password: 'secret1');
    final pets = InMemoryPetRepository();
    await pumpPgApp(tester, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      petRepositoryProvider.overrideWithValue(pets),
      userRepositoryProvider.overrideWithValue(InMemoryUserRepository()),
    ], initialLocation: Routes.createPet, extra: const OnboardingArg(fromOnboarding: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('Skip for now'), findsNothing); // left the screen
    expect(await pets.watchMyPets('uid_me@x.com').first, isEmpty);
  });
```
Add imports to the test file: `import 'package:pet_aggregator_app/features/auth/onboarding_arg.dart';`. The existing `test/features/create_pet_screen_test.dart` already fills a pet name before Finish — confirm it still passes (name validation won't block it); if it taps Finish with an empty name, add a name entry first.

- [ ] **Step 6: Run create-pet tests + full suite — expect PASS**

Run: `flutter test test/features/create_pet_optional_test.dart test/features/create_pet_screen_test.dart && flutter test`

- [ ] **Step 7: `flutter analyze` clean, then commit**

```bash
git add lib/features/pets/create_pet_screen.dart test/features/create_pet_optional_test.dart test/features/create_pet_screen_test.dart
git commit -m "feat: Create Pet requires a name + Skip for now in onboarding"
```

---

### Task 3: Pro setup — Set up later + context-aware exit

**Files:**
- Modify: `lib/features/services/pro_setup_screen.dart`
- Test: `test/features/pro_setup_onboarding_test.dart` (create)

**Interfaces:**
- Consumes: `widget.fromOnboarding` (Task 1).
- Produces: `_exit()` → Home when onboarding else `Routes.services`; Save → `_exit()`; back → `_exit()`; "Set up later" (onboarding only) → Home.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/pro_setup_onboarding_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/auth/onboarding_arg.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<(FakeAuthRepository, InMemoryProRepository)> _pump(WidgetTester tester,
    {required bool onboarding}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Me',
      email: 'me@x.com', area: 'Khar', role: Role.servicePro));
  final pros = InMemoryProRepository();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    proRepositoryProvider.overrideWithValue(pros),
  ], initialLocation: Routes.proSetup,
     extra: onboarding ? const OnboardingArg(fromOnboarding: true) : null);
  await tester.pumpAndSettle();
  return (auth, pros);
}

void main() {
  testWidgets('onboarding shows Set up later and reaches Home writing no listing', (tester) async {
    final (auth, pros) = await _pump(tester, onboarding: true);
    expect(find.text('Set up later'), findsOneWidget);
    await tester.tap(find.text('Set up later'));
    await tester.pumpAndSettle();
    expect(find.text('Set up later'), findsNothing);
    expect(await pros.watchPro(auth.currentUser!.uid).first, isNull);
  });

  testWidgets('non-onboarding entry does not show Set up later', (tester) async {
    await _pump(tester, onboarding: false);
    expect(find.text('Set up later'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `flutter test test/features/pro_setup_onboarding_test.dart`

- [ ] **Step 3: Implement in `pro_setup_screen.dart`**

Add a helper method to the state class:
```dart
  void _exit() =>
      context.go(widget.fromOnboarding ? Routes.home : Routes.services);
```
In `_save`, replace `if (mounted) context.go(Routes.services);` with `if (mounted) _exit();`.
Change the app bar back: `onBack: () => context.go(Routes.services)` → `onBack: _exit`.
Add "Set up later" below the Save button. Replace the bottom `PgPrimaryButton(...)` container's child with a Column:
```dart
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              PgPrimaryButton(label: _saving ? 'Saving…' : 'Save listing',
                onPressed: _saving ? () {} : _save),
              if (widget.fromOnboarding) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _saving ? null : () => context.go(Routes.home),
                  child: Text('Set up later',
                    style: PgText.inter(13.5, FontWeight.w600, color: context.pg.muted))),
              ],
            ]),
```
(Confirm the exact current bottom-bar structure at `pro_setup_screen.dart:121-122` and wrap its `PgPrimaryButton` as above, preserving padding/decoration.)

- [ ] **Step 4: Run the new tests + full suite — expect PASS**

Run: `flutter test test/features/pro_setup_onboarding_test.dart test/features/pro_setup_screen_test.dart && flutter test`

- [ ] **Step 5: `flutter analyze` clean, then commit**

```bash
git add lib/features/services/pro_setup_screen.dart test/features/pro_setup_onboarding_test.dart
git commit -m "feat: Pro setup - Set up later + Home exit in onboarding"
```

---

### Task 4: Host setup — Set up later + context-aware exit

**Files:**
- Modify: `lib/features/homestay/host_setup_screen.dart`
- Test: `test/features/host_setup_onboarding_test.dart` (create)

**Interfaces:**
- Consumes: `widget.fromOnboarding` (Task 1).
- Produces: `_exit()` → Home when onboarding else `Routes.homestay`; Save → `_exit()`; back → onboarding `_exit()` else `canPop() ? pop() : go(Routes.homestay)`; "Set up later" (onboarding only) → Home.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/host_setup_onboarding_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/role.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import 'package:pet_aggregator_app/features/auth/onboarding_arg.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

Future<(FakeAuthRepository, InMemoryHomestayRepository)> _pump(WidgetTester tester,
    {required bool onboarding}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final users = InMemoryUserRepository();
  await users.createUser(UserProfile(uid: auth.currentUser!.uid, name: 'Me',
      email: 'me@x.com', area: 'Khar', role: Role.homestayHost));
  final homes = InMemoryHomestayRepository();
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(users),
    homestayRepositoryProvider.overrideWithValue(homes),
  ], initialLocation: Routes.hostSetup,
     extra: onboarding ? const OnboardingArg(fromOnboarding: true) : null);
  await tester.pumpAndSettle();
  return (auth, homes);
}

void main() {
  testWidgets('onboarding shows Set up later and reaches Home writing no listing', (tester) async {
    final (auth, homes) = await _pump(tester, onboarding: true);
    expect(find.text('Set up later'), findsOneWidget);
    await tester.tap(find.text('Set up later'));
    await tester.pumpAndSettle();
    expect(find.text('Set up later'), findsNothing);
    expect(await homes.watchHomestay(auth.currentUser!.uid).first, isNull);
  });

  testWidgets('non-onboarding entry does not show Set up later', (tester) async {
    await _pump(tester, onboarding: false);
    expect(find.text('Set up later'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `flutter test test/features/host_setup_onboarding_test.dart`

- [ ] **Step 3: Implement in `host_setup_screen.dart`**

Add the helper:
```dart
  void _exit() =>
      context.go(widget.fromOnboarding ? Routes.home : Routes.homestay);
```
In `_save`, replace `if (mounted) context.go(Routes.homestay);` with `if (mounted) _exit();`.
Change the app bar back:
```dart
            onBack: () => widget.fromOnboarding
                ? _exit()
                : (context.canPop() ? context.pop() : context.go(Routes.homestay)),
```
Add "Set up later" below the Save button (same pattern as Task 3) — wrap the bottom `PgPrimaryButton` (at `host_setup_screen.dart:141`) in a Column:
```dart
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              PgPrimaryButton(label: _saving ? 'Saving…' : 'Save listing',
                onPressed: _saving ? () {} : _save),
              if (widget.fromOnboarding) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _saving ? null : () => context.go(Routes.home),
                  child: Text('Set up later',
                    style: PgText.inter(13.5, FontWeight.w600, color: context.pg.muted))),
              ],
            ]),
```
(Confirm the current button's exact label — `host_setup_screen.dart:141` — and preserve the container padding/decoration.)

- [ ] **Step 4: Run the new tests + full suite — expect PASS**

Run: `flutter test test/features/host_setup_onboarding_test.dart test/features/host_setup_screen_test.dart && flutter test`

- [ ] **Step 5: `flutter analyze` clean, then commit**

```bash
git add lib/features/homestay/host_setup_screen.dart test/features/host_setup_onboarding_test.dart
git commit -m "feat: Host setup - Set up later + Home exit in onboarding"
```

---

### Task 5: Booking + Homestay-request empty-state CTA

**Files:**
- Modify: `lib/features/services/booking_screen.dart` (bottom button)
- Modify: `lib/features/homestay/homestay_request_screen.dart` (bottom button)
- Test: `test/features/booking_empty_pet_test.dart` (create)

**Interfaces:**
- Consumes: `myPetsProvider`, `Routes.createPet`.
- Produces: when petless, the bottom primary button becomes `Add a pet` → `context.push(Routes.createPet)` on both screens (was a silent no-op).

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/booking_empty_pet_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/router/routes.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/repositories/providers.dart';
import '../support/fakes.dart';
import '../support/pump.dart';

const _pro = Pro(uid: 'pro1', name: 'Aarav', area: 'Khar', bio: 'Walker',
    serviceType: ServiceType.walker, rate: 250, experienceYears: 3);
const _home = Homestay(uid: 'h1', homeName: "Meera's", hostName: 'Meera', area: 'Khar',
    about: '', homeType: HomeType.apartment, ratePerNight: 900);

Future<void> _pump(WidgetTester tester, String route, Object extra,
    {required bool withPet}) async {
  final auth = FakeAuthRepository();
  await auth.signUp(email: 'me@x.com', password: 'secret1');
  final uid = auth.currentUser!.uid;
  await pumpPgApp(tester, overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    petRepositoryProvider.overrideWithValue(
        withPet ? InMemoryPetRepository(fixturePets(uid)) : InMemoryPetRepository()),
    reviewRepositoryProvider.overrideWithValue(InMemoryReviewRepository()),
  ], initialLocation: route, extra: extra);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('booking: petless shows Add a pet CTA that opens Create Pet', (tester) async {
    await _pump(tester, Routes.booking, _pro, withPet: false);
    expect(find.text('Add a pet'), findsOneWidget);
    expect(find.text('Continue to payment'), findsNothing);
    await tester.tap(find.text('Add a pet'));
    await tester.pumpAndSettle();
    expect(find.text('Add your pet'), findsOneWidget); // Create Pet
  });

  testWidgets('booking: with a pet shows the normal Continue button', (tester) async {
    await _pump(tester, Routes.booking, _pro, withPet: true);
    expect(find.text('Continue to payment'), findsOneWidget);
    expect(find.text('Add a pet'), findsNothing);
  });

  testWidgets('homestay request: petless shows Add a pet CTA', (tester) async {
    await _pump(tester, Routes.hostRequest, _home, withPet: false);
    expect(find.text('Add a pet'), findsOneWidget);
    await tester.tap(find.text('Add a pet'));
    await tester.pumpAndSettle();
    expect(find.text('Add your pet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it — expect FAIL** (button is still the no-op Continue/Send)

Run: `flutter test test/features/booking_empty_pet_test.dart`

- [ ] **Step 3: Booking screen — make the bottom button an "Add a pet" CTA when petless**

In `lib/features/services/booking_screen.dart`, replace the bottom `PgPrimaryButton` (currently `label: 'Continue to payment', onPressed: pets.isEmpty ? () {} : () => _continue(pro, pets)`) with:
```dart
            child: pets.isEmpty
                ? PgPrimaryButton(
                    label: 'Add a pet', onPressed: () => context.push(Routes.createPet))
                : PgPrimaryButton(
                    label: 'Continue to payment', onPressed: () => _continue(pro, pets)),
```

- [ ] **Step 4: Homestay-request screen — same CTA**

In `lib/features/homestay/homestay_request_screen.dart`, replace the bottom `PgPrimaryButton` (currently `label: _saving ? 'Sending…' : 'Send request to $hostFirst', onPressed: (pets.isEmpty || _saving) ? () {} : () => _send(h, pets)`) with:
```dart
            child: pets.isEmpty
                ? PgPrimaryButton(
                    label: 'Add a pet', onPressed: () => context.push(Routes.createPet))
                : PgPrimaryButton(
                    label: _saving ? 'Sending…' : 'Send request to $hostFirst',
                    onPressed: _saving ? () {} : () => _send(h, pets)),
```

- [ ] **Step 5: Run the empty-state tests + full suite — expect PASS**

Run: `flutter test test/features/booking_empty_pet_test.dart && flutter test`

- [ ] **Step 6: `flutter analyze` clean, then commit**

```bash
git add lib/features/services/booking_screen.dart lib/features/homestay/homestay_request_screen.dart test/features/booking_empty_pet_test.dart
git commit -m "feat: petless booking flows offer Add a pet instead of a dead button"
```

---

### Task 6: Final verification + on-device flow walk

**Files:** none (fixes only if verification finds problems).

- [ ] **Step 1: Full local verification**

```bash
flutter analyze              # No issues found!
flutter test                 # all pass
flutter build apk --debug    # succeeds
```

- [ ] **Step 2: On-device flow walk (`flutter run -d emulator-5554`, three fresh signups)**

1. Sign up as **Pet Parent** → area → Create Pet: tap Finish with a blank name → error, no advance; enter a name → Home with the pet. Repeat and use **Skip for now** → Home, no pet.
2. Sign up as **Service Pro** → area → **Pro setup** (not Create Pet); **Set up later** → Home; or Save → Home with a live listing in Services.
3. Sign up as **Homestay Host** → area → **Host setup**; **Set up later** → Home; Save → Home.
4. As a petless pro, open a pro → Book → the primary button reads **Add a pet**; tap → Create Pet; add one → return and book normally.
5. Regression: from Profile, "Become a pro or host" → Pro/Host setup still returns to Services/Homestay list (not Home) on Save/back.

- [ ] **Step 3: Commit any verification fixes** (none expected).

---

## Self-review notes (checked against the spec)

- Spec coverage: role routing + OnboardingArg (T1), Create Pet name-required + Skip + back-nav fix (T2), Pro setup skip/exit (T3), Host setup skip/exit (T4), booking empty states (T5), DoD walk (T6). Profile "Add a pet" card is pre-existing — no task needed.
- Type consistency: `OnboardingArg({fromOnboarding})`, `fromOnboarding` param on all three screens, `_exit()` in both setup screens, exact copy strings (`Skip for now`, `Set up later`, `Please enter your pet's name.`, `Add a pet`) identical across tasks and tests.
- The `pumpPg` vs `pumpPgApp` distinction is called out in Task 2 (direct-widget tests need a manual `ProviderScope`; nav tests use `pumpPgApp` with `extra: OnboardingArg`). The blank-name test taps Finish, which returns early on empty name before any navigation, so it needs no router.
- Error color verified: `c.heart` (the form-error red used by `pro_setup_screen.dart:114`), matched in Task 2. `PgTextField` has no `onChanged`, so the error clears on the next Finish, not on keystroke — verified against the widget.
